import Foundation
import ScribeCore

log("scribe-mcp: initializing database...")
try await Database.shared.initialize()
log("scribe-mcp: database ready")

let toolHandler = MCPToolHandler()
let resourceHandler = MCPResourceHandler()
let protocolHandler = MCPProtocolHandler(toolHandler: toolHandler, resourceHandler: resourceHandler)
let transport = StdioTransport(handler: protocolHandler)
await transport.run()
