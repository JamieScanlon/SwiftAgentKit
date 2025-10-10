//
//  chunked_stdio_example.swift
//  SwiftAgentKit
//
//  Example demonstrating the use of chunked stdio transport to handle large messages
//  that exceed the 64KB pipe limit on macOS
//

import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitMCP
import EasyJSON

/// Example demonstrating chunked stdio transport for handling large messages
public func runChunkedStdioExample() async throws {
    let logger = Logger(label: "chunked-stdio-example")
    logger.info("Starting Chunked Stdio Transport Example")
    
    // MARK: - Setup MCP Server with Adaptive Stdio Transport
    
    logger.info("Creating MCP server with adaptive stdio transport...")
    let server = MCPServer(
        name: "adaptive-example-server",
        version: "1.0.0"
        // No need to specify transport type - .stdio is adaptive by default!
        // It automatically handles both small and large messages
    )
    
    // Register a tool that returns a large response
    let toolDefinition = ToolDefinition(
        name: "generate_large_response",
        description: "Generate a large response to test chunking (returns data > 64KB)",
        parameters: [
            .init(
                name: "size_kb",
                description: "Size of the response in kilobytes",
                type: "number",
                required: true
            )
        ],
        type: .function
    )
    
    await server.registerTool(toolDefinition: toolDefinition) { arguments in
        let sizeKB: Double
        if case .double(let value) = arguments["size_kb"] {
            sizeKB = value
        } else if case .integer(let value) = arguments["size_kb"] {
            sizeKB = Double(value)
        } else {
            return .error("INVALID_PARAMS", "size_kb must be a number")
        }
        
        // Generate a large response
        let responseSize = Int(sizeKB) * 1024
        let largeData = String(repeating: "A", count: responseSize)
        let jsonResponse = """
        {
            "status": "success",
            "size_requested": \(sizeKB),
            "size_actual": \(responseSize),
            "data": "\(largeData)"
        }
        """
        
        return .success(jsonResponse)
    }
    
    logger.info("Registered tool: generate_large_response")
    logger.info("Tool can generate responses of any size - chunking is automatic!")
    
    // Note: To actually start the server, you would call:
    // try await server.start()
    // 
    // The server automatically:
    // - Sends small messages as plain JSON-RPC for compatibility
    // - Chunks large messages (>60KB) to avoid pipe limits
    // - Receives both plain and chunked messages from clients
    
    logger.info("✓ Server configured with adaptive stdio transport")
    
    // MARK: - Client Side
    
    logger.info("\nClient Side Configuration:")
    logger.info("The client automatically handles both plain and chunked messages.")
    logger.info("No special configuration needed!")
    logger.info("")
    logger.info("Example client code:")
    logger.info("""
    let client = MCPClient(name: "my-client")
    let inPipe = Pipe()
    let outPipe = Pipe()
    
    // Connect to the server - automatically adapts to message sizes
    try await client.connect(inPipe: inPipe, outPipe: outPipe)
    
    // Call a tool that returns a large response - works transparently!
    let result = try await client.callTool(
        "generate_large_response",
        arguments: ["size_kb": .number(100)]  // Request 100KB response
    )
    """)
    
    // MARK: - Technical Details
    
    logger.info("\nTechnical Details:")
    logger.info("1. Small messages (<60KB) sent as plain JSON-RPC for compatibility")
    logger.info("2. Large messages (≥60KB) automatically chunked into ~60KB frames")
    logger.info("3. Each chunk is framed with: messageId:chunkIndex:totalChunks:data")
    logger.info("4. Chunks are reassembled on the receiving end transparently")
    logger.info("5. Receiving side handles both plain and chunked messages")
    logger.info("")
    logger.info("Benefits:")
    logger.info("- Handles messages of any size (not limited to 64KB)")
    logger.info("- Transparent to the application layer")
    logger.info("- Compatible with all MCP clients/servers")
    logger.info("- Works around macOS pipe buffer limitations")
    logger.info("- No configuration or capability negotiation needed")
    
    logger.info("\n✓ Adaptive Stdio Example Complete")
}

