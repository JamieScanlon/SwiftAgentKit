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
import EasyJSON

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
                    // Extract text content
                    let textContent = contents.compactMap { content in
                        if case .text(let text) = content { return text } else { return nil }
                    }.joined(separator: "\n")
                    
                    // Extract resource content (file:// URIs)
                    var fileResources: [[String: JSON]] = []
                    for content in contents {
                        if case .resource(let uri, let mimeType, let text) = content {
                            // Only handle file:// URIs
                            if uri.hasPrefix("file://") {
                                do {
                                    let fileURL = URL(string: uri)
                                    if let fileURL = fileURL, fileURL.scheme == "file" {
                                        // Read file data
                                        let fileData = try Data(contentsOf: fileURL)
                                        let base64Data = fileData.base64EncodedString()
                                        
                                        var resourceInfo: [String: JSON] = [
                                            "uri": .string(uri),
                                            "mimeType": .string(mimeType),
                                            "data": .string(base64Data)
                                        ]
                                        
                                        if let text = text {
                                            resourceInfo["name"] = .string(text)
                                        }
                                        
                                        fileResources.append(resourceInfo)
                                        
                                        logger.info(
                                            "Read file resource from MCP tool",
                                            metadata: SwiftAgentKitLogging.metadata(
                                                ("toolName", .string(toolCall.name)),
                                                ("uri", .string(uri)),
                                                ("mimeType", .string(mimeType)),
                                                ("size", .stringConvertible(fileData.count))
                                            )
                                        )
                                    }
                                } catch {
                                    logger.warning(
                                        "Failed to read file resource",
                                        metadata: SwiftAgentKitLogging.metadata(
                                            ("toolName", .string(toolCall.name)),
                                            ("uri", .string(uri)),
                                            ("error", .string(String(describing: error)))
                                        )
                                    )
                                }
                            }
                        }
                    }
                    
                    // Build metadata with file resources if any
                    var metadata: [String: JSON] = ["source": .string("mcp_tool")]
                    if !fileResources.isEmpty {
                        metadata["fileResources"] = .array(fileResources.map { .object($0) })
                    }
                    
                    return ToolResult(
                        success: true,
                        content: textContent,
                        metadata: .object(metadata),
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
