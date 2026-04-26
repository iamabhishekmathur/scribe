import Foundation
import Network

/// Lightweight embedded HTTP server on localhost:7777
/// Provides REST API for meeting data access
public actor LocalAPIServer {
    public static let shared = LocalAPIServer()

    private var listener: NWListener?
    private var _isRunning = false
    public var isRunning: Bool { _isRunning }

    private let port: UInt16 = 7777

    private init() {}

    public func start() throws {
        guard !_isRunning else { return }

        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleConnection(connection) }
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Scribe API server listening on http://localhost:\(self.port)")
            case .failed(let error):
                print("Scribe API server failed: \(error)")
            default:
                break
            }
        }

        listener.start(queue: .global(qos: .utility))
        _isRunning = true
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        _isRunning = false
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
            Task {
                guard let data, let requestString = String(data: data, encoding: .utf8) else {
                    connection.cancel()
                    return
                }

                let response = await self.routeRequest(requestString)
                let httpResponse = "HTTP/1.1 \(response.status)\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(response.body.count)\r\n\r\n\(response.body)"

                connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    // MARK: - Routing

    private struct HTTPResponse {
        let status: String
        let body: String
    }

    private func routeRequest(_ raw: String) async -> HTTPResponse {
        let lines = raw.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            return HTTPResponse(status: "400 Bad Request", body: "{\"error\":\"Bad request\"}")
        }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            return HTTPResponse(status: "400 Bad Request", body: "{\"error\":\"Bad request\"}")
        }

        let method = parts[0]
        let fullPath = parts[1]
        let pathAndQuery = fullPath.components(separatedBy: "?")
        let path = pathAndQuery[0]
        let query = pathAndQuery.count > 1 ? pathAndQuery[1] : nil

        switch (method, path) {
        case ("GET", "/api/meetings"):
            return await handleGetMeetings()
        case ("GET", let p) where p.hasPrefix("/api/meetings/") && p.hasSuffix("/transcript"):
            let id = extractId(from: p, removing: "/api/meetings/", and: "/transcript")
            return await handleGetTranscript(id: id)
        case ("GET", let p) where p.hasPrefix("/api/meetings/") && p.hasSuffix("/summary"):
            let id = extractId(from: p, removing: "/api/meetings/", and: "/summary")
            return await handleGetSummary(id: id)
        case ("GET", let p) where p.hasPrefix("/api/meetings/") && p.hasSuffix("/notes"):
            let id = extractId(from: p, removing: "/api/meetings/", and: "/notes")
            return await handleGetNotes(id: id)
        case ("GET", let p) where p.hasPrefix("/api/meetings/"):
            let id = extractId(from: p, removing: "/api/meetings/", and: "")
            return await handleGetMeeting(id: id)
        case ("DELETE", let p) where p.hasPrefix("/api/meetings/"):
            let id = extractId(from: p, removing: "/api/meetings/", and: "")
            return await handleDeleteMeeting(id: id)
        case ("GET", "/api/search"):
            let q = parseQueryParam(query, key: "q") ?? ""
            return await handleSearch(query: q)
        case ("GET", "/api/status"):
            return await handleStatus()
        default:
            return HTTPResponse(status: "404 Not Found", body: "{\"error\":\"Not found\"}")
        }
    }

    // MARK: - Handlers

    private func handleGetMeetings() async -> HTTPResponse {
        guard let meetings = try? await MeetingStore.shared.getAllMeetings() else {
            return HTTPResponse(status: "500 Internal Server Error", body: "{\"error\":\"Failed to fetch meetings\"}")
        }
        let data = meetings.map { meetingToDict($0) }
        return jsonResponse(data)
    }

    private func handleGetMeeting(id: String) async -> HTTPResponse {
        guard let uuid = UUID(uuidString: id),
              let meeting = try? await MeetingStore.shared.getMeeting(id: uuid) else {
            return HTTPResponse(status: "404 Not Found", body: "{\"error\":\"Meeting not found\"}")
        }
        return jsonResponse(meetingToDict(meeting))
    }

    private func handleGetTranscript(id: String) async -> HTTPResponse {
        guard let uuid = UUID(uuidString: id),
              let segments = try? await MeetingStore.shared.getTranscript(meetingId: uuid) else {
            return HTTPResponse(status: "404 Not Found", body: "{\"error\":\"Not found\"}")
        }
        let data = segments.map { seg -> [String: Any] in
            var d: [String: Any] = ["text": seg.text, "startTime": seg.startTime, "endTime": seg.endTime, "isFinal": seg.isFinal]
            if let s = seg.speaker { d["speaker"] = s }
            if let c = seg.confidence { d["confidence"] = c }
            return d
        }
        return jsonResponse(data)
    }

    private func handleGetSummary(id: String) async -> HTTPResponse {
        guard let uuid = UUID(uuidString: id),
              let summaries = try? await MeetingStore.shared.getSummaries(meetingId: uuid) else {
            return HTTPResponse(status: "404 Not Found", body: "{\"error\":\"Not found\"}")
        }
        let data = summaries.map { s -> [String: Any] in
            ["type": s.summaryType, "content": s.content, "model": s.modelUsed]
        }
        return jsonResponse(data)
    }

    private func handleGetNotes(id: String) async -> HTTPResponse {
        guard let uuid = UUID(uuidString: id),
              let notes = try? await MeetingStore.shared.getNotes(meetingId: uuid) else {
            return HTTPResponse(status: "404 Not Found", body: "{\"error\":\"Not found\"}")
        }
        let data = notes.map { n -> [String: Any] in
            var d: [String: Any] = ["text": n.text, "timestamp": n.timestamp]
            if let e = n.enrichedText { d["enrichedText"] = e }
            return d
        }
        return jsonResponse(data)
    }

    private func handleDeleteMeeting(id: String) async -> HTTPResponse {
        guard let uuid = UUID(uuidString: id) else {
            return HTTPResponse(status: "400 Bad Request", body: "{\"error\":\"Invalid ID\"}")
        }
        do {
            try await MeetingStore.shared.deleteMeeting(id: uuid)
            return HTTPResponse(status: "200 OK", body: "{\"deleted\":true}")
        } catch {
            return HTTPResponse(status: "500 Internal Server Error", body: "{\"error\":\"\(error.localizedDescription)\"}")
        }
    }

    private func handleSearch(query: String) async -> HTTPResponse {
        guard !query.isEmpty else {
            return HTTPResponse(status: "400 Bad Request", body: "{\"error\":\"Query parameter 'q' required\"}")
        }
        let results = (try? await SearchIndex.shared.search(query: query)) ?? []
        let data = results.map { r -> [String: Any] in
            ["meetingId": r.meetingId.uuidString, "meetingTitle": r.meetingTitle, "snippet": r.snippet, "source": r.source.rawValue]
        }
        return jsonResponse(data)
    }

    private func handleStatus() async -> HTTPResponse {
        let data: [String: Any] = [
            "status": "running",
            "version": "0.3.0",
        ]
        return jsonResponse(data)
    }

    // MARK: - Helpers

    private func meetingToDict(_ m: MeetingRecord) -> [String: Any] {
        var d: [String: Any] = [
            "id": m.id.uuidString,
            "title": m.title,
            "startTime": ISO8601DateFormatter().string(from: m.startTime),
            "state": m.state,
        ]
        if let end = m.endTime { d["endTime"] = ISO8601DateFormatter().string(from: end) }
        if let dur = m.duration { d["duration"] = dur }
        if let url = m.meetingURL { d["meetingURL"] = url }
        return d
    }

    private func jsonResponse(_ obj: Any) -> HTTPResponse {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8) else {
            return HTTPResponse(status: "500 Internal Server Error", body: "{\"error\":\"Serialization failed\"}")
        }
        return HTTPResponse(status: "200 OK", body: str)
    }

    private func extractId(from path: String, removing prefix: String, and suffix: String) -> String {
        var id = path
        if !prefix.isEmpty { id = String(id.dropFirst(prefix.count)) }
        if !suffix.isEmpty, id.hasSuffix(suffix) { id = String(id.dropLast(suffix.count)) }
        return id
    }

    private func parseQueryParam(_ query: String?, key: String) -> String? {
        guard let query else { return nil }
        for param in query.components(separatedBy: "&") {
            let kv = param.components(separatedBy: "=")
            if kv.count == 2, kv[0] == key {
                return kv[1].removingPercentEncoding
            }
        }
        return nil
    }
}
