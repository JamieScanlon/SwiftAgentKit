import Foundation
import EasyJSON

/// Wrapper provider that forwards all behavior and metadata to an inner provider.
///
/// Use this as a base for wrappers that add logging, policy checks, persistence, or transforms
/// without accidentally dropping descriptor metadata methods.
public struct ForwardingToolProvider: ToolProvider {
    public let inner: any ToolProvider

    public init(inner: any ToolProvider) {
        self.inner = inner
    }

    public var name: String { inner.name }

    public func availableTools() async -> [ToolDefinition] {
        await inner.availableTools()
    }

    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        try await inner.executeTool(toolCall)
    }

    public func executeToolOutcome(_ toolCall: ToolCall) async throws -> ToolExecutionOutcome {
        try await inner.executeToolOutcome(toolCall)
    }

    public func cancelPending(handleID: String, toolCallID: String) async -> Bool {
        await inner.cancelPending(handleID: handleID, toolCallID: toolCallID)
    }

    public func parallelSafety(for toolCall: ToolCall) async -> ToolParallelSafety {
        await inner.parallelSafety(for: toolCall)
    }

    public func registrationSource(for definition: ToolDefinition) async -> ToolRegistrationSource {
        await inner.registrationSource(for: definition)
    }

    public func effectClass(for definition: ToolDefinition) async -> ToolEffectClass {
        await inner.effectClass(for: definition)
    }

    public func executionParallelHint(for definition: ToolDefinition) async -> ToolExecutionParallelHint {
        await inner.executionParallelHint(for: definition)
    }

    public func policyTags(for definition: ToolDefinition) async -> [ToolPolicyTag] {
        await inner.policyTags(for: definition)
    }

    public func rawSchema(for definition: ToolDefinition) async -> JSON? {
        await inner.rawSchema(for: definition)
    }
}
