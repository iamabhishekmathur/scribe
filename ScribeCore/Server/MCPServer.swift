import Foundation

/// MCP (Model Context Protocol) server for AI client integration.
/// Exposes meeting data as MCP tools and resources.
/// Uses stdin/stdout JSON-RPC transport.
public actor MCPServer {
    public static let shared = MCPServer()
    private var isRunning = false

    private init() {}

    /// Available MCP tools
    public enum Tool: String, CaseIterable {
        case listMeetings = "scribe_list_meetings"
        case getMeeting = "scribe_get_meeting"
        case search = "scribe_search"
        case currentStatus = "scribe_current_status"

        var description: String {
            switch self {
            case .listMeetings: return "List recent meetings with titles, dates, and durations"
            case .getMeeting: return "Get full meeting details including transcript, notes, and summary"
            case .search: return "Search across all meeting transcripts, notes, and summaries"
            case .currentStatus: return "Get current Scribe status (recording, idle, etc.)"
            }
        }

        var inputSchema: [String: Any] {
            switch self {
            case .listMeetings:
                return ["type": "object", "properties": [
                    "limit": ["type": "integer", "description": "Max meetings to return", "default": 20]
                ]]
            case .getMeeting:
                return ["type": "object", "properties": [
                    "meetingId": ["type": "string", "description": "Meeting UUID"]
                ], "required": ["meetingId"]]
            case .search:
                return ["type": "object", "properties": [
                    "query": ["type": "string", "description": "Search query"]
                ], "required": ["query"]]
            case .currentStatus:
                return ["type": "object", "properties": [:] as [String: Any]]
            }
        }
    }

    /// Handle a tool call from an MCP client
    public func handleToolCall(name: String, arguments: [String: Any]) async -> [String: Any] {
        guard let tool = Tool(rawValue: name) else {
            return ["error": "Unknown tool: \(name)"]
        }

        switch tool {
        case .listMeetings:
            let limit = arguments["limit"] as? Int ?? 20
            guard let meetings = try? await MeetingStore.shared.getAllMeetings(limit: limit) else {
                return ["error": "Failed to fetch meetings"]
            }
            return ["meetings": meetings.map { m -> [String: Any] in
                var d: [String: Any] = ["id": m.id.uuidString, "title": m.title, "state": m.state]
                d["startTime"] = ISO8601DateFormatter().string(from: m.startTime)
                if let dur = m.duration { d["duration"] = dur }
                return d
            }]

        case .getMeeting:
            guard let idStr = arguments["meetingId"] as? String,
                  let uuid = UUID(uuidString: idStr) else {
                return ["error": "Invalid meetingId"]
            }
            guard let meeting = try? await MeetingStore.shared.getMeeting(id: uuid) else {
                return ["error": "Meeting not found"]
            }
            let transcript = (try? await MeetingStore.shared.getTranscript(meetingId: uuid)) ?? []
            let notes = (try? await MeetingStore.shared.getNotes(meetingId: uuid)) ?? []
            let summaries = (try? await MeetingStore.shared.getSummaries(meetingId: uuid)) ?? []

            return [
                "meeting": ["id": meeting.id.uuidString, "title": meeting.title, "state": meeting.state],
                "transcript": transcript.map { ["speaker": $0.speaker ?? "Unknown", "text": $0.text] },
                "notes": notes.map { ["text": $0.text, "enrichedText": $0.enrichedText ?? ""] },
                "summaries": summaries.map { ["type": $0.summaryType, "content": $0.content] },
            ]

        case .search:
            guard let query = arguments["query"] as? String, !query.isEmpty else {
                return ["error": "Query required"]
            }
            let results = (try? await SearchIndex.shared.search(query: query)) ?? []
            return ["results": results.map { r -> [String: Any] in
                ["meetingId": r.meetingId.uuidString, "meetingTitle": r.meetingTitle, "snippet": r.snippet, "source": r.source.rawValue]
            }]

        case .currentStatus:
            return ["status": "idle", "version": "0.3.0"]
        }
    }

    /// Generate MCP tool definitions for registration
    public func toolDefinitions() -> [[String: Any]] {
        Tool.allCases.map { tool in
            [
                "name": tool.rawValue,
                "description": tool.description,
                "inputSchema": tool.inputSchema,
            ]
        }
    }
}
