//
//  MCPToolProvider.swift
//  SwiftAgentKitAdapters
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import Logging
import MCP
import SwiftAgentKit
import SwiftAgentKitMCP

/// Direct MCP tool provider
public struct MCPToolProvider: ToolProvider {
    private let clients: [MCPClient]
    private let logger = Logger(label: "MCPToolProvider")
    
    public var name: String { "MCP Tools" }
    
    public func availableTools() async -> [ToolDefinition] {
        var tools: [ToolDefinition] = []
        for client in clients {
            let clientTools = await client.tools
            for tool in clientTools {
                tools.append(ToolDefinition(
                    name: tool.name,
                    description: tool.description,
                    type: .mcpTool
                ))
            }
        }
        return tools
    }
    
    public init(clients: [MCPClient]) {
        self.clients = clients
    }
    
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        for client in clients {
            // Check if this client has the requested tool
            let clientTools = await client.tools
            guard clientTools.contains(where: { $0.name == toolCall.name }) else { continue }
            
            do {
                // For now, pass arguments as-is - MCP module should handle conversion
                let arguments: [String: Value]? = nil
                
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