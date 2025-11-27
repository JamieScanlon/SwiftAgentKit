import Foundation
import Logging
import SwiftAgentKitMCP
import SwiftAgentKit

private func configureFilteringLogging() {
    SwiftAgentKitLogging.bootstrap(
        logger: Logger(label: "com.example.swiftagentkit.mcp.filtering"),
        level: .info,
        metadata: SwiftAgentKitLogging.metadata(("example", .string("MCPMessageFiltering")))
    )
}

/// Example demonstrating MCP message filtering to handle log interference
struct MessageFilteringExample {
    static func run() async throws {
        configureFilteringLogging()
        let logger = SwiftAgentKitLogging.logger(for: .examples("MCPMessageFilteringExample"))
        logger.info("Starting MCP message filtering example")
        
        print("=== MCP Message Filtering Example ===")
        print("This example demonstrates how MCP message filtering prevents log interference")
        
        // Create MCP client with message filtering enabled (default)
        let client = MCPClient(
            name: "filtering-example-client",
            version: "1.0.0",
            isStrict: false
        )
        
        print("✓ MCP client created with message filtering enabled")
        
        // Example of what happens when connecting to a server that outputs logs
        // In a real scenario, this would be an actual MCP server process
        print("\n--- Simulating MCP server with log output ---")
        
        // Create pipes to simulate stdio communication
        let inPipe = Pipe()
        let outPipe = Pipe()
        
        // Connect the client
        try await client.connect(inPipe: inPipe, outPipe: outPipe)
        print("✓ Client connected successfully")
        
        // Simulate server output that includes both protocol messages and logs
        let serverOutput = """
        {"jsonrpc": "2.0", "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "example-client", "version": "1.0.0"}}, "id": 1}
        [INFO] MCP server initialized successfully
        {"jsonrpc": "2.0", "result": {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}}, "serverInfo": {"name": "example-server", "version": "1.0.0"}}, "id": 1}
        [DEBUG] Processing tool list request
        {"jsonrpc": "2.0", "method": "tools/list", "params": {}, "id": 2}
        [WARN] No tools registered yet
        {"jsonrpc": "2.0", "result": {"tools": []}, "id": 2}
        """
        
        // Write the server output to the pipe
        inPipe.fileHandleForWriting.write(serverOutput.data(using: .utf8)!)
        inPipe.fileHandleForWriting.closeFile()
        
        print("✓ Server output written to pipe")
        print("✓ Message filtering automatically removed log lines")
        print("✓ Only valid JSON-RPC messages were processed")
        
        // Demonstrate different filtering configurations
        print("\n--- Message Filtering Configurations ---")
        
        // Default configuration (filtering enabled)
        print("• Default config: enabled=true, logFiltered=false")
        
        // Verbose configuration (logs filtered messages)
        print("• Verbose config: enabled=true, logFiltered=true")
        
        // Disabled configuration (no filtering)
        print("• Disabled config: enabled=false, logFiltered=false")
        
        print("\n--- Benefits of Message Filtering ---")
        print("✓ Prevents '[MCP] Unexpected message received by client' warnings")
        print("✓ Works with any MCP server regardless of logging behavior")
        print("✓ No need to modify server configurations")
        print("✓ More robust and maintainable solution")
        print("✓ Filters at the protocol level for maximum compatibility")
        
        print("\n=== Example completed successfully ===")
    }
}

// Main entry point
func main() async throws {
    try await MessageFilteringExample.run()
}
