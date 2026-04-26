import Foundation
import GRDB

public struct SearchResult: Identifiable, Sendable {
    public let id: UUID
    public let meetingId: UUID
    public let meetingTitle: String
    public let snippet: String
    public let source: SearchSource
    public let timestamp: Date
    public let speaker: String?

    public enum SearchSource: String, Sendable {
        case transcript
        case note
        case summary
        case title
        case screen
        case participant
    }

    public init(id: UUID, meetingId: UUID, meetingTitle: String, snippet: String, source: SearchSource, timestamp: Date, speaker: String? = nil) {
        self.id = id
        self.meetingId = meetingId
        self.meetingTitle = meetingTitle
        self.snippet = snippet
        self.source = source
        self.timestamp = timestamp
        self.speaker = speaker
    }
}

public actor SearchIndex {
    public static let shared = SearchIndex()

    private var db: Database { Database.shared }

    /// Common English stop words that add noise to FTS queries
    private static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "is", "are", "was", "were", "be", "been",
        "being", "have", "has", "had", "do", "does", "did", "will", "would",
        "could", "should", "may", "might", "shall", "can", "need", "must",
        "it", "its", "he", "she", "they", "them", "we", "us", "i", "me", "my",
        "you", "your", "this", "that", "these", "those", "which", "what",
        "who", "whom", "where", "when", "why", "how", "not", "no", "nor",
        "if", "then", "than", "so", "just", "also", "very", "too",
        "about", "up", "out", "all", "any", "some",
    ]

    /// Build an FTS5 query string from user input, stripping stop words and punctuation
    private func buildFTSQuery(_ input: String, useOrLogic: Bool = false) -> String {
        let terms = input
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !Self.stopWords.contains($0.lowercased()) }

        guard !terms.isEmpty else { return "" }

        let separator = useOrLogic ? " OR " : " "
        return terms.map { "\($0)*" }.joined(separator: separator)
    }

    private init() {}

    /// Search meeting titles using LIKE (no FTS needed).
    /// Strips stop words and searches for each meaningful term independently.
    public func searchTitles(query: String, limit: Int = 20) throws -> [SearchResult] {
        let terms = query
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !Self.stopWords.contains($0.lowercased()) }

        guard !terms.isEmpty else { return [] }

        // Build WHERE clause: title LIKE '%term1%' OR title LIKE '%term2%' ...
        let conditions = terms.map { _ in "title LIKE ?" }.joined(separator: " OR ")
        let arguments: [DatabaseValueConvertible] = terms.map { "%\($0)%" as String } + [limit]

        return try db.reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, title, startTime
                FROM meetings
                WHERE \(conditions)
                ORDER BY startTime DESC
                LIMIT ?
                """, arguments: StatementArguments(arguments)!)

            return rows.map { row in
                SearchResult(
                    id: UUID(uuidString: row["id"]) ?? UUID(),
                    meetingId: UUID(uuidString: row["id"]) ?? UUID(),
                    meetingTitle: row["title"],
                    snippet: row["title"],
                    source: .title,
                    timestamp: row["startTime"]
                )
            }
        }
    }

    /// Search for meetings by participant name (in JSON participants field or speaker profiles)
    public func searchParticipants(query: String, limit: Int = 20) throws -> [SearchResult] {
        let pattern = "%\(query)%"
        return try db.reader.read { db in
            // Search meetings.participants JSON field
            let meetingRows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT m.id, m.title, m.participants, m.startTime
                FROM meetings m
                WHERE m.participants LIKE ?
                ORDER BY m.startTime DESC
                LIMIT ?
                """, arguments: [pattern, limit])

            var results: [SearchResult] = []
            for row in meetingRows {
                let participants: String = row["participants"] ?? ""
                // Extract matching names from JSON array
                var matchedNames: [String] = []
                if let data = participants.data(using: .utf8),
                   let names = try? JSONDecoder().decode([String].self, from: data) {
                    matchedNames = names.filter { $0.localizedCaseInsensitiveContains(query) }
                }
                let snippet = matchedNames.isEmpty
                    ? "Participant match"
                    : "with \(matchedNames.joined(separator: ", "))"

                results.append(SearchResult(
                    id: UUID(uuidString: row["id"]) ?? UUID(),
                    meetingId: UUID(uuidString: row["id"]) ?? UUID(),
                    meetingTitle: row["title"],
                    snippet: snippet,
                    source: .participant,
                    timestamp: row["startTime"]
                ))
            }

            // Also search speaker_profiles.name
            let speakerRows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT m.id, m.title, m.startTime, sp.name
                FROM speaker_profiles sp
                JOIN meetings m ON m.id = sp.meetingId
                WHERE sp.name LIKE ?
                ORDER BY m.startTime DESC
                LIMIT ?
                """, arguments: [pattern, limit])

            let existingIds = Set(results.map(\.meetingId))
            for row in speakerRows {
                let meetingId = UUID(uuidString: row["id"] as String) ?? UUID()
                guard !existingIds.contains(meetingId) else { continue }
                let name: String = row["name"]
                results.append(SearchResult(
                    id: UUID(),
                    meetingId: meetingId,
                    meetingTitle: row["title"],
                    snippet: "with \(name)",
                    source: .participant,
                    timestamp: row["startTime"]
                ))
            }

            return results
        }
    }

    /// Full-text search across transcripts, notes, summaries, and screen contexts.
    /// When `useOrLogic` is true, terms are joined with OR (good for natural language queries).
    public func search(query: String, limit: Int = 50, useOrLogic: Bool = false) throws -> [SearchResult] {
        let ftsQuery = buildFTSQuery(query, useOrLogic: useOrLogic)
        guard !ftsQuery.isEmpty else { return [] }

        return try db.reader.read { db in
            var results: [SearchResult] = []

            // Search transcripts (with speaker attribution)
            let transcriptRows = try Row.fetchAll(db, sql: """
                SELECT ts.id, ts.meetingId, m.title,
                       snippet(transcript_fts, 0, '<b>', '</b>', '...', 32) as snippet,
                       m.startTime, ts.speaker, ts.speakerIndex
                FROM transcript_fts
                JOIN transcript_segments ts ON ts.rowid = transcript_fts.rowid
                JOIN meetings m ON m.id = ts.meetingId
                WHERE transcript_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """, arguments: [ftsQuery, limit])

            for row in transcriptRows {
                let speakerName: String? = row["speaker"] as String?
                results.append(SearchResult(
                    id: UUID(uuidString: row["id"]) ?? UUID(),
                    meetingId: UUID(uuidString: row["meetingId"]) ?? UUID(),
                    meetingTitle: row["title"],
                    snippet: row["snippet"],
                    source: .transcript,
                    timestamp: row["startTime"],
                    speaker: speakerName
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

            // Search screen contexts
            let screenRows = try Row.fetchAll(db, sql: """
                SELECT sc.id, sc.meetingId, m.title,
                       snippet(screen_contexts_fts, 0, '<b>', '</b>', '...', 32) as snippet,
                       m.startTime
                FROM screen_contexts_fts
                JOIN screen_contexts sc ON sc.rowid = screen_contexts_fts.rowid
                JOIN meetings m ON m.id = sc.meetingId
                WHERE screen_contexts_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """, arguments: [ftsQuery, limit / 2])

            for row in screenRows {
                results.append(SearchResult(
                    id: UUID(uuidString: row["id"]) ?? UUID(),
                    meetingId: UUID(uuidString: row["meetingId"]) ?? UUID(),
                    meetingTitle: row["title"],
                    snippet: row["snippet"],
                    source: .screen,
                    timestamp: row["startTime"]
                ))
            }

            return results.sorted { $0.timestamp > $1.timestamp }
        }
    }

    // MARK: - Natural Language Search (LLM-powered query expansion)

    /// Detects whether a query is a natural language question vs. keyword search
    public func isNaturalLanguageQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasSuffix("?") { return true }
        let questionStarters = ["what", "who", "when", "where", "why", "how",
                                "which", "did", "does", "do", "was", "were",
                                "is", "are", "can", "could", "will", "would",
                                "tell me", "show me", "find", "list", "summarize"]
        return questionStarters.contains { trimmed.hasPrefix($0) }
    }

    /// Expand a natural language query into search keywords using the LLM,
    /// then run those keywords through FTS and optionally summarize results.
    public func naturalLanguageSearch(query: String) async throws -> NLSearchResult {
        let provider = await LLMManager.shared.provider

        // Step 1: Extract search keywords from natural language
        let extractionPrompt = """
        Extract search keywords from this question about meeting transcripts/notes. \
        Return ONLY a comma-separated list of 3-8 keywords. No explanation, no quotes, just keywords.

        Also if the question mentions a person's name, include it as a keyword.
        If the question asks about a time period, ignore the time part — just extract topic keywords.

        Question: \(query)
        Keywords:
        """

        let keywords = try await provider.complete(messages: [
            LLMMessage(role: .user, content: extractionPrompt)
        ])

        // Parse keywords
        let extractedTerms = keywords
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && $0.count > 1 }

        // Step 2: Run FTS with extracted keywords
        let ftsQuery = extractedTerms.joined(separator: " ")
        let ftsResults = try search(query: ftsQuery)
        let titleResults = try searchTitles(query: ftsQuery)

        // Also try participant search if any term looks like a name
        var participantResults: [SearchResult] = []
        for term in extractedTerms {
            let first = term.first.map { $0.isUppercase } ?? false
            if first || term.count > 2 {
                let pResults = try searchParticipants(query: term)
                participantResults.append(contentsOf: pResults)
            }
        }

        // Merge and deduplicate
        var seen = Set<UUID>()
        var merged: [SearchResult] = []
        for r in titleResults where seen.insert(r.meetingId).inserted { merged.append(r) }
        for r in participantResults where seen.insert(r.meetingId).inserted { merged.append(r) }
        for r in ftsResults { merged.append(r) }
        let topResults = Array(merged.prefix(12))

        // Step 3: Generate a brief answer from the top results
        var answer: String? = nil
        if !topResults.isEmpty {
            let context = topResults.prefix(6).map { r in
                let src = r.source.rawValue
                let speaker = r.speaker.map { " [\($0)]" } ?? ""
                return "[\(r.meetingTitle) · \(src)\(speaker)] \(cleanSnippet(r.snippet))"
            }.joined(separator: "\n")

            let answerPrompt = """
            Based on these meeting search results, briefly answer the user's question in 2-3 sentences. \
            If the results don't contain enough info to answer, say so honestly.

            Question: \(query)

            Search results:
            \(context)

            Brief answer:
            """

            answer = try? await provider.complete(messages: [
                LLMMessage(role: .user, content: answerPrompt)
            ])
        }

        return NLSearchResult(
            query: query,
            extractedKeywords: extractedTerms,
            results: topResults,
            answer: answer
        )
    }

    private func cleanSnippet(_ html: String) -> String {
        html.replacingOccurrences(of: "<b>", with: "")
            .replacingOccurrences(of: "</b>", with: "")
    }
}

/// Result of a natural language search including LLM-generated answer
public struct NLSearchResult: Sendable {
    public let query: String
    public let extractedKeywords: [String]
    public let results: [SearchResult]
    public let answer: String?
}
