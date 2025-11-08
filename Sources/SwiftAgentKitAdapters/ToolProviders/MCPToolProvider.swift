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
    private let logger: Logger
    
    public var name: String { "MCP Tools" }
    
    public func availableTools() async -> [ToolDefinition] {
        var tools: [ToolDefinition] = []
        for client in clients {
            let clientTools = await client.tools
            tools.append(contentsOf: clientTools)
        }
        return tools
    }
    
    public init(clients: [MCPClient], logger: Logger? = nil) {
        self.clients = clients
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .adapters("MCPToolProvider"),
            metadata: SwiftAgentKitLogging.metadata(
                ("clientCount", .stringConvertible(clients.count))
            )
        )
    }
    
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        for client in clients {
            let clientName = await client.name
            // Check if this client has the requested tool
            let clientTools = await client.tools
            guard clientTools.contains(where: { $0.name == toolCall.name }) else { continue }
            
            do {
                // Convert ToolCall arguments to MCP Value format
                let arguments = toolCall.argumentsToValue()
                
                if let contents = try await client.callTool(toolCall.name, arguments: arguments) {
                    let content = contents.compactMap { content in
                        if case .text(let text) = content { return text } else { return nil }
                    }.joined(separator: "\n")
                    return ToolResult(
                        success: true,
                        content: content,
                        metadata: .object(["source": .string("mcp_tool")]),
                        toolCallId: toolCall.id
                    )
                }
            } catch {
                logger.warning(
                    "MCP client tool execution failed",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("toolName", .string(toolCall.name)),
                        ("client", .string(clientName)),
                        ("error", .string(String(describing: error)))
                    )
                )
                continue
            }
        }
        
        return ToolResult(
            success: false,
            content: "",
            toolCallId: toolCall.id,
            error: "MCP tool not found or failed"
        )
    }
} 
