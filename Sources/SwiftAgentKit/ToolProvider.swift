import Foundation
import EasyJSON

/// Protocol for any system that can provide tools (A2A agents or MCP tools)
public protocol ToolProvider: Sendable {
    var name: String { get }
    func availableTools() async -> [ToolDefinition]
    func executeTool(_ toolCall: ToolCall) async throws -> ToolResult
    /// Override to return `.pending` when execution is accepted now and completed later.
    func executeToolOutcome(_ toolCall: ToolCall) async throws -> ToolExecutionOutcome
    /// Optional cancellation hook for pending handles.
    func cancelPending(handleID: String, toolCallID: String) async -> Bool
    /// Optional parallel-safety metadata at dispatch boundary.
    func parallelSafety(for toolCall: ToolCall) async -> ToolParallelSafety
}

public extension ToolProvider {
    func executeToolOutcome(_ toolCall: ToolCall) async throws -> ToolExecutionOutcome {
        .completed(try await executeTool(toolCall))
    }

    func cancelPending(handleID: String, toolCallID: String) async -> Bool {
        false
    }

    func parallelSafety(for toolCall: ToolCall) async -> ToolParallelSafety {
        .unknown
    }
}
