import Foundation
import Logging
import SwiftAgentKitMCP

// Example: Creating an MCP Server with tools
@main
struct MCPServerExample {
    static func main() async {
        // Set up logging to stderr to avoid interfering with MCP protocol on stdout
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = .debug  // Set to debug level for more detailed logging
            return handler
        }
        
        let logger = Logger(label: "MCPServerExample")
        logger.info("=== SwiftAgentKit MCP Server Example ===")
        
        // Create an MCP server
        let server = MCPServer(name: "example-tool-server", version: "1.0.0")
        
        // Register some example tools
        await server.registerTool(
            name: "hello_world",
            description: "A simple greeting tool",
            inputSchema: [
                "type": "object",
                "properties": "{\"name\": {\"type\": \"string\", \"description\": \"Name to greet\"}}",
                "required": "[\"name\"]"
            ]
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
            name: "add_numbers",
            description: "Add two numbers together",
            inputSchema: [
                "type": "object",
                "properties": "{\"a\": {\"type\": \"number\", \"description\": \"First number\"}, \"b\": {\"type\": \"number\", \"description\": \"Second number\"}}",
                "required": "[\"a\", \"b\"]"
            ]
        ) { args in
            let a: Double
            let b: Double
            
            if case .double(let value) = args["a"] {
                a = value
            } else if case .integer(let value) = args["a"] {
                a = Double(value)
            } else {
                a = 0
            }
            
            if case .double(let value) = args["b"] {
                b = value
            } else if case .integer(let value) = args["b"] {
                b = Double(value)
            } else {
                b = 0
            }
            
            let result = a + b
            return .success("\(a) + \(b) = \(result)")
        }
        
        await server.registerTool(
            name: "get_environment",
            description: "Get environment variable value",
            inputSchema: [
                "type": "object",
                "properties": "{\"variable\": {\"type\": \"string\", \"description\": \"Environment variable name\"}}",
                "required": "[\"variable\"]"
            ]
        ) { args in
            let variableName: String
            if case .string(let value) = args["variable"] {
                variableName = value
            } else {
                variableName = ""
            }
            let value = ProcessInfo.processInfo.environment[variableName] ?? "Not found"
            return .success("\(variableName) = \(value)")
        }
        
        logger.info("Registered 3 tools: hello_world, add_numbers, get_environment")
        
        // Print diagnostic information
        let diagnosticInfo = await server.diagnosticInfo()
        logger.info("Server diagnostic info: \(diagnosticInfo)")
        
        logger.info("Starting MCP server...")
        
        do {
            // Start the server
            try await server.start()
            
            logger.info("✓ MCP server started successfully")
            logger.info("Server is now listening on stdio")
            logger.info("You can connect to this server using an MCP client")
            logger.info("Press Ctrl+C to stop the server")
            
            // Keep the server running
            try await Task.sleep(nanoseconds: UInt64.max)
            
        } catch {
            logger.error("Failed to start MCP server: \(error)")
            exit(1)
        }
    }
}

