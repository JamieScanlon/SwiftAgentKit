import Foundation
import EasyJSON

/// Protocol for any system that can provide tools (A2A agents or MCP tools)
public protocol ToolProvider: Sendable {
    var name: String { get }
    func availableTools() async -> [ToolDefinition]
    func executeTool(_ toolCall: ToolCall) async throws -> ToolResult
} 