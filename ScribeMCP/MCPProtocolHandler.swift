import Foundation

/// Result of handling an MCP request
enum MCPResult {
    case success([String: Any])
    case error(Int, String)
}

/// Routes JSON-RPC methods to the appropriate MCP handler
final class MCPProtocolHandler: Sendable {
    let toolHandler: MCPToolHandler
    let resourceHandler: MCPResourceHandler

    init(toolHandler: MCPToolHandler, resourceHandler: MCPResourceHandler) {
        self.toolHandler = toolHandler
        self.resourceHandler = resourceHandler
    }

    func handle(method: String, params: [String: Any]) async -> MCPResult {
        switch method {
        case "initialize":
            return .success([
                "protocolVersion": "2025-11-25",
                "capabilities": [
                    "tools": [:] as [String: Any],
                    "resources": [:] as [String: Any],
                ] as [String: Any],
                "serverInfo": [
                    "name": "scribe",
                    "version": "0.3.0",
                ] as [String: Any],
            ])

        case "tools/list":
            return .success(["tools": toolHandler.toolDefinitions()])

        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            return await toolHandler.callTool(name: name, arguments: arguments)

        case "resources/list":
            return .success(["resources": resourceHandler.resourceDefinitions()])

        case "resources/read":
            let uri = params["uri"] as? String ?? ""
            return await resourceHandler.readResource(uri: uri)

        default:
            return .error(-32601, "Method not found: \(method)")
        }
    }
}
