import Foundation

// MARK: - Identity

/// Identifies one agentic tool loop (multiple LLM calls and tool runs within a single logical turn).
public enum AgenticLoopID: Hashable, Sendable, Codable {
    /// A2A adapter path: stable key from task and context.
    case a2a(taskId: String, contextId: String)
    /// Orchestrator path: session id for one `updateConversation` tree (including recursive tool continuations).
    case orchestratorSession(UUID)
}

// MARK: - State

/// Coarse lifecycle for an agentic turn (tool loop until a final answer or failure).
///
/// Distinct from ``LLMRuntimeState`` (shared LLM instance) and ``LLMRequestState`` (one `send` / `stream`).
public enum AgenticLoopState: Sendable, Equatable, Codable {
    case started
    case llmCall(iteration: Int)
    case waitingForToolExecution
    case executingTools
    case betweenIterations
    case completed
    case failed(String?)
    case maxIterationsReached
}

// MARK: - Hub

/// Broadcasts agentic-loop state updates to all subscribers.
public final class AgenticLoopStateHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<(AgenticLoopID, AgenticLoopState)>.Continuation] = [:]

    public init() {}

    public func publish(_ id: AgenticLoopID, _ state: AgenticLoopState) {
        let activeContinuations: [AsyncStream<(AgenticLoopID, AgenticLoopState)>.Continuation]
        lock.lock()
        activeContinuations = Array(continuations.values)
        lock.unlock()

        for continuation in activeContinuations {
            continuation.yield((id, state))
        }
    }

    public func makeStream() -> AsyncStream<(AgenticLoopID, AgenticLoopState)> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: id)
            }
        }
    }

    private func removeContinuation(id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}

// MARK: - Task-local (optional correlation)

extension AgenticLoopID {
    /// The agentic loop id for the current task, when set by ``LLMProtocolAdapter`` or ``SwiftAgentKitOrchestrator``.
    @TaskLocal public static var current: AgenticLoopID?
}
