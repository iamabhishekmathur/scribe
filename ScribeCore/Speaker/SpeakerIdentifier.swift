import Foundation
import GRDB

/// Speaker profile for renaming "Speaker 0" → "Alice"
public struct SpeakerProfile: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public var id: UUID
    public var speakerIndex: Int
    public var name: String
    public var meetingId: UUID?  // nil = global profile
    public var color: String     // hex color
    public var createdAt: Date

    public static var databaseTableName: String { "speaker_profiles" }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["speakerIndex"] = speakerIndex
        container["name"] = name
        container["meetingId"] = meetingId?.uuidString
        container["color"] = color
        container["createdAt"] = createdAt
    }

    public init(
        id: UUID = UUID(),
        speakerIndex: Int,
        name: String,
        meetingId: UUID? = nil,
        color: String = "#007AFF"
    ) {
        self.id = id
        self.speakerIndex = speakerIndex
        self.name = name
        self.meetingId = meetingId
        self.color = color
        self.createdAt = Date()
    }
}

/// Manages speaker identification and profile resolution
public actor SpeakerIdentifier {
    public static let shared = SpeakerIdentifier()

    private static let defaultColors = [
        "#007AFF", "#34C759", "#FF9500", "#AF52DE",
        "#FF2D55", "#5AC8FA", "#5856D6", "#00C7BE"
    ]

    private init() {}

    /// Get display name for a speaker index in a meeting
    public func displayName(speakerIndex: Int, meetingId: UUID) async -> String {
        // Check meeting-specific profile first
        if let profile = try? await getProfile(speakerIndex: speakerIndex, meetingId: meetingId) {
            return profile.name
        }
        // Check global profile
        if let profile = try? await getProfile(speakerIndex: speakerIndex, meetingId: nil) {
            return profile.name
        }
        // Use 1-based numbering for non-technical users; index 0 = "You" (handled in UI)
        return speakerIndex == 0 ? "You" : "Speaker \(speakerIndex)"
    }

    /// Get color for a speaker index
    public func color(speakerIndex: Int) -> String {
        Self.defaultColors[speakerIndex % Self.defaultColors.count]
    }

    /// Rename a speaker
    public func renameSpeaker(speakerIndex: Int, name: String, meetingId: UUID?) async throws {
        let db = Database.shared

        // Check if profile exists
        if var existing = try getProfile(speakerIndex: speakerIndex, meetingId: meetingId) {
            existing.name = name
            let updated = existing
            try await db.writer.write { conn in
                try updated.update(conn)
            }
        } else {
            let profile = SpeakerProfile(
                speakerIndex: speakerIndex,
                name: name,
                meetingId: meetingId,
                color: color(speakerIndex: speakerIndex)
            )
            try await db.writer.write { conn in
                try profile.insert(conn)
            }
        }
    }

    /// Get all speaker profiles for a meeting
    public func getProfiles(meetingId: UUID) throws -> [SpeakerProfile] {
        try Database.shared.reader.read { db in
            try SpeakerProfile
                .filter(Column("meetingId") == meetingId.uuidString)
                .order(Column("speakerIndex").asc)
                .fetchAll(db)
        }
    }

    private func getProfile(speakerIndex: Int, meetingId: UUID?) throws -> SpeakerProfile? {
        try Database.shared.reader.read { db in
            if let meetingId {
                return try SpeakerProfile
                    .filter(Column("speakerIndex") == speakerIndex && Column("meetingId") == meetingId.uuidString)
                    .fetchOne(db)
            } else {
                return try SpeakerProfile
                    .filter(Column("speakerIndex") == speakerIndex && Column("meetingId") == nil)
                    .fetchOne(db)
            }
        }
    }
}
