//
//  ToolProvider.swift
//  SwiftAgentKitAdapters
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import EasyJSON
import SwiftAgentKit

/// Protocol for any system that can provide tools (A2A agents or MCP tools)
public protocol ToolProvider: Sendable {
    var name: String { get }
    var availableTools: [ToolDefinition] { get }
    func executeTool(_ toolCall: ToolCall) async throws -> ToolResult
}

/// Result of a tool execution
public struct ToolResult: Sendable {
    public let success: Bool
    public let content: String
    public let metadata: JSON
    public let error: String?
    
    public init(success: Bool, content: String, metadata: JSON = .object([:]), error: String? = nil) {
        self.success = success
        self.content = content
        self.metadata = metadata
        self.error = error
    }
}

/// Definition of an available tool
public struct ToolDefinition: Sendable, Codable {
    public let name: String
    public let description: String
    public let type: ToolType
    
    public init(name: String, description: String, type: ToolType) {
        self.name = name
        self.description = description
        self.type = type
    }
    
    public enum ToolType: String, Codable, Sendable {
        case a2aAgent = "a2a_agent"
        case mcpTool = "mcp_tool"
        case function = "function"
    }
}

/// Simple tool manager that coordinates multiple providers
public struct ToolManager: Sendable {
    private let providers: [ToolProvider]
    
    public init(providers: [ToolProvider] = []) {
        self.providers = providers
    }
    
    public var allTools: [ToolDefinition] {
        providers.flatMap { $0.availableTools }
    }
    
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        for provider in providers {
            do {
                let result = try await provider.executeTool(toolCall)
                if result.success {
                    return result
                }
            } catch {
                // Continue to next provider
                continue
            }
        }
        
        return ToolResult(
            success: false,
            content: "",
            error: "Tool '\(toolCall.name)' not found in any provider"
        )
    }
    
    public func addProvider(_ provider: ToolProvider) -> ToolManager {
        ToolManager(providers: providers + [provider])
    }
} 