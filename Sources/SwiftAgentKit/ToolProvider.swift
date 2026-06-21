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
    private func descriptorHint(for toolName: String) -> ToolDescriptorHints? {
        (self as? any ToolDescriptorHinting)?.descriptorHintsByToolName[toolName]
    }

    func executeToolOutcome(_ toolCall: ToolCall) async throws -> ToolExecutionOutcome {
        .completed(try await executeTool(toolCall))
    }

    func cancelPending(handleID: String, toolCallID: String) async -> Bool {
        false
    }

    func parallelSafety(for toolCall: ToolCall) async -> ToolParallelSafety {
        if let hint = descriptorHint(for: toolCall.name) {
            if let parallelSafety = hint.parallelSafety {
                return parallelSafety
            }
            switch hint.parallelHint {
            case .parallelizable:
                return .parallelSafe
            case .serialOnly:
                return .mutating
            case .unknown:
                return .unknown
            }
        }
        return .unknown
    }

    func registrationSource(for definition: ToolDefinition) async -> ToolRegistrationSource {
        switch definition.type {
        case .function: return .local
        case .mcpTool: return .mcp
        case .a2aAgent: return .a2a
        case .acpAgent: return .acp
        }
    }

    func effectClass(for definition: ToolDefinition) async -> ToolEffectClass {
        if let hint = descriptorHint(for: definition.name) {
            return hint.effectClass
        }
        return .unknown
    }

    func executionParallelHint(for definition: ToolDefinition) async -> ToolExecutionParallelHint {
        if let hint = descriptorHint(for: definition.name) {
            return hint.parallelHint
        }
        return .unknown
    }

    func policyTags(for definition: ToolDefinition) async -> [ToolPolicyTag] {
        if let hint = descriptorHint(for: definition.name) {
            return hint.policyTags
        }
        return []
    }

    func rawSchema(for definition: ToolDefinition) async -> JSON? {
        nil
    }
}
