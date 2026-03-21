import Foundation

// MARK: - Identity

/// Identifies a single `LLMProtocol` invocation (`send`, `stream`, or `generateImage`).
public struct LLMRequestID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    /// The in-flight request ID for the current task, when set by `QueuedLLM` or `StatefulLLM`.
    @TaskLocal public static var current: LLMRequestID?
}

// MARK: - Per-call state

/// Lifecycle of one LLM call. Distinct from [`LLMRuntimeState`](LLMRuntimeState.swift) (instance / model).
///
/// - `queued` is emitted only by queue-aware wrappers such as [`QueuedLLM`](QueuedLLM.swift).
/// - Sub-phases like ``LLMGenerationState`` mirror generation while the call is active.
public enum LLMRequestState: Sendable, Equatable, Codable {
    /// Waiting for a queue slot (only from `QueuedLLM`).
    case queued
    /// Slot acquired; work not yet attributed to a specific generation sub-phase.
    case active
    /// Actively generating with a fine-grained phase.
    case generating(LLMGenerationState)
    /// Streaming output (token/chunk delivery).
    case streaming
    /// Call finished successfully.
    case completed
    /// Call failed with an error description.
    case failed(String?)
    /// Call was cancelled.
    case cancelled
}

// MARK: - Hub

/// Broadcasts per-request state updates to all subscribers.
public final class LLMRequestStateHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<(LLMRequestID, LLMRequestState)>.Continuation] = [:]

    public init() {}

    /// When set (e.g. by `QueuedLLM`), `StatefulLLM` publishes into this hub instead of its own.
    @TaskLocal public static var current: LLMRequestStateHub?

    public func publish(_ id: LLMRequestID, _ state: LLMRequestState) {
        let activeContinuations: [AsyncStream<(LLMRequestID, LLMRequestState)>.Continuation]
        lock.lock()
        activeContinuations = Array(continuations.values)
        lock.unlock()

        for continuation in activeContinuations {
            continuation.yield((id, state))
        }
    }

    public func makeStream() -> AsyncStream<(LLMRequestID, LLMRequestState)> {
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
