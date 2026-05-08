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
    /// Optional canonical registration source override.
    func registrationSource(for definition: ToolDefinition) async -> ToolRegistrationSource
    /// Optional canonical effect hint override.
    func effectClass(for definition: ToolDefinition) async -> ToolEffectClass
    /// Optional canonical execution-parallel hint override.
    func executionParallelHint(for definition: ToolDefinition) async -> ToolExecutionParallelHint
    /// Optional policy tags override.
    func policyTags(for definition: ToolDefinition) async -> [ToolPolicyTag]
    /// Optional raw schema override for normalization/fingerprinting.
    func rawSchema(for definition: ToolDefinition) async -> JSON?
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

    func registrationSource(for definition: ToolDefinition) async -> ToolRegistrationSource {
        switch definition.type {
        case .function: return .local
        case .mcpTool: return .mcp
        case .a2aAgent: return .a2a
        }
    }

    func effectClass(for definition: ToolDefinition) async -> ToolEffectClass {
        .unknown
    }

    func executionParallelHint(for definition: ToolDefinition) async -> ToolExecutionParallelHint {
        .unknown
    }

    func policyTags(for definition: ToolDefinition) async -> [ToolPolicyTag] {
        []
    }

    func rawSchema(for definition: ToolDefinition) async -> JSON? {
        nil
    }
}
