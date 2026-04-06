import Foundation
import ScribeCore

/// Handles MCP resource list and read requests
final class MCPResourceHandler: Sendable {
    private nonisolated(unsafe) static let isoFormatter = ISO8601DateFormatter()

    func resourceDefinitions() -> [[String: Any]] {
        [
            [
                "uri": "scribe:///meetings/recent",
                "name": "Recent Meetings",
                "description": "10 most recent meetings (metadata only)",
                "mimeType": "application/json",
            ],
        ]
    }

    func readResource(uri: String) async -> MCPResult {
        // Match scribe:///meetings/recent
        if uri == "scribe:///meetings/recent" {
            return await readRecentMeetings(uri: uri)
        }

        // Match scribe:///meetings/{id}
        let meetingPrefix = "scribe:///meetings/"
        if uri.hasPrefix(meetingPrefix) {
            let idStr = String(uri.dropFirst(meetingPrefix.count))
            if let uuid = UUID(uuidString: idStr) {
                return await readMeetingExport(uri: uri, id: uuid)
            }
        }

        return .error(-32602, "Unknown resource URI: \(uri)")
    }

    private func readRecentMeetings(uri: String) async -> MCPResult {
        do {
            let meetings = try await MeetingStore.shared.getAllMeetings(limit: 10)
            let list = meetings.map { m -> [String: Any] in
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
            let jsonData = try JSONSerialization.data(withJSONObject: list)
            let text = String(data: jsonData, encoding: .utf8) ?? "[]"
            return .success([
                "contents": [
                    ["uri": uri, "mimeType": "application/json", "text": text]
                ]
            ])
        } catch {
            return .error(-32603, "Failed to read recent meetings: \(error.localizedDescription)")
        }
    }

    private func readMeetingExport(uri: String, id: UUID) async -> MCPResult {
        do {
            let store = MeetingStore.shared
            guard let meeting = try await store.getMeeting(id: id) else {
                return .error(-32602, "Meeting not found: \(id)")
            }
            let transcript = try await store.getTranscript(meetingId: id)
            let notes = try await store.getNotes(meetingId: id)
            let summaries = try await store.getSummaries(meetingId: id)
            let screenContexts = try await store.getScreenContexts(meetingId: id)

            let iso = Self.isoFormatter
            let export: [String: Any] = [
                "meeting": [
                    "id": meeting.id.uuidString,
                    "title": meeting.title,
                    "startTime": iso.string(from: meeting.startTime),
                    "endTime": meeting.endTime.map { iso.string(from: $0) } as Any,
                    "duration": meeting.duration as Any,
                    "state": meeting.state,
                    "meetingURL": meeting.meetingURL as Any,
                    "participants": meeting.participants as Any,
                ] as [String: Any],
                "transcript": transcript.map { s in
                    ["speaker": s.speaker ?? "Unknown", "text": s.text,
                     "startTime": s.startTime, "endTime": s.endTime] as [String: Any]
                },
                "notes": notes.map { n in
                    ["text": n.text, "enrichedText": n.enrichedText as Any,
                     "timestamp": n.timestamp] as [String: Any]
                },
                "summaries": summaries.map { s in
                    ["type": s.summaryType, "content": s.content] as [String: Any]
                },
                "screenContexts": screenContexts.map { c in
                    ["extractedText": c.extractedText, "timestamp": c.timestamp,
                     "sourceDescription": c.sourceDescription as Any] as [String: Any]
                },
                "exportedAt": iso.string(from: Date()),
            ]

            let data = try JSONSerialization.data(withJSONObject: export)
            let text = String(data: data, encoding: .utf8) ?? "{}"

            return .success([
                "contents": [
                    ["uri": uri, "mimeType": "application/json", "text": text]
                ]
            ])
        } catch {
            return .error(-32603, "Failed to read meeting: \(error.localizedDescription)")
        }
    }
}
