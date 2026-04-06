import Foundation
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "Summarization")

/// Post-meeting summarization: decisions, action items, topics, follow-ups
public actor SummarizationService {
    public static let shared = SummarizationService()
    private init() {}

    private let systemPrompt = """
    You are the user's executive assistant and chief of staff. You sat in on their meeting \
    and are now preparing a crisp debrief. Write like a sharp, trusted colleague — direct, \
    specific, and action-oriented. No filler. Use the user's own notes as signals for what \
    mattered most to them. Format your response in markdown.
    """

    /// Generate all summary types for a completed meeting
    public func summarizeMeeting(meetingId: UUID) async throws {
        let store = MeetingStore.shared
        let segments = try await store.getTranscript(meetingId: meetingId)
        let notes = try await store.getNotes(meetingId: meetingId)
        let screenContexts = try await store.getScreenContexts(meetingId: meetingId)

        guard !segments.isEmpty else {
            logger.info("No transcript segments, skipping summarization")
            return
        }

        let transcriptStr: String = segments.map { seg in
            let speaker = seg.speaker ?? "Unknown"
            return "[\(speaker)] \(seg.text)"
        }.joined(separator: "\n")

        let notesText: String = notes.isEmpty ? "" : "\n\n--- USER'S OWN NOTES (taken during the meeting) ---\n" + notes.map(\.text).joined(separator: "\n") + "\n--- END NOTES ---"
        let screenText: String = screenContexts.isEmpty ? "" : "\n\n--- SCREEN CONTENT SHARED ---\n" + screenContexts.map(\.extractedText).joined(separator: "\n---\n") + "\n--- END SCREEN CONTENT ---"

        let provider = await LLMManager.shared.provider
        let modelName = String(describing: type(of: provider))

        let segCount = segments.count
        let charCount: Int = transcriptStr.utf8.count
        logger.info("Summarizing meeting with \(segCount) segments, \(charCount) chars")

        // Generate full summary
        let fullPrompt: String = """
        Here is the full transcript of a meeting. Each line is formatted as [Speaker Name] followed by what they said.

        --- BEGIN TRANSCRIPT ---
        \(transcriptStr)
        --- END TRANSCRIPT ---
        \(notesText)\(screenText)

        Prepare a meeting debrief with these sections:

        ## Overview
        2-3 sentences: what was this meeting about, who drove it, and what was the outcome.

        ## Key Discussion Points
        The substantive topics discussed. For each, note the conclusion or open question.

        ## Decisions Made
        Numbered list of concrete decisions. Include who made or owns each decision. If none were made, say so briefly.

        ## Action Items
        Numbered list. Each item must have: what needs to happen, who owns it, and any deadline mentioned. Pay special attention to the user's notes — anything they wrote down likely matters to them.

        ## Follow-ups Needed
        Things that weren't resolved and need follow-up. Include suggested next steps where obvious.
        """

        let fullSummary = try await provider.complete(messages: [
            LLMMessage(role: .system, content: systemPrompt),
            LLMMessage(role: .user, content: fullPrompt)
        ])
        let sumLen: Int = fullSummary.utf8.count
        logger.info("Summary generated, \(sumLen) chars")
        try await store.saveSummary(AISummary(meetingId: meetingId, summaryType: "full", content: fullSummary, modelUsed: modelName))

        // Generate action items
        let actionPrompt: String = """
        Here is the meeting transcript and the user's own notes.

        --- BEGIN TRANSCRIPT ---
        \(transcriptStr)
        --- END TRANSCRIPT ---
        \(notesText)

        Extract every action item from this meeting. For each one:
        1. **What** needs to happen (be specific)
        2. **Who** owns it (use the speaker's name if mentioned, otherwise "TBD")
        3. **When** — any deadline or timeframe mentioned

        Pay close attention to the user's notes — if they wrote something down, it's likely important to them and may imply an action they're taking on.

        Format as a numbered markdown list. If genuinely no action items, say "No action items identified."
        """
        let actions = try await provider.complete(messages: [
            LLMMessage(role: .system, content: systemPrompt),
            LLMMessage(role: .user, content: actionPrompt)
        ])
        try await store.saveSummary(AISummary(meetingId: meetingId, summaryType: "action_items", content: actions, modelUsed: modelName))

        // Generate decisions
        let decisionsPrompt: String = """
        Here is the meeting transcript and the user's own notes.

        --- BEGIN TRANSCRIPT ---
        \(transcriptStr)
        --- END TRANSCRIPT ---
        \(notesText)

        Extract every decision that was made or agreed upon in this meeting. For each:
        1. **What** was decided
        2. **Who** made or approved it
        3. **Context** — brief reason or what it replaced, if mentioned

        Include implicit decisions (e.g., "let's go with option A" or "we'll skip that for now"). Also consider the user's notes — something they noted may reflect a decision they want to remember.

        Format as a numbered markdown list. If no decisions, say "No decisions identified."
        """
        let decisions = try await provider.complete(messages: [
            LLMMessage(role: .system, content: systemPrompt),
            LLMMessage(role: .user, content: decisionsPrompt)
        ])
        try await store.saveSummary(AISummary(meetingId: meetingId, summaryType: "decisions", content: decisions, modelUsed: modelName))
    }
}
