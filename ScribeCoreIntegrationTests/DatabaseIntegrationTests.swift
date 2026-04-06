import Testing
@testable import ScribeCore
import Foundation
import GRDB

// MARK: - Test Database Helper

/// Creates an in-memory GRDB database with the same schema as Scribe's production database.
/// This avoids touching the real Application Support database during tests.
final class TestDatabaseHelper: @unchecked Sendable {
    let dbQueue: DatabaseQueue

    init() throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys=ON")
        }
        dbQueue = try DatabaseQueue(configuration: config) // in-memory

        try dbQueue.write { db in
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

            // FTS5 indexes
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
    }

    var reader: any DatabaseReader { dbQueue }
    var writer: any DatabaseWriter { dbQueue }
}

// MARK: - Meeting CRUD Tests

@Suite("Meeting Database CRUD Tests")
struct MeetingCRUDTests {

    @Test("Insert and fetch a meeting")
    func insertAndFetch() throws {
        let db = try TestDatabaseHelper()
        let meeting = MeetingRecord(title: "Standup")

        try db.dbQueue.write { conn in
            try meeting.insert(conn)
        }

        let fetched = try db.dbQueue.read { conn in
            try MeetingRecord.fetchOne(conn, key: meeting.id.uuidString)
        }

        #expect(fetched != nil)
        #expect(fetched?.title == "Standup")
        #expect(fetched?.state == "recording")
    }

    @Test("Update meeting state")
    func updateState() throws {
        let db = try TestDatabaseHelper()
        var meeting = MeetingRecord(title: "Standup")

        try db.dbQueue.write { conn in
            try meeting.insert(conn)
        }

        meeting.state = "ended"
        meeting.endTime = Date()
        meeting.updatedAt = Date()

        try db.dbQueue.write { conn in
            try meeting.update(conn)
        }

        let fetched = try db.dbQueue.read { conn in
            try MeetingRecord.fetchOne(conn, key: meeting.id.uuidString)
        }

        #expect(fetched?.state == "ended")
        #expect(fetched?.endTime != nil)
    }

    @Test("Delete meeting")
    func deleteMeeting() throws {
        let db = try TestDatabaseHelper()
        let meeting = MeetingRecord(title: "To Delete")

        try db.dbQueue.write { conn in
            try meeting.insert(conn)
        }

        try db.dbQueue.write { conn in
            _ = try MeetingRecord.deleteOne(conn, key: meeting.id.uuidString)
        }

        let fetched = try db.dbQueue.read { conn in
            try MeetingRecord.fetchOne(conn, key: meeting.id.uuidString)
        }
        #expect(fetched == nil)
    }

    @Test("Cascade delete removes transcript segments")
    func cascadeDelete() throws {
        let db = try TestDatabaseHelper()
        let meeting = MeetingRecord(title: "Meeting with Transcript")

        try db.dbQueue.write { conn in
            try meeting.insert(conn)

            let segment = TranscriptSegment(
                meetingId: meeting.id,
                text: "Hello",
                startTime: 0,
                endTime: 1
            )
            try segment.insert(conn)
        }

        // Verify segment exists
        let segmentsBefore = try db.dbQueue.read { conn in
            try TranscriptSegment.filter(Column("meetingId") == meeting.id.uuidString).fetchCount(conn)
        }
        #expect(segmentsBefore == 1)

        // Delete meeting
        try db.dbQueue.write { conn in
            _ = try MeetingRecord.deleteOne(conn, key: meeting.id.uuidString)
        }

        // Segments should be cascaded
        let segmentsAfter = try db.dbQueue.read { conn in
            try TranscriptSegment.filter(Column("meetingId") == meeting.id.uuidString).fetchCount(conn)
        }
        #expect(segmentsAfter == 0)
    }

