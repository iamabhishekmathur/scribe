import Foundation
import GRDB

public final class Database: Sendable {
    public static let shared = Database()

    private let dbPool: DatabasePool

    private init() {
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dbDir = appSupport.appendingPathComponent("Scribe", isDirectory: true)
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)

            let dbPath = dbDir.appendingPathComponent("scribe.sqlite").path

            var config = Configuration()
            config.prepareDatabase { db in
                // WAL mode for concurrent reads (important for HTTP server later)
                try db.execute(sql: "PRAGMA journal_mode=WAL")
                try db.execute(sql: "PRAGMA foreign_keys=ON")
            }

            dbPool = try DatabasePool(path: dbPath, configuration: config)
        } catch {
            fatalError("Failed to create database: \(error)")
        }
    }

    public func initialize() async throws {
        try await migrate()
    }

    public var reader: DatabaseReader { dbPool }
    public var writer: DatabaseWriter { dbPool }

    private func migrate() async throws {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_create_tables") { db in
            // Folders
            try db.create(table: "folders") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("parentId", .text).references("folders", onDelete: .setNull)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }

            // Meetings
            try db.create(table: "meetings") { t in
                t.primaryKey("id", .text).notNull()
                t.column("title", .text).notNull()
                t.column("startTime", .datetime).notNull()
                t.column("endTime", .datetime)
                t.column("duration", .double)
                t.column("calendarEventId", .text)
                t.column("meetingURL", .text)
                t.column("participants", .text)
                t.column("folderId", .text).references("folders", onDelete: .setNull)
                t.column("state", .text).notNull().defaults(to: "recording")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_meetings_startTime", on: "meetings", columns: ["startTime"])
            try db.create(index: "idx_meetings_state", on: "meetings", columns: ["state"])

            // Transcript segments
            try db.create(table: "transcript_segments") { t in
                t.primaryKey("id", .text).notNull()
                t.column("meetingId", .text).notNull().references("meetings", onDelete: .cascade)
                t.column("speaker", .text)
                t.column("speakerIndex", .integer)
                t.column("text", .text).notNull()
                t.column("startTime", .double).notNull()
                t.column("endTime", .double).notNull()
                t.column("confidence", .double)
                t.column("isFinal", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_transcript_meetingId", on: "transcript_segments", columns: ["meetingId"])

            // User notes
            try db.create(table: "user_notes") { t in
                t.primaryKey("id", .text).notNull()
                t.column("meetingId", .text).notNull().references("meetings", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("enrichedText", .text)
                t.column("timestamp", .double).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_notes_meetingId", on: "user_notes", columns: ["meetingId"])

            // AI summaries
            try db.create(table: "ai_summaries") { t in
                t.primaryKey("id", .text).notNull()
                t.column("meetingId", .text).notNull().references("meetings", onDelete: .cascade)
                t.column("summaryType", .text).notNull()
                t.column("content", .text).notNull()
                t.column("modelUsed", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_summaries_meetingId", on: "ai_summaries", columns: ["meetingId"])

            // Screen contexts
            try db.create(table: "screen_contexts") { t in
                t.primaryKey("id", .text).notNull()
                t.column("meetingId", .text).notNull().references("meetings", onDelete: .cascade)
                t.column("timestamp", .double).notNull()
                t.column("extractedText", .text).notNull()
                t.column("sourceDescription", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_screen_contexts_meetingId", on: "screen_contexts", columns: ["meetingId"])
        }

        // Full-text search index
        migrator.registerMigration("v1_fts5") { db in
            try db.create(virtualTable: "transcript_fts", using: FTS5()) { t in
                t.synchronize(withTable: "transcript_segments")
                t.column("text")
            }

            try db.create(virtualTable: "notes_fts", using: FTS5()) { t in
                t.synchronize(withTable: "user_notes")
                t.column("text")
            }

            try db.create(virtualTable: "summaries_fts", using: FTS5()) { t in
                t.synchronize(withTable: "ai_summaries")
                t.column("content")
            }
        }

        migrator.registerMigration("v2_speaker_profiles") { db in
            try db.create(table: "speaker_profiles") { t in
                t.primaryKey("id", .text).notNull()
                t.column("speakerIndex", .integer).notNull()
                t.column("name", .text).notNull()
                t.column("meetingId", .text).references("meetings", onDelete: .cascade)
                t.column("color", .text).notNull().defaults(to: "#007AFF")
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_speaker_profiles_meeting", on: "speaker_profiles", columns: ["meetingId", "speakerIndex"])
        }

        try await migrator.migrate(dbPool)
    }
}
