import Foundation

// MARK: - Identity

/// Identifies one agentic tool loop (multiple LLM calls and tool runs within a single logical turn).
public enum AgenticLoopID: Hashable, Sendable, Codable {
    /// A2A adapter path: stable key from task and context.
    case a2a(taskId: String, contextId: String)
    /// Orchestrator path: session id for one `updateConversation` tree (including recursive tool continuations).
    case orchestratorSession(UUID)
}

// MARK: - Generation summary

/// Observed outcome of one completed model generation inside an agentic loop (beta).
public struct LLMGenerationSummary: Sendable, Equatable, Codable {
    /// 1-based index of this LLM completion within the current `updateConversation` tree (matches ``AgenticLoopState/llmCall(iteration:)`` for that step).
    public var innerStepIndex: Int
    public var hadToolCalls: Bool
    public var toolNames: [String]
    public var finishReason: String?
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?

    public init(
        innerStepIndex: Int,
        hadToolCalls: Bool,
        toolNames: [String],
        finishReason: String? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil
    ) {
        self.innerStepIndex = innerStepIndex
        self.hadToolCalls = hadToolCalls
        self.toolNames = toolNames
        self.finishReason = finishReason
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

// MARK: - State

/// Coarse lifecycle for an agentic turn (tool loop until a final answer or failure).
///
/// Distinct from ``LLMRuntimeState`` (shared LLM instance) and ``LLMRequestState`` (one `send` / `stream`).
public enum AgenticLoopState: Sendable, Equatable, Codable {
    case started
    case llmCall(iteration: Int)
    /// Emitted after each finished model generation (sync or streaming complete) for observability.
    case llmGenerationCompleted(LLMGenerationSummary)
    case waitingForToolExecution
    case executingTools
    case betweenIterations
    case completed
    case failed(String?)
    case maxIterationsReached
}

// MARK: - Hub

/// Broadcasts agentic-loop state updates to all subscribers.
///
/// **Retention:** The hub keeps the **last published** state per ``AgenticLoopID`` until it is
/// overwritten by another `publish` for the **same** id (or until the process exits). Completed
/// loops are **not** removed automatically. For ``AgenticLoopID/orchestratorSession(_:)``, each
/// top-level ``SwiftAgentKitOrchestrator/updateConversation`` uses a **new** UUID, so older session
/// ids typically remain in ``currentStates`` as `.completed` / `.failed` while new turns add new
/// entries. Hosts should treat the loop id tied to the **current** user turn (or task) as
/// authoritative for UI, not “the only id in the dictionary.”
public final class AgenticLoopStateHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<(AgenticLoopID, AgenticLoopState)>.Continuation] = [:]
    private var lastStates: [AgenticLoopID: AgenticLoopState] = [:]

    public init() {}

    /// Latest published state for the given agentic loop id, if any.
    public func currentState(for id: AgenticLoopID) -> AgenticLoopState? {
        lock.lock()
        defer { lock.unlock() }
        return lastStates[id]
    }

    /// Snapshot of the latest published state per agentic loop id.
    public var currentStates: [AgenticLoopID: AgenticLoopState] {
        lock.lock()
        let snapshot = lastStates
        lock.unlock()
        return snapshot
    }

    public func publish(_ id: AgenticLoopID, _ state: AgenticLoopState) {
        let activeContinuations: [AsyncStream<(AgenticLoopID, AgenticLoopState)>.Continuation]
        lock.lock()
        lastStates[id] = state
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