    @Test("Cascade delete removes notes, summaries, screen contexts")
    func cascadeDeleteAll() throws {
        let db = try TestDatabaseHelper()
        let meeting = MeetingRecord(title: "Full Meeting")

        try db.dbQueue.write { conn in
            try meeting.insert(conn)

            try UserNote(meetingId: meeting.id, text: "Note", timestamp: 1).insert(conn)
            try AISummary(meetingId: meeting.id, summaryType: "full", content: "Summary", modelUsed: "test").insert(conn)
            try ScreenContext(meetingId: meeting.id, timestamp: 1, extractedText: "Screen").insert(conn)
        }

        // Delete meeting - should cascade to all children
        try db.dbQueue.write { conn in
            _ = try MeetingRecord.deleteOne(conn, key: meeting.id.uuidString)
        }

        try db.dbQueue.read { conn in
            let notes = try UserNote.filter(Column("meetingId") == meeting.id.uuidString).fetchCount(conn)
            let summaries = try AISummary.filter(Column("meetingId") == meeting.id.uuidString).fetchCount(conn)
            let contexts = try ScreenContext.filter(Column("meetingId") == meeting.id.uuidString).fetchCount(conn)
            #expect(notes == 0)
            #expect(summaries == 0)
            #expect(contexts == 0)
        }
    }

    @Test("Fetch meetings ordered by startTime descending")
    func orderedFetch() throws {
        let db = try TestDatabaseHelper()
        let now = Date()

        let m1 = MeetingRecord(title: "Old", startTime: now.addingTimeInterval(-3600))
        let m2 = MeetingRecord(title: "Middle", startTime: now.addingTimeInterval(-1800))
        let m3 = MeetingRecord(title: "Recent", startTime: now)

        try db.dbQueue.write { conn in
            try m1.insert(conn)
            try m2.insert(conn)
            try m3.insert(conn)
        }

        let meetings = try db.dbQueue.read { conn in
            try MeetingRecord
                .order(Column("startTime").desc)
                .fetchAll(conn)
        }

        #expect(meetings.count == 3)
        #expect(meetings[0].title == "Recent")
        #expect(meetings[1].title == "Middle")
        #expect(meetings[2].title == "Old")
    }

    @Test("Pagination with limit and offset")
    func pagination() throws {
        let db = try TestDatabaseHelper()

        for i in 0..<10 {
            let meeting = MeetingRecord(
                title: "Meeting \(i)",
                startTime: Date().addingTimeInterval(Double(i) * 60)
            )
            try db.dbQueue.write { conn in
                try meeting.insert(conn)
            }
        }

        let page = try db.dbQueue.read { conn in
            try MeetingRecord
                .order(Column("startTime").desc)
                .limit(3, offset: 2)
                .fetchAll(conn)
        }
        #expect(page.count == 3)
    }

    @Test("Foreign key constraint on folderId")
    func folderForeignKey() throws {
        let db = try TestDatabaseHelper()

        // Insert meeting with non-existent folderId should fail with FK constraint
        let meeting = MeetingRecord(title: "Bad FK", folderId: UUID())

        #expect(throws: (any Error).self) {
            try db.dbQueue.write { conn in
                try meeting.insert(conn)
            }
        }
    }

    @Test("Folder deletion sets meeting folderId to null")
    func folderDeletionSetNull() throws {
        let db = try TestDatabaseHelper()
        let folder = Folder(name: "Work")

        try db.dbQueue.write { conn in
            try folder.insert(conn)
        }

        let meeting = MeetingRecord(title: "Work meeting", folderId: folder.id)
        try db.dbQueue.write { conn in
            try meeting.insert(conn)
        }

        // Delete folder
        try db.dbQueue.write { conn in
            _ = try Folder.deleteOne(conn, key: folder.id.uuidString)
        }

        let fetched = try db.dbQueue.read { conn in
            try MeetingRecord.fetchOne(conn, key: meeting.id.uuidString)
        }
        #expect(fetched?.folderId == nil, "folderId should be set to NULL on folder deletion")
    }
}

// MARK: - Transcript Segment Database Tests

@Suite("Transcript Segment Database Tests")
struct TranscriptSegmentDBTests {

