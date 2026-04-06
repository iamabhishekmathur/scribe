import Foundation

/// Real-time AI chat during meetings with rolling transcript context
public actor ChatService {
    private var meetingId: UUID?
    private var chatHistory: [LLMMessage] = []
    private let maxContextSegments = 100

    public init() {}

    /// Start a chat session for a meeting
    public func start(meetingId: UUID) {
        self.meetingId = meetingId
        self.chatHistory = []
    }

    /// Ask a question about the current meeting
    public func ask(_ question: String) async throws -> String {
        guard let meetingId else {
            throw ChatServiceError.noActiveMeeting
        }

        let store = MeetingStore.shared
        let segments = try await store.getTranscript(meetingId: meetingId)
        let notes = try await store.getNotes(meetingId: meetingId)
        let screenContexts = try await store.getScreenContexts(meetingId: meetingId)

        // Build rolling context from recent transcript
        let recentSegments = segments.suffix(maxContextSegments)
        let transcript: String = recentSegments.map { seg in
            let speaker = seg.speaker ?? "Unknown"
            return "[\(speaker)] \(seg.text)"
        }.joined(separator: "\n")

        let notesText: String = notes.isEmpty ? "" :
            "\n\nUser's own notes from this meeting:\n" + notes.map(\.text).joined(separator: "\n")

        let screenText: String = screenContexts.isEmpty ? "" :
            "\n\nRecent screen content shared:\n" + screenContexts.suffix(5).map(\.extractedText).joined(separator: "\n---\n")

        let systemPrompt = """
        You are the user's executive assistant sitting alongside them in this meeting. They may be \
        multitasking, so your answers need to be immediately useful — no preamble, no hedging.

        Guidelines:
        - Lead with the answer, not the reasoning.
        - "What did I miss?" → Give a tight 3-5 bullet recap of what happened, who said what, and any decisions.
        - "What are they asking?" → Translate the current discussion into a clear, direct question.
        - Action items → Be specific: what, who, by when.
        - If you don't have enough context, say so in one sentence — don't speculate.
        - Use the user's notes as context for what they care about.
        - Keep responses short — the user is in a live meeting and scanning, not reading essays.
        """

        let contextMessage: String = "Current meeting transcript:\n\(transcript)\(notesText)\(screenText)"

        var messages: [LLMMessage] = [
            LLMMessage(role: .system, content: systemPrompt),
            LLMMessage(role: .user, content: contextMessage),
            LLMMessage(role: .assistant, content: "Ready. What do you need?"),
        ]

        // Add conversation history (last few exchanges)
        messages.append(contentsOf: chatHistory.suffix(10))
        messages.append(LLMMessage(role: .user, content: question))

        let provider = await LLMManager.shared.provider
        let response = try await provider.complete(messages: messages)

        // Store in chat history
        chatHistory.append(LLMMessage(role: .user, content: question))
        chatHistory.append(LLMMessage(role: .assistant, content: response))

        return response
    }

    public func stop() {
        meetingId = nil
        chatHistory = []
    }
}

public enum ChatServiceError: Error, LocalizedError {
    case noActiveMeeting

    public var errorDescription: String? {
        switch self {
        case .noActiveMeeting: return "No active meeting for chat"
        }
    }
}
