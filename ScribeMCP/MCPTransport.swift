import Foundation

/// JSON-RPC 2.0 stdin/stdout transport for MCP protocol.
/// Reads one JSON object per line from stdin, writes responses to stdout.
/// All logging goes to stderr per MCP spec.
final class StdioTransport: Sendable {
    let handler: MCPProtocolHandler

    init(handler: MCPProtocolHandler) {
        self.handler = handler
    }

    func run() async {
        log("scribe-mcp: server started, reading from stdin")

        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }

            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log("scribe-mcp: invalid JSON input")
                continue
            }

            let method = json["method"] as? String
            let id = json["id"]  // Can be Int, String, or nil (notification)

            // Notifications have no id — don't send a response
            guard let requestId = id else {
                if let m = method {
                    log("scribe-mcp: notification '\(m)' (ignored)")
                }
                continue
            }

            let params = json["params"] as? [String: Any] ?? [:]
            let methodName = method ?? ""

            let result = await handler.handle(method: methodName, params: params)

            var response: [String: Any] = ["jsonrpc": "2.0"]

            // Preserve id type (Int or String)
            if let intId = requestId as? Int {
                response["id"] = intId
            } else if let strId = requestId as? String {
                response["id"] = strId
            } else {
                response["id"] = requestId
            }

            switch result {
            case .success(let value):
                response["result"] = value
            case .error(let code, let message):
                response["error"] = ["code": code, "message": message]
            }

            guard let responseData = try? JSONSerialization.data(withJSONObject: response),
                  let responseStr = String(data: responseData, encoding: .utf8) else {
                log("scribe-mcp: failed to serialize response")
                continue
            }

            print(responseStr)
            fflush(stdout)
        }

        log("scribe-mcp: stdin closed, shutting down")
    }
}

/// Log to stderr (MCP requires stdout is reserved for protocol messages)
func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