    @Test("Insert and fetch segments in chronological order")
    func chronologicalOrder() throws {
        let db = try TestDatabaseHelper()
        let meeting = MeetingRecord(title: "Test")

        try db.dbQueue.write { conn in
            try meeting.insert(conn)

            // Insert out of order
            try TranscriptSegment(meetingId: meeting.id, text: "Third", startTime: 10, endTime: 15).insert(conn)
            try TranscriptSegment(meetingId: meeting.id, text: "First", startTime: 0, endTime: 5).insert(conn)
            try TranscriptSegment(meetingId: meeting.id, text: "Second", startTime: 5, endTime: 10).insert(conn)
        }

        let segments = try db.dbQueue.read { conn in
            try TranscriptSegment
                .filter(Column("meetingId") == meeting.id.uuidString)
                .order(Column("startTime").asc)
                .fetchAll(conn)
        }

        #expect(segments.count == 3)
        #expect(segments[0].text == "First")
        #expect(segments[1].text == "Second")
        #expect(segments[2].text == "Third")
    }

    @Test("Batch insert multiple segments")
    func batchInsert() throws {
        let db = try TestDatabaseHelper()
        let meeting = MeetingRecord(title: "Test")

        let segments = (0..<100).map { i in
            TranscriptSegment(
                meetingId: meeting.id,
                speaker: "Speaker \(i % 3)",
                text: "Segment \(i)",
                startTime: Double(i),
                endTime: Double(i) + 1.0
            )
        }

        try db.dbQueue.write { conn in
            try meeting.insert(conn)
            for segment in segments {
                try segment.insert(conn)
            }
        }

        let count = try db.dbQueue.read { conn in
            try TranscriptSegment.filter(Column("meetingId") == meeting.id.uuidString).fetchCount(conn)
        }
        #expect(count == 100)
    }

    @Test("Foreign key prevents orphan segments")
    func foreignKeyConstraint() throws {
        let db = try TestDatabaseHelper()
        let segment = TranscriptSegment(meetingId: UUID(), text: "Orphan", startTime: 0, endTime: 1)

        #expect(throws: (any Error).self) {
            try db.dbQueue.write { conn in
                try segment.insert(conn)
            }
        }
    }

    @Test("Unicode text in transcripts")
    func unicodeText() throws {
        let db = try TestDatabaseHelper()
        let meeting = MeetingRecord(title: "International")

        let testTexts = [
            "普通话测试",        // Chinese
            "日本語テスト",       // Japanese
            "한국어 테스트",      // Korean
            "العربية اختبار",    // Arabic
            "Ñoño español",    // Spanish accents
            "🎙️📝💡",          // Emoji
        ]

        try db.dbQueue.write { conn in
            try meeting.insert(conn)
            for (i, text) in testTexts.enumerated() {
                try TranscriptSegment(
                    meetingId: meeting.id,
                    text: text,
                    startTime: Double(i),
                    endTime: Double(i) + 1
                ).insert(conn)
            }
        }

        let segments = try db.dbQueue.read { conn in
            try TranscriptSegment
                .filter(Column("meetingId") == meeting.id.uuidString)
                .order(Column("startTime").asc)
                .fetchAll(conn)
        }

        #expect(segments.count == testTexts.count)
        for (segment, expected) in zip(segments, testTexts) {
            #expect(segment.text == expected)
        }
    }
}

// MARK: - FTS5 Search Tests

@Suite("Full-Text Search Tests")
struct FTSSearchTests {

