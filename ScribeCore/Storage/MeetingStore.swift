import Foundation
import GRDB

public actor MeetingStore {
    public static let shared = MeetingStore()

    private var db: Database { Database.shared }

    private init() {}

    // MARK: - Meetings

    public func createMeeting(_ meeting: MeetingRecord) throws {
        try db.writer.write { db in
            try meeting.insert(db)
        }
    }

    public func updateMeeting(_ meeting: MeetingRecord) throws {
        try db.writer.write { db in
            var updated = meeting
            updated.updatedAt = Date()
            try updated.update(db)
        }
    }

    public func endMeeting(id: UUID) throws {
        try db.writer.write { db in
            if var meeting = try MeetingRecord.fetchOne(db, key: id.uuidString) {
                meeting.endTime = Date()
                meeting.duration = meeting.endTime!.timeIntervalSince(meeting.startTime)
                meeting.state = "ended"
                meeting.updatedAt = Date()
                try meeting.update(db)
            }
        }
    }

    public func completeMeeting(id: UUID) throws {
        try db.writer.write { db in
            if var meeting = try MeetingRecord.fetchOne(db, key: id.uuidString) {
                meeting.state = "complete"
                meeting.updatedAt = Date()
                try meeting.update(db)
            }
        }
    }

    public func getMeeting(id: UUID) throws -> MeetingRecord? {
        try db.reader.read { db in
            try MeetingRecord.fetchOne(db, key: id.uuidString)
        }
    }

    public func getAllMeetings(limit: Int = 100, offset: Int = 0) throws -> [MeetingRecord] {
        try db.reader.read { db in
            try MeetingRecord
                .order(Column("startTime").desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }

    public func deleteMeeting(id: UUID) throws {
        try db.writer.write { db in
            _ = try MeetingRecord.deleteOne(db, key: id.uuidString)
        }
    }

    // MARK: - Transcript Segments

    public func addTranscriptSegment(_ segment: TranscriptSegment) throws {
        try db.writer.write { db in
            try segment.insert(db)
        }
    }

    public func addTranscriptSegments(_ segments: [TranscriptSegment]) throws {
        try db.writer.write { db in
            for segment in segments {
                try segment.insert(db)
            }
        }
    }

    public func getTranscript(meetingId: UUID) throws -> [TranscriptSegment] {
        try db.reader.read { db in
            try TranscriptSegment
                .filter(Column("meetingId") == meetingId.uuidString)
                .order(Column("startTime").asc)
                .fetchAll(db)
        }
    }

    // MARK: - User Notes

    public func addNote(_ note: UserNote) throws {
        try db.writer.write { db in
            try note.insert(db)
        }
    }

    public func updateNote(_ note: UserNote) throws {
        try db.writer.write { db in
            var updated = note
            updated.updatedAt = Date()
            try updated.update(db)
        }
    }

    public func getNotes(meetingId: UUID) throws -> [UserNote] {
        try db.reader.read { db in
            try UserNote
                .filter(Column("meetingId") == meetingId.uuidString)
                .order(Column("timestamp").asc)
                .fetchAll(db)
        }
    }

    // MARK: - AI Summaries

    public func saveSummary(_ summary: AISummary) throws {
        try db.writer.write { db in
            try summary.insert(db)
        }
    }

    public func getSummaries(meetingId: UUID) throws -> [AISummary] {
        try db.reader.read { db in
            try AISummary
                .filter(Column("meetingId") == meetingId.uuidString)
                .fetchAll(db)
        }
    }

    // MARK: - Screen Contexts

    public func addScreenContext(_ context: ScreenContext) throws {
        try db.writer.write { db in
            try context.insert(db)
        }
    }

    public func getScreenContexts(meetingId: UUID) throws -> [ScreenContext] {
        try db.reader.read { db in
            try ScreenContext
                .filter(Column("meetingId") == meetingId.uuidString)
                .order(Column("timestamp").asc)
                .fetchAll(db)
        }
    }

    // MARK: - Folders

    public func createFolder(_ folder: Folder) throws {
        try db.writer.write { db in
            try folder.insert(db)
        }
    }

    public func getFolders() throws -> [Folder] {
        try db.reader.read { db in
            try Folder.order(Column("sortOrder").asc).fetchAll(db)
        }
    }

    public func updateFolder(_ folder: Folder) throws {
        try db.writer.write { db in
            try folder.update(db)
        }
    }

    public func deleteFolder(id: UUID) throws {
        try db.writer.write { db in
            // Meetings in this folder get folderId set to NULL (via FK onDelete: .setNull)
            _ = try Folder.deleteOne(db, key: id.uuidString)
        }
    }

    public func reorderFolders(_ orderedIds: [UUID]) throws {
        try db.writer.write { db in
            for (index, folderId) in orderedIds.enumerated() {
                try db.execute(
                    sql: "UPDATE folders SET sortOrder = ? WHERE id = ?",
                    arguments: [index, folderId.uuidString]
                )
            }
        }
    }

    public func moveMeetingToFolder(meetingId: UUID, folderId: UUID?) throws {
        try db.writer.write { db in
            try db.execute(
                sql: "UPDATE meetings SET folderId = ?, updatedAt = ? WHERE id = ?",
                arguments: [folderId?.uuidString, Date(), meetingId.uuidString]
            )
        }
    }

    public func getMeetingsInFolder(folderId: UUID, limit: Int = 100) throws -> [MeetingRecord] {
        try db.reader.read { db in
            try MeetingRecord
                .filter(Column("folderId") == folderId.uuidString)
                .order(Column("startTime").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func folderMeetingCount(folderId: UUID) throws -> Int {
        try db.reader.read { db in
            try MeetingRecord
                .filter(Column("folderId") == folderId.uuidString)
                .fetchCount(db)
        }
    }
}
