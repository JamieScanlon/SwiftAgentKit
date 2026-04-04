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
    public var maxAgenticStepsPerUpdate: Int?
    public var rejectAssistantTurnWithNoToolCallsWhenToolsAvailable: Bool?
    public var maxCorrectionRetries: Int?
    public var correctionMessage: String?
    public var correctionRole: MessageRole?

    public static let `default` = OrchestratorInvocationOptions()

    public init(
        additionalParameters: JSON? = nil,
        systemPromptMetadata: [String: String]? = nil,
        toolInvocationPolicy: ToolInvocationPolicy? = nil,
        maxAgenticStepsPerUpdate: Int? = nil,
        rejectAssistantTurnWithNoToolCallsWhenToolsAvailable: Bool? = nil,
        maxCorrectionRetries: Int? = nil,
        correctionMessage: String? = nil,
        correctionRole: MessageRole? = nil
    ) {
        self.additionalParameters = additionalParameters
        self.systemPromptMetadata = systemPromptMetadata
        self.toolInvocationPolicy = toolInvocationPolicy
        self.maxAgenticStepsPerUpdate = maxAgenticStepsPerUpdate
        self.rejectAssistantTurnWithNoToolCallsWhenToolsAvailable = rejectAssistantTurnWithNoToolCallsWhenToolsAvailable
        self.maxCorrectionRetries = maxCorrectionRetries
        self.correctionMessage = correctionMessage
        self.correctionRole = correctionRole
    }
}
