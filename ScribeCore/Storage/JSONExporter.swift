import Foundation

public struct MeetingExport: Codable, Sendable {
    public let meeting: MeetingRecord
    public let transcript: [TranscriptSegment]
    public let notes: [UserNote]
    public let summaries: [AISummary]
    public let screenContexts: [ScreenContext]
    public let exportedAt: Date
}

public actor JSONExporter {
    public static let shared = JSONExporter()

    private let exportDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        exportDir = appSupport.appendingPathComponent("Scribe/exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
    }

    public func exportMeeting(id: UUID) async throws -> URL {
        let store = MeetingStore.shared

        guard let meeting = try await store.getMeeting(id: id) else {
            throw ExportError.meetingNotFound
        }

        let transcript = try await store.getTranscript(meetingId: id)
        let notes = try await store.getNotes(meetingId: id)
        let summaries = try await store.getSummaries(meetingId: id)
        let screenContexts = try await store.getScreenContexts(meetingId: id)

        let export = MeetingExport(
            meeting: meeting,
            transcript: transcript,
            notes: notes,
            summaries: summaries,
            screenContexts: screenContexts,
            exportedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(export)
        let fileURL = exportDir.appendingPathComponent("\(id.uuidString).json")
        try data.write(to: fileURL)

        return fileURL
    }

    public enum ExportError: Error {
        case meetingNotFound
    }
}
