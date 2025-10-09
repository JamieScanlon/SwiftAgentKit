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
    
    // MARK: - Setup MCP Server with Chunked Stdio Transport
    
    logger.info("Creating MCP server with chunked stdio transport...")
    let server = MCPServer(
        name: "chunked-example-server",
        version: "1.0.0",
        transportType: .chunkedStdio  // Use chunked stdio to handle large messages
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
    logger.info("Tool can generate responses larger than the 64KB pipe limit")
    
    // Note: To actually start the server, you would call:
    // try await server.start()
    // 
    // The server would then communicate via stdio using chunked frames
    // to handle messages larger than 64KB
    
    logger.info("✓ Server configured with chunked stdio transport")
    
    // MARK: - Client Side
    
    logger.info("\nClient Side Configuration:")
    logger.info("When connecting to a server with chunked stdio, the ClientTransport")
    logger.info("automatically handles chunking and reassembly of large messages.")
    logger.info("")
    logger.info("Example client code:")
    logger.info("""
    let client = MCPClient(name: "chunked-client")
    let inPipe = Pipe()
    let outPipe = Pipe()
    
    // Connect to the server
    try await client.connect(inPipe: inPipe, outPipe: outPipe)
    
    // Call a tool that returns a large response
    let result = try await client.callTool(
        "generate_large_response",
        arguments: ["size_kb": .number(100)]  // Request 100KB response
    )
    """)
    
    // MARK: - Technical Details
    
    logger.info("\nTechnical Details:")
    logger.info("1. Messages are automatically chunked when they exceed ~60KB")
    logger.info("2. Each chunk is framed with: messageId:chunkIndex:totalChunks:data")
    logger.info("3. Chunks are reassembled on the receiving end transparently")
    logger.info("4. Frame format is newline-delimited for compatibility")
    logger.info("")
    logger.info("Benefits:")
    logger.info("- Handles messages of any size (not limited to 64KB)")
    logger.info("- Transparent to the application layer")
    logger.info("- Compatible with JSON-RPC and MCP protocols")
    logger.info("- Works around macOS pipe buffer limitations")
    
    logger.info("\n✓ Chunked Stdio Example Complete")
}

