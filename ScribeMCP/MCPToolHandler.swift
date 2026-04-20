import Foundation
import ScribeCore

/// Implements the 6 MCP tools for Scribe meeting data
final class MCPToolHandler: Sendable {
    private nonisolated(unsafe) static let isoFormatter = ISO8601DateFormatter()

    func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "scribe_list_meetings",
                "description": "List recent meetings with titles, dates, durations, and state",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "limit": ["type": "integer", "description": "Max meetings to return (default 20)"]
                    ] as [String: Any],
                ] as [String: Any],
            ],
            [
                "name": "scribe_get_meeting",
                "description": "Get full meeting details including transcript, notes, and summaries",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "meetingId": ["type": "string", "description": "Meeting UUID"]
                    ] as [String: Any],
                    "required": ["meetingId"],
                ] as [String: Any],
            ],
            [
                "name": "scribe_get_transcript",
                "description": "Get the transcript for a meeting with speakers and timestamps",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "meetingId": ["type": "string", "description": "Meeting UUID"]
                    ] as [String: Any],
                    "required": ["meetingId"],
                ] as [String: Any],
            ],
            [
                "name": "scribe_get_action_items",
                "description": "Get action items and decisions from a meeting",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "meetingId": ["type": "string", "description": "Meeting UUID"]
                    ] as [String: Any],
                    "required": ["meetingId"],
                ] as [String: Any],
            ],
            [
                "name": "scribe_search",
                "description": "Search across all meeting transcripts, notes, and summaries",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search query"],
                        "limit": ["type": "integer", "description": "Max results (default 20)"],
                    ] as [String: Any],
                    "required": ["query"],
                ] as [String: Any],
            ],
            [
                "name": "scribe_current_status",
                "description": "Get Scribe status: version, database path, meeting count",
                "inputSchema": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                ] as [String: Any],
            ],
        ]
    }

    func callTool(name: String, arguments: [String: Any]) async -> MCPResult {
        do {
            let result: Any
            switch name {
            case "scribe_list_meetings":
                result = try await listMeetings(arguments: arguments)
            case "scribe_get_meeting":
                result = try await getMeeting(arguments: arguments)
            case "scribe_get_transcript":
                result = try await getTranscript(arguments: arguments)
            case "scribe_get_action_items":
                result = try await getActionItems(arguments: arguments)
            case "scribe_search":
                result = try await search(arguments: arguments)
            case "scribe_current_status":
                result = try await currentStatus()
            default:
                return toolError("Unknown tool: \(name)")
            }
            return toolSuccess(result)
        } catch {
            return toolError(error.localizedDescription)
        }
    }

    // MARK: - Tool Implementations

    private func listMeetings(arguments: [String: Any]) async throws -> Any {
        let limit = arguments["limit"] as? Int ?? 20
        let meetings = try await MeetingStore.shared.getAllMeetings(limit: limit)
        return ["meetings": meetings.map { meetingBrief($0) }]
    }

    private func getMeeting(arguments: [String: Any]) async throws -> Any {
        let uuid = try requireMeetingId(arguments)
        guard let meeting = try await MeetingStore.shared.getMeeting(id: uuid) else {
            throw ToolError.meetingNotFound(uuid)
        }
        let transcript = try await MeetingStore.shared.getTranscript(meetingId: uuid)
        let notes = try await MeetingStore.shared.getNotes(meetingId: uuid)
        let summaries = try await MeetingStore.shared.getSummaries(meetingId: uuid)

        return [
            "meeting": meetingDetail(meeting),
            "transcript": transcript.map { segmentDict($0) },
            "notes": notes.map { noteDict($0) },
            "summaries": summaries.map { summaryDict($0) },
        ] as [String: Any]
    }

    private func getTranscript(arguments: [String: Any]) async throws -> Any {
        let uuid = try requireMeetingId(arguments)
        let segments = try await MeetingStore.shared.getTranscript(meetingId: uuid)
        return ["segments": segments.map { segmentDict($0) }]
    }

    private func getActionItems(arguments: [String: Any]) async throws -> Any {
        let uuid = try requireMeetingId(arguments)
        let summaries = try await MeetingStore.shared.getSummaries(meetingId: uuid)
        let filtered = summaries.filter { $0.summaryType == "action_items" || $0.summaryType == "decisions" }
        return ["items": filtered.map { summaryDict($0) }]
    }

    private func search(arguments: [String: Any]) async throws -> Any {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            throw ToolError.missingParam("query")
        }
        let limit = arguments["limit"] as? Int ?? 20
        let results = try await SearchIndex.shared.search(query: query, limit: limit)
        return ["results": results.map { r in
            [
                "meetingId": r.meetingId.uuidString,
                "meetingTitle": r.meetingTitle,
                "snippet": r.snippet,
                "source": r.source.rawValue,
            ] as [String: Any]
        }]
    }

    private func currentStatus() async throws -> Any {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbPath = appSupport.appendingPathComponent("Scribe/scribe.sqlite").path
        let meetings = try await MeetingStore.shared.getAllMeetings(limit: 1)
        let count = meetings.isEmpty ? 0 : try await MeetingStore.shared.getAllMeetings(limit: 10000).count
        return [
            "version": "0.2.0",
            "databasePath": dbPath,
            "meetingCount": count,
            "status": "running",
        ] as [String: Any]
    }

    // MARK: - Helpers

    private func requireMeetingId(_ arguments: [String: Any]) throws -> UUID {
        guard let idStr = arguments["meetingId"] as? String else {
            throw ToolError.missingParam("meetingId")
        }
        guard let uuid = UUID(uuidString: idStr) else {
            throw ToolError.invalidUUID(idStr)
        }
        return uuid
    }

    private func meetingBrief(_ m: MeetingRecord) -> [String: Any] {
        var d: [String: Any] = [
            "id": m.id.uuidString,
            "title": m.title,
            "startTime": Self.isoFormatter.string(from: m.startTime),
            "state": m.state,
        ]
        if let end = m.endTime { d["endTime"] = Self.isoFormatter.string(from: end) }
        if let dur = m.duration { d["duration"] = dur }
        return d
    }

    private func meetingDetail(_ m: MeetingRecord) -> [String: Any] {
        var d = meetingBrief(m)
        if let url = m.meetingURL { d["meetingURL"] = url }
        if let participants = m.participants { d["participants"] = participants }
        if let folderId = m.folderId { d["folderId"] = folderId.uuidString }
        return d
    }

    private func segmentDict(_ s: TranscriptSegment) -> [String: Any] {
        [
            "speaker": s.speaker ?? "Unknown",
            "text": s.text,
            "startTime": s.startTime,
            "endTime": s.endTime,
        ]
    }

    private func noteDict(_ n: UserNote) -> [String: Any] {
        var d: [String: Any] = ["text": n.text, "timestamp": n.timestamp]
        if let enriched = n.enrichedText { d["enrichedText"] = enriched }
        return d
    }

    private func summaryDict(_ s: AISummary) -> [String: Any] {
        ["type": s.summaryType, "content": s.content]
    }

    private func toolSuccess(_ value: Any) -> MCPResult {
        let jsonData = try? JSONSerialization.data(withJSONObject: value)
        let text = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return .success([
            "content": [["type": "text", "text": text]],
            "isError": false,
        ])
    }

    private func toolError(_ message: String) -> MCPResult {
        .success([
            "content": [["type": "text", "text": message]],
            "isError": true,
        ])
    }
}

enum ToolError: LocalizedError {
    case missingParam(String)
    case invalidUUID(String)
    case meetingNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .missingParam(let name): return "Missing required parameter: \(name)"
        case .invalidUUID(let s): return "Invalid UUID: \(s)"
        case .meetingNotFound(let id): return "Meeting not found: \(id)"
        }
    }
}
