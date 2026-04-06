import Foundation

/// Enriches user notes with transcript context
public actor EnrichmentService {
    public static let shared = EnrichmentService()
    private init() {}

    /// Enrich a single note with surrounding transcript context
    public func enrichNote(noteId: UUID, meetingId: UUID) async throws {
        let store = MeetingStore.shared
        let notes = try await store.getNotes(meetingId: meetingId)
        guard var note = notes.first(where: { $0.id == noteId }) else { return }

        let segments = try await store.getTranscript(meetingId: meetingId)
        guard !segments.isEmpty else { return }

        // Find transcript context around the note's timestamp
        let windowSeconds: TimeInterval = 60
        let nearby = segments.filter { seg in
            abs(seg.startTime - note.timestamp) < windowSeconds
        }

        let context = nearby.map { seg in
            let speaker = seg.speaker ?? "Unknown"
            return "[\(speaker)] \(seg.text)"
        }.joined(separator: "\n")

        guard !context.isEmpty else { return }

        let provider = await LLMManager.shared.provider
        let prompt = """
        The user wrote this note during a meeting: "\(note.text)"

        Here is the transcript context around when the note was taken:
        \(context)

        Expand and enrich the note with relevant details from the transcript. \
        Keep the user's original intent but add context, specifics, and any \
        referenced decisions or action items. Be concise (2-4 sentences).
        """

        let enriched = try await provider.complete(messages: [
            LLMMessage(role: .system, content: "You enrich meeting notes with transcript context. Be concise and helpful."),
            LLMMessage(role: .user, content: prompt)
        ])

        note.enrichedText = enriched
        try await store.updateNote(note)
    }

    /// Enrich all notes for a meeting
    public func enrichAllNotes(meetingId: UUID) async throws {
        let notes = try await MeetingStore.shared.getNotes(meetingId: meetingId)
        for note in notes where note.enrichedText == nil {
            try await enrichNote(noteId: note.id, meetingId: meetingId)
        }
    }
}
