import Foundation
import GRDB

// MARK: - UUID Text Encoding Strategy
// GRDB encodes UUID as 16-byte BLOB by default via DatabaseValueConvertible,
// but Codable encodes UUID as uppercase string. This mismatch breaks update/fetch.
// We solve this by implementing EncodableRecord.encode(to:) explicitly so that
// UUID fields are always stored as text strings.

public struct MeetingRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var startTime: Date
    public var endTime: Date?
    public var duration: TimeInterval?
    public var calendarEventId: String?
    public var meetingURL: String?
    public var participants: String? // JSON array of participant names
    public var folderId: UUID?
    public var state: String // idle, recording, ended, processing, complete
    public var createdAt: Date
    public var updatedAt: Date

    public static var databaseTableName: String { "meetings" }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["title"] = title
        container["startTime"] = startTime
        container["endTime"] = endTime
        container["duration"] = duration
        container["calendarEventId"] = calendarEventId
        container["meetingURL"] = meetingURL
        container["participants"] = participants
        container["folderId"] = folderId?.uuidString
        container["state"] = state
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }

    public init(
        id: UUID = UUID(),
        title: String,
        startTime: Date = Date(),
        endTime: Date? = nil,
        duration: TimeInterval? = nil,
        calendarEventId: String? = nil,
        meetingURL: String? = nil,
        participants: String? = nil,
        folderId: UUID? = nil,
        state: String = "recording"
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.calendarEventId = calendarEventId
        self.meetingURL = meetingURL
        self.participants = participants
        self.folderId = folderId
        self.state = state
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

public struct TranscriptSegment: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public var id: UUID
    public var meetingId: UUID
    public var speaker: String?
    public var speakerIndex: Int?
    public var text: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var confidence: Double?
    public var isFinal: Bool
    public var createdAt: Date

    public static var databaseTableName: String { "transcript_segments" }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["meetingId"] = meetingId.uuidString
        container["speaker"] = speaker
        container["speakerIndex"] = speakerIndex
        container["text"] = text
        container["startTime"] = startTime
        container["endTime"] = endTime
        container["confidence"] = confidence
        container["isFinal"] = isFinal
        container["createdAt"] = createdAt
    }

    public init(
        id: UUID = UUID(),
        meetingId: UUID,
        speaker: String? = nil,
        speakerIndex: Int? = nil,
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Double? = nil,
        isFinal: Bool = true
    ) {
        self.id = id
        self.meetingId = meetingId
        self.speaker = speaker
        self.speakerIndex = speakerIndex
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.isFinal = isFinal
        self.createdAt = Date()
    }
}

public struct UserNote: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public var id: UUID
    public var meetingId: UUID
    public var text: String
    public var enrichedText: String?
    public var timestamp: TimeInterval
    public var createdAt: Date
    public var updatedAt: Date

    public static var databaseTableName: String { "user_notes" }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["meetingId"] = meetingId.uuidString
        container["text"] = text
        container["enrichedText"] = enrichedText
        container["timestamp"] = timestamp
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }

    public init(
        id: UUID = UUID(),
        meetingId: UUID,
        text: String,
        enrichedText: String? = nil,
        timestamp: TimeInterval
    ) {
        self.id = id
        self.meetingId = meetingId
        self.text = text
        self.enrichedText = enrichedText
        self.timestamp = timestamp
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

public struct AISummary: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public var id: UUID
    public var meetingId: UUID
    public var summaryType: String // "full", "action_items", "decisions", "topics", "follow_ups"
    public var content: String
    public var modelUsed: String
    public var createdAt: Date

    public static var databaseTableName: String { "ai_summaries" }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["meetingId"] = meetingId.uuidString
        container["summaryType"] = summaryType
        container["content"] = content
        container["modelUsed"] = modelUsed
        container["createdAt"] = createdAt
    }

    public init(
        id: UUID = UUID(),
        meetingId: UUID,
        summaryType: String,
        content: String,
        modelUsed: String
    ) {
        self.id = id
        self.meetingId = meetingId
        self.summaryType = summaryType
        self.content = content
        self.modelUsed = modelUsed
        self.createdAt = Date()
    }
}

public struct Folder: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var parentId: UUID?
    public var sortOrder: Int
    public var createdAt: Date

    public static var databaseTableName: String { "folders" }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["name"] = name
        container["parentId"] = parentId?.uuidString
        container["sortOrder"] = sortOrder
        container["createdAt"] = createdAt
    }

    public init(
        id: UUID = UUID(),
        name: String,
        parentId: UUID? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}

public struct ScreenContext: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public var id: UUID
    public var meetingId: UUID
    public var timestamp: TimeInterval
    public var extractedText: String
    public var sourceDescription: String?
    public var createdAt: Date

    public static var databaseTableName: String { "screen_contexts" }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["meetingId"] = meetingId.uuidString
        container["timestamp"] = timestamp
        container["extractedText"] = extractedText
        container["sourceDescription"] = sourceDescription
        container["createdAt"] = createdAt
    }

    public init(
        id: UUID = UUID(),
        meetingId: UUID,
        timestamp: TimeInterval,
        extractedText: String,
        sourceDescription: String? = nil
    ) {
        self.id = id
        self.meetingId = meetingId
        self.timestamp = timestamp
        self.extractedText = extractedText
        self.sourceDescription = sourceDescription
        self.createdAt = Date()
    }
}
