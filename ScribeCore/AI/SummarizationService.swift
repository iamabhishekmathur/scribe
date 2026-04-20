import Foundation
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "Summarization")

/// Post-meeting summarization using configurable templates
public actor SummarizationService {
    public static let shared = SummarizationService()
    private init() {}

    /// Generate summary for a meeting using the specified template.
    /// Each section becomes a separate AISummary record.
    public func summarizeMeeting(meetingId: UUID, template: SummaryTemplate? = nil) async throws {
        let store = MeetingStore.shared
        let segments = try await store.getTranscript(meetingId: meetingId)
        let notes = try await store.getNotes(meetingId: meetingId)
        let screenContexts = try await store.getScreenContexts(meetingId: meetingId)

        guard !segments.isEmpty else {
            logger.info("No transcript segments, skipping summarization")
            return
        }

        let tmpl = template ?? SummaryTemplate.general

        let transcriptStr: String = segments.map { seg in
            let speaker = seg.speaker ?? "Unknown"
            return "[\(speaker)] \(seg.text)"
        }.joined(separator: "\n")

        let notesText: String = notes.isEmpty ? "" :
            "\n\n--- USER'S OWN NOTES (taken during the meeting) ---\n" +
            notes.map(\.text).joined(separator: "\n") +
            "\n--- END NOTES ---"
        let screenText: String = screenContexts.isEmpty ? "" :
            "\n\n--- SCREEN CONTENT SHARED ---\n" +
            screenContexts.map(\.extractedText).joined(separator: "\n---\n") +
            "\n--- END SCREEN CONTENT ---"

        let provider = await LLMManager.shared.provider
        let modelName = String(describing: type(of: provider))

        logger.info("Summarizing with template '\(tmpl.name)', \(segments.count) segments, \(tmpl.sections.count) sections")

        // Build a single prompt with all sections for efficiency
        var sectionDirectives = ""
        for section in tmpl.sections {
            sectionDirectives += "\n## \(section.heading)\n\(section.promptDirective)\n"
        }

        let prompt: String = """
        Here is the full transcript of a meeting. Each line is formatted as [Speaker Name] followed by what they said.

        --- BEGIN TRANSCRIPT ---
        \(transcriptStr)
        --- END TRANSCRIPT ---
        \(notesText)\(screenText)

        Prepare a meeting summary with exactly these sections:
        \(sectionDirectives)
        """

        let result = try await provider.complete(messages: [
            LLMMessage(role: .system, content: tmpl.systemPrompt),
            LLMMessage(role: .user, content: prompt)
        ])

        logger.info("Summary generated (\(tmpl.name)), \(result.utf8.count) chars")

        // Save as a single "full" summary tagged with the template ID
        try await store.saveSummary(AISummary(
            meetingId: meetingId,
            summaryType: tmpl.id,
            content: result,
            modelUsed: modelName
        ))
    }
}