    @Test("Search finds transcript text")
    func searchTranscript() throws {
        let db = try TestDatabaseHelper()
        let meeting = MeetingRecord(title: "Search Test Meeting")

        try db.dbQueue.write { conn in
            try meeting.insert(conn)
            try TranscriptSegment(
                meetingId: meeting.id,
                text: "We need to discuss the quarterly budget review",
                startTime: 0,
                endTime: 5
            ).insert(conn)
        }

        let results = try db.dbQueue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT ts.id, ts.text
                FROM transcript_fts
                JOIN transcript_segments ts ON ts.rowid = transcript_fts.rowid
                WHERE transcript_fts MATCH ?
                """, arguments: ["budget*"])
        }

        #expect(results.count == 1)
    }

    @Test("Search finds notes")
    func searchNotes() throws {
        let db = try TestDatabaseHelper()
        let meeting = MeetingRecord(title: "Notes Test")

        try db.dbQueue.write { conn in
            try meeting.insert(conn)
            try UserNote(
                meetingId: meeting.id,
                text: "Action item: deploy the new authentication service by Friday",
                timestamp: 30
            ).insert(conn)
        }

        let results = try db.dbQueue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT un.id, un.text
                FROM notes_fts
                JOIN user_notes un ON un.rowid = notes_fts.rowid
                WHERE notes_fts MATCH ?
                """, arguments: ["authentication*"])
        }

        #expect(results.count == 1)
    }

    @Test("Search finds AI summaries")
    func searchSummaries() throws {
        let db = try TestDatabaseHelper()
        let meeting = MeetingRecord(title: "Summary Test")

        try db.dbQueue.write { conn in
            try meeting.insert(conn)
            try AISummary(
                meetingId: meeting.id,
                summaryType: "full",
                content: "The team decided to migrate from PostgreSQL to DynamoDB for the user service",
                modelUsed: "claude-3-opus"
            ).insert(conn)
        }

        let results = try db.dbQueue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT s.id, s.content
                FROM summaries_fts
                JOIN ai_summaries s ON s.rowid = summaries_fts.rowid
                WHERE summaries_fts MATCH ?
                """, arguments: ["migrate*"])
        }

        #expect(results.count == 1)
    }

    @Test("Search returns no results for non-matching query")
    func searchNoResults() throws {
        let db = try TestDatabaseHelper()
        let meeting = MeetingRecord(title: "Empty")

        try db.dbQueue.write { conn in
            try meeting.insert(conn)
            try TranscriptSegment(meetingId: meeting.id, text: "Hello world", startTime: 0, endTime: 1).insert(conn)
        }

        let results = try db.dbQueue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT ts.id FROM transcript_fts
                JOIN transcript_segments ts ON ts.rowid = transcript_fts.rowid
                WHERE transcript_fts MATCH ?
                """, arguments: ["zzzznonexistent*"])
        }

        #expect(results.isEmpty)
    }

    @Test("FTS stays synchronized after insert")
    func ftsSynchronized() throws {
        let db = try TestDatabaseHelper()
        let meeting = MeetingRecord(title: "Sync Test")

        try db.dbQueue.write { conn in
            try meeting.insert(conn)
        }

        // Insert segment
        try db.dbQueue.write { conn in
            try TranscriptSegment(meetingId: meeting.id, text: "synchronization test phrase", startTime: 0, endTime: 1).insert(conn)
        }

        // FTS should pick it up immediately due to synchronize()
        let results = try db.dbQueue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT * FROM transcript_fts WHERE transcript_fts MATCH ?
                """, arguments: ["synchronization*"])
        }

        #expect(results.count == 1)
    }
}

// MARK: - Folder Tests

@Suite("Folder Database Tests")
struct FolderDBTests {

    @Test("Nested folders with parent reference")
    func nestedFolders() throws {
        let db = try TestDatabaseHelper()
        let parent = Folder(name: "Work")
        let child = Folder(name: "Q1 2026", parentId: parent.id, sortOrder: 1)

        try db.dbQueue.write { conn in
            try parent.insert(conn)
            try child.insert(conn)
        }

        let fetched = try db.dbQueue.read { conn in
            try Folder.fetchOne(conn, key: child.id.uuidString)
        }

        #expect(fetched?.parentId == parent.id)
    }

    @Test("Parent deletion sets child parentId to null")
    func parentDeletionSetsNull() throws {
        let db = try TestDatabaseHelper()
        let parent = Folder(name: "Parent")
        let child = Folder(name: "Child", parentId: parent.id)

        try db.dbQueue.write { conn in
            try parent.insert(conn)
            try child.insert(conn)
        }

        try db.dbQueue.write { conn in
            _ = try Folder.deleteOne(conn, key: parent.id.uuidString)
        }

        let fetched = try db.dbQueue.read { conn in
            try Folder.fetchOne(conn, key: child.id.uuidString)
        }
        #expect(fetched?.parentId == nil)
    }

    @Test("Sort order is respected")
    func sortOrder() throws {
        let db = try TestDatabaseHelper()

        let f1 = Folder(name: "C", sortOrder: 2)
        let f2 = Folder(name: "A", sortOrder: 0)
        let f3 = Folder(name: "B", sortOrder: 1)

        try db.dbQueue.write { conn in
            try f1.insert(conn)
            try f2.insert(conn)
            try f3.insert(conn)
        }

        let folders = try db.dbQueue.read { conn in
            try Folder.order(Column("sortOrder").asc).fetchAll(conn)
        }

        #expect(folders[0].name == "A")
        #expect(folders[1].name == "B")
        #expect(folders[2].name == "C")
    }
}

// MARK: - UUID Encoding Diagnostic

@Suite("UUID Encoding Diagnostic")
struct UUIDEncodingTests {

    @Test("UUIDs are stored as text via custom encode(to:)")
    func uuidStorageFormat() throws {
        let db = try TestDatabaseHelper()
        let meeting = MeetingRecord(title: "UUID Test")

        try db.dbQueue.write { conn in
            try meeting.insert(conn)
        }

        // Check raw storage via SQL
        let rows = try db.dbQueue.read { conn in
            try Row.fetchAll(conn, sql: "SELECT typeof(id) as id_type, id FROM meetings")
        }

        let storedType: String = rows[0]["id_type"]
        let storedId: String = rows[0]["id"]
        // Our custom encode(to:) stores UUID as text (uppercase)
        #expect(storedType == "text", "UUID should be stored as text, got: \(storedType)")
        #expect(storedId == meeting.id.uuidString, "Stored UUID should match uuidString")

        // Fetch by uuidString should work
        let fetched = try db.dbQueue.read { conn in
            try MeetingRecord.fetchOne(conn, key: meeting.id.uuidString)
        }
        #expect(fetched != nil, "Fetching by .uuidString should work")
    }
}

// MARK: - Edge Cases and Data Integrity

@Suite("Data Integrity Edge Cases")
struct DataIntegrityTests {

    @Test("Duplicate UUID insert fails")
    func duplicateUUID() throws {
        let db = try TestDatabaseHelper()
        let id = UUID()
        let m1 = MeetingRecord(id: id, title: "First")
        let m2 = MeetingRecord(id: id, title: "Duplicate")

        try db.dbQueue.write { conn in
            try m1.insert(conn)
        }

        #expect(throws: (any Error).self) {
            try db.dbQueue.write { conn in
                try m2.insert(conn)
            }
        }
    }

    @Test("Very long text in transcript")
    func longTranscriptText() throws {
        let db = try TestDatabaseHelper()
        let meeting = MeetingRecord(title: "Long")
        let longText = String(repeating: "word ", count: 100000) // ~500KB

        try db.dbQueue.write { conn in
            try meeting.insert(conn)
            try TranscriptSegment(
                meetingId: meeting.id,
                text: longText,
                startTime: 0,
                endTime: 1
            ).insert(conn)
        }

        let fetched = try db.dbQueue.read { conn in
            try TranscriptSegment
                .filter(Column("meetingId") == meeting.id.uuidString)
                .fetchOne(conn)
        }
        #expect(fetched?.text.count == longText.count)
    }

    @Test("Special characters in meeting title")
    func specialCharacters() throws {
        let db = try TestDatabaseHelper()
        let titles = [
            "Meeting with 'single quotes'",
            "Meeting with \"double quotes\"",
            "Meeting with \\ backslash",
            "Meeting with % percent",
            "Meeting with _ underscore",
            "O'Brien's Planning",
            "DROP TABLE meetings; --",  // SQL injection attempt
        ]

        for title in titles {
            let meeting = MeetingRecord(title: title)
            try db.dbQueue.write { conn in
                try meeting.insert(conn)
            }

            let fetched = try db.dbQueue.read { conn in
                try MeetingRecord.fetchOne(conn, key: meeting.id.uuidString)
            }
            #expect(fetched?.title == title, "Title should be preserved exactly: \(title)")
        }
    }

    @Test("Concurrent reads don't block")
    func concurrentReads() async throws {
        let db = try TestDatabaseHelper()
        let meeting = MeetingRecord(title: "Concurrent")

        try await db.dbQueue.write { conn in
            try meeting.insert(conn)
        }

        // Run multiple concurrent reads
        await withTaskGroup(of: MeetingRecord?.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try? db.dbQueue.read { conn in
                        try MeetingRecord.fetchOne(conn, key: meeting.id.uuidString)
                    }
                }
            }

            var results: [MeetingRecord?] = []
            for await result in group {
                results.append(result)
            }
            #expect(results.count == 10)
            #expect(results.allSatisfy { $0?.title == "Concurrent" })
        }
    }
}

// MARK: - JSON Export Tests

@Suite("JSON Export Format Tests")
struct JSONExportFormatTests {

    @Test("Export produces valid JSON with ISO8601 dates")
    func exportFormat() throws {
        let meetingId = UUID()
        let export = MeetingExport(
            meeting: MeetingRecord(id: meetingId, title: "Export Test"),
            transcript: [
                TranscriptSegment(meetingId: meetingId, text: "Hello", startTime: 0, endTime: 1)
            ],
            notes: [],
            summaries: [],
            screenContexts: [],
            exportedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(export)
        let jsonString = String(data: data, encoding: .utf8)!

        // Should contain ISO8601 date format
        #expect(jsonString.contains("T"))
        #expect(jsonString.contains("Z") || jsonString.contains("+"))

        // Should be valid JSON
        let parsed = try JSONSerialization.jsonObject(with: data)
        #expect(parsed is [String: Any])
    }

    @Test("Export round-trip preserves data integrity")
    func exportRoundTrip() throws {
        let meetingId = UUID()
        let now = Date()

        let original = MeetingExport(
            meeting: MeetingRecord(
                id: meetingId,
                title: "Full Export",
                endTime: now,
                duration: 3600,
                calendarEventId: "cal-123",
                meetingURL: "https://meet.google.com/abc",
                participants: "[\"Alice\",\"Bob\"]",
                state: "complete"
            ),
            transcript: (0..<5).map { i in
                TranscriptSegment(
                    meetingId: meetingId,
                    speaker: "Speaker \(i % 2)",
                    text: "Segment \(i) content",
                    startTime: Double(i) * 10,
                    endTime: Double(i) * 10 + 9
                )
            },
            notes: [
                UserNote(meetingId: meetingId, text: "Key decision made", timestamp: 30)
            ],
            summaries: [
                AISummary(meetingId: meetingId, summaryType: "full", content: "Team discussed...", modelUsed: "claude-3-opus"),
                AISummary(meetingId: meetingId, summaryType: "action_items", content: "1. Deploy\n2. Review", modelUsed: "claude-3-opus"),
            ],
            screenContexts: [
                ScreenContext(meetingId: meetingId, timestamp: 45, extractedText: "Revenue: $1.2M")
            ],
            exportedAt: now
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeetingExport.self, from: data)

        #expect(decoded.meeting.id == meetingId)
        #expect(decoded.meeting.title == "Full Export")
        #expect(decoded.meeting.calendarEventId == "cal-123")
        #expect(decoded.transcript.count == 5)
        #expect(decoded.notes.count == 1)
        #expect(decoded.summaries.count == 2)
        #expect(decoded.screenContexts.count == 1)
    }
}
