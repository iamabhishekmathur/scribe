import Foundation
import GRDB

public struct SearchResult: Identifiable, Sendable {
    public let id: UUID
    public let meetingId: UUID
    public let meetingTitle: String
    public let snippet: String
    public let source: SearchSource
    public let timestamp: Date

    public enum SearchSource: String, Sendable {
        case transcript
        case note
        case summary
    }
}

public actor SearchIndex {
    public static let shared = SearchIndex()

    private var db: Database { Database.shared }

    private init() {}

    public func search(query: String, limit: Int = 50) throws -> [SearchResult] {
        let ftsQuery = query
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { "\($0)*" }
            .joined(separator: " ")

        guard !ftsQuery.isEmpty else { return [] }

        return try db.reader.read { db in
            var results: [SearchResult] = []

            // Search transcripts
            let transcriptRows = try Row.fetchAll(db, sql: """
                SELECT ts.id, ts.meetingId, m.title, snippet(transcript_fts, 0, '<b>', '</b>', '...', 32) as snippet, m.startTime
                FROM transcript_fts
                JOIN transcript_segments ts ON ts.rowid = transcript_fts.rowid
                JOIN meetings m ON m.id = ts.meetingId
                WHERE transcript_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """, arguments: [ftsQuery, limit])

            for row in transcriptRows {
                results.append(SearchResult(
                    id: UUID(uuidString: row["id"]) ?? UUID(),
                    meetingId: UUID(uuidString: row["meetingId"]) ?? UUID(),
                    meetingTitle: row["title"],
                    snippet: row["snippet"],
                    source: .transcript,
                    timestamp: row["startTime"]
                ))
            }

            // Search notes
            let noteRows = try Row.fetchAll(db, sql: """
                SELECT un.id, un.meetingId, m.title, snippet(notes_fts, 0, '<b>', '</b>', '...', 32) as snippet, m.startTime
                FROM notes_fts
                JOIN user_notes un ON un.rowid = notes_fts.rowid
                JOIN meetings m ON m.id = un.meetingId
                WHERE notes_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """, arguments: [ftsQuery, limit])

            for row in noteRows {
                results.append(SearchResult(
                    id: UUID(uuidString: row["id"]) ?? UUID(),
                    meetingId: UUID(uuidString: row["meetingId"]) ?? UUID(),
                    meetingTitle: row["title"],
                    snippet: row["snippet"],
                    source: .note,
                    timestamp: row["startTime"]
                ))
            }

            // Search summaries
            let summaryRows = try Row.fetchAll(db, sql: """
                SELECT s.id, s.meetingId, m.title, snippet(summaries_fts, 0, '<b>', '</b>', '...', 32) as snippet, m.startTime
                FROM summaries_fts
                JOIN ai_summaries s ON s.rowid = summaries_fts.rowid
                JOIN meetings m ON m.id = s.meetingId
                WHERE summaries_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """, arguments: [ftsQuery, limit])

            for row in summaryRows {
                results.append(SearchResult(
                    id: UUID(uuidString: row["id"]) ?? UUID(),
                    meetingId: UUID(uuidString: row["meetingId"]) ?? UUID(),
                    meetingTitle: row["title"],
                    snippet: row["snippet"],
                    source: .summary,
                    timestamp: row["startTime"]
                ))
            }

            return results.sorted { $0.timestamp > $1.timestamp }
        }
    }
}
