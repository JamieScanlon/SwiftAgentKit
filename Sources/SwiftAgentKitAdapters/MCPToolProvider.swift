//
//  MCPToolProvider.swift
//  SwiftAgentKitAdapters
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitMCP

/// Direct MCP tool provider
public struct MCPToolProvider: ToolProvider {
    private let clients: [MCPClient]
    private let logger = Logger(label: "MCPToolProvider")
    
    public var name: String { "MCP Tools" }
    
    public var availableTools: [ToolDefinition] {
        clients.flatMap { client in
            // TODO: We need to make tools accessible from MCPClient
            // For now, this is a placeholder implementation
            client.tools.map { tool in
                ToolDefinition(
                    name: tool.name,
                    description: tool.description,
                    type: .mcpTool
                )
            }
        }
    }
    
    public init(clients: [MCPClient]) {
        self.clients = clients
    }
    
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        for client in clients {
            // TODO: We need to make tools accessible from MCPClient
            guard client.tools.contains(where: { $0.name == toolCall.name }) else { continue }
            
            do {
                // TODO: We need to implement argumentsToValue() method on ToolCall
                // For now, using a simplified approach
                let arguments = toolCall.arguments.compactMapValues { value in
                    // Convert to MCP Value type - this is a simplified conversion
                    // TODO: Implement proper conversion from [String: Any] to MCP Value
                    return nil
                }
                
                if let contents = try await client.callTool(toolCall.name, arguments: arguments) {
                    let content = contents.compactMap { content in
                        if case .text(let text) = content { return text } else { return nil }
                    }.joined(separator: "\n")
                    return ToolResult(
                        success: true,
                        content: content,
                        metadata: .object(["source": .string("mcp_tool")])
                    )
                }
            } catch {
                logger.warning("MCP client call failed: \(error)")
                continue
            }
        }
        
        return ToolResult(
            success: false,
            content: "",
            error: "MCP tool not found or failed"
        )
    }
} 