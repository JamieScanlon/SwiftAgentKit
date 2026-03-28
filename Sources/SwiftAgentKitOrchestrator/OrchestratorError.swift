import Foundation

/// Errors thrown by ``SwiftAgentKitOrchestrator`` for harness safety and policy limits.
public enum OrchestratorError: Error, LocalizedError, Sendable {
    /// ``OrchestratorConfig/maxAgenticStepsPerUpdate`` was exceeded for one `updateConversation` call.
    case agenticStepLimitReached(limit: Int)
    /// Assistant turn was rejected (prose without tools) and correction retries were exhausted.
    case assistantTurnCorrectionRetriesExhausted(configuredMaxCorrectionRetries: Int)

    public var errorDescription: String? {
        switch self {
        case .agenticStepLimitReached(let limit):
            return "Agentic step limit reached: \(limit) LLM invocations per updateConversation."
        case .assistantTurnCorrectionRetriesExhausted(let max):
            return "Assistant turn rejected after exhausting correction retries (maxCorrectionRetries=\(max))."
        }
    }
}
