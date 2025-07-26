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

extension ToolDefinition {
    public init(tool: Tool) {
        
        var parameters: [ToolDefinition.Parameter] = []
        if case .object(let inputSchema) = tool.inputSchema {
            if case .object(let propertiesValue) = inputSchema["properties"] {
                
                var requiredArray: [String] = []
                if case .array(let requiredValue) = inputSchema["required"] {
                    requiredArray = requiredValue.compactMap({
                        if case .string(let stringValue) = $0 {
                            return stringValue
                        } else {
                            return nil
                        }
                    })
                    
                }
                
                for (key, value) in propertiesValue {
                    
                    guard case .object(let objectValue) = value else { continue }
                    let name: String = key
                    var description = ""
                    var type: String = ""
                    let required: Bool = requiredArray.contains(key)
                    if case .string(let stringValue) = objectValue["type"] {
                        type = stringValue
                    }
                    if case .string(let stringValue) = objectValue["description"] {
                        description = stringValue
                    }
                    parameters.append(.init(name: name, description: description, type: type, required: required))
                }
            }
        }
        self.name = tool.name
        self.description = tool.description
        self.parameters = parameters
        self.type = .mcpTool
    }
}

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
                    parameters: [],
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
                // Convert ToolCall arguments to MCP Value format
                let arguments = toolCall.argumentsToValue()
                
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
