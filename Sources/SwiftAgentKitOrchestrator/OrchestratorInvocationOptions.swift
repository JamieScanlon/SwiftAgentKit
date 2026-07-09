import Foundation
import SwiftAgentKit
import EasyJSON

/// Per-`updateConversation` overrides layered on top of ``OrchestratorConfig``.
///
/// `nil` fields mean “use the value from ``OrchestratorConfig``.”
public struct OrchestratorInvocationOptions: Sendable {
    /// Merged with ``OrchestratorConfig/additionalParameters`` (later keys win).
    public var additionalParameters: JSON?
    /// Convenience for string metadata; shallow-merged as a JSON object into additional parameters.
    public var systemPromptMetadata: [String: String]?
    public var toolInvocationPolicy: ToolInvocationPolicy?
    public var assistantPersistenceMode: AssistantPersistenceMode?
    public var parallelToolDispatchEnabled: Bool?
    public var dispatchPlannerMode: ToolDispatchPlannerMode?
    /// Optional override for ``OrchestratorConfig/maxParallelInFlightPerStage``.
    public var maxParallelInFlightPerStage: Int?
    /// Optional per-call safety metadata keyed by toolCallID.
    public var toolParallelSafetyMetadata: [ToolCallID: ToolParallelSafety]?
    public var preDispatchPolicyEvaluator: (any ToolPreDispatchPolicyEvaluating)?
    public var maxAgenticStepsPerUpdate: Int?
    public var rejectAssistantTurnWithNoToolCallsWhenToolsAvailable: Bool?
    public var maxCorrectionRetries: Int?
    public var correctionMessage: String?
    public var correctionRole: MessageRole?
    /// Provider-normalized JSON Schema per tool name for LLM dispatch.
    public var toolParameterSchemasByName: [String: JSON]?
    /// Per-tool OpenAI strict schema flag for LLM dispatch.
    public var toolSchemaStrictByName: [String: Bool]?

    public static let `default` = OrchestratorInvocationOptions()

    public init(
        additionalParameters: JSON? = nil,
        systemPromptMetadata: [String: String]? = nil,
        toolInvocationPolicy: ToolInvocationPolicy? = nil,
        assistantPersistenceMode: AssistantPersistenceMode? = nil,
        parallelToolDispatchEnabled: Bool? = nil,
        dispatchPlannerMode: ToolDispatchPlannerMode? = nil,
        maxParallelInFlightPerStage: Int? = nil,
        toolParallelSafetyMetadata: [ToolCallID: ToolParallelSafety]? = nil,
        preDispatchPolicyEvaluator: (any ToolPreDispatchPolicyEvaluating)? = nil,
        maxAgenticStepsPerUpdate: Int? = nil,
        rejectAssistantTurnWithNoToolCallsWhenToolsAvailable: Bool? = nil,
        maxCorrectionRetries: Int? = nil,
        correctionMessage: String? = nil,
        correctionRole: MessageRole? = nil,
        toolParameterSchemasByName: [String: JSON]? = nil,
        toolSchemaStrictByName: [String: Bool]? = nil
    ) {
        self.additionalParameters = additionalParameters
        self.systemPromptMetadata = systemPromptMetadata
        self.toolInvocationPolicy = toolInvocationPolicy
        self.assistantPersistenceMode = assistantPersistenceMode
        self.parallelToolDispatchEnabled = parallelToolDispatchEnabled
        self.dispatchPlannerMode = dispatchPlannerMode
        self.maxParallelInFlightPerStage = maxParallelInFlightPerStage
        self.toolParallelSafetyMetadata = toolParallelSafetyMetadata
        self.preDispatchPolicyEvaluator = preDispatchPolicyEvaluator
        self.maxAgenticStepsPerUpdate = maxAgenticStepsPerUpdate
        self.rejectAssistantTurnWithNoToolCallsWhenToolsAvailable = rejectAssistantTurnWithNoToolCallsWhenToolsAvailable
        self.maxCorrectionRetries = maxCorrectionRetries
        self.correctionMessage = correctionMessage
        self.correctionRole = correctionRole
        self.toolParameterSchemasByName = toolParameterSchemasByName
        self.toolSchemaStrictByName = toolSchemaStrictByName
    }
}
