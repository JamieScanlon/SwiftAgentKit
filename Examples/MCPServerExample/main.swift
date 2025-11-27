import Foundation
import Logging
import SwiftAgentKitMCP
import EasyJSON
import SwiftAgentKit

private func configureServerLogging() {
    SwiftAgentKitLogging.bootstrap(
        logger: Logger(label: "com.example.swiftagentkit.mcp.server"),
        level: .info,
        metadata: SwiftAgentKitLogging.metadata(("example", .string("MCPServer")))
    )
}

struct MCPServerExample {
    static func main() async throws {
        configureServerLogging()
        let logger = SwiftAgentKitLogging.logger(for: .examples("MCPServerExample"))
        logger.info("Starting MCP Server Example")
        
        print("=== SwiftAgentKit MCP Server Example ===")
        
        // Example 1: Default stdio transport (most common for MCP servers)
        let stdioServer = MCPServer(name: "example-tool-server", version: "1.0.0")
        
        // Example 2: HTTP client transport (for connecting to remote MCP servers)
        _ = MCPServer(
            name: "http-example-server", 
            version: "1.0.0",
            transportType: .httpClient(
                endpoint: URL(string: "http://localhost:8080")!,
                streaming: true,
                sseInitializationTimeout: 10
            )
        )
        
        // Example 3: Network transport (for TCP/UDP connections)
        // Note: This requires creating an NWConnection first
        // let connection = NWConnection(host: "localhost", port: 8080, using: .tcp)
        // let networkServer = MCPServer(
        //     name: "network-example-server",
        //     version: "1.0.0", 
        //     transportType: .network(connection: connection)
        // )
        
        // Use the stdio server for this example
        let server = stdioServer
        
        // Register some example tools
        await server.registerTool(
            toolDefinition: ToolDefinition(
                name: "hello_world",
                description: "A simple greeting tool",
                parameters: [
                    ToolDefinition.Parameter(
                        name: "name",
                        description: "Name to greet",
                        type: "string",
                        required: true
                    )
                ],
                type: .mcpTool
            )
        ) { args in
            let name: String
            if case .string(let value) = args["name"] {
                name = value
            } else {
                name = "World"
            }
            return .success("Hello, \(name)!")
        }
        
        await server.registerTool(
            toolDefinition: ToolDefinition(
                name: "add_numbers",
                description: "Add two numbers together",
                parameters: [
                    ToolDefinition.Parameter(
                        name: "a",
                        description: "First number",
                        type: "number",
                        required: true
                    ),
                    ToolDefinition.Parameter(
                        name: "b",
                        description: "Second number",
                        type: "number",
                        required: true
                    )
                ],
                type: .mcpTool
            )
        ) { args in
            let a: Double
            let b: Double
            
            if case .double(let value) = args["a"] {
                a = value
            } else if case .integer(let value) = args["a"] {
                a = Double(value)
            } else {
                return .error("INVALID_PARAMETER", "Parameter 'a' must be a number")
            }
            
            if case .double(let value) = args["b"] {
                b = value
            } else if case .integer(let value) = args["b"] {
                b = Double(value)
            } else {
                return .error("INVALID_PARAMETER", "Parameter 'b' must be a number")
            }
            
            let result = a + b
            return .success("\(a) + \(b) = \(result)")
        }
        
        await server.registerTool(
            toolDefinition: ToolDefinition(
                name: "get_environment",
                description: "Get environment variable value",
                parameters: [
                    ToolDefinition.Parameter(
                        name: "variable",
                        description: "Environment variable name",
                        type: "string",
                        required: true
                    )
                ],
                type: .mcpTool
            )
        ) { args in
            let variable: String
            if case .string(let value) = args["variable"] {
                variable = value
            } else {
                return .error("INVALID_PARAMETER", "Parameter 'variable' must be a string")
            }
            
            let value = ProcessInfo.processInfo.environment[variable] ?? "Not found"
            return .success("\(variable) = \(value)")
        }
        
        // Print registered tools
        let toolNames = ["hello_world", "add_numbers", "get_environment"]
        print("Registered \(toolNames.count) tools: \(toolNames.joined(separator: ", "))")
        
        // Print diagnostic info
        let info = await server.diagnosticInfo()
        print("Server diagnostic info: \(info)")
        
        print("Starting MCP server...")
        
        // Start the server
        try await server.start()
    }
}

