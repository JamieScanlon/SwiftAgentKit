import Foundation

public enum ToolExecutionOutcome: Sendable, Equatable {
    case completed(ToolResult)
    case pending(PendingToolHandle)
}

public struct PendingToolHandle: Sendable, Equatable, Codable {
    public let handleID: String
    public let toolCallID: String
    public let provider: String?
    public let startedAt: Date

    public init(
        handleID: String,
        toolCallID: String,
        provider: String? = nil,
        startedAt: Date = Date()
    ) {
        self.handleID = handleID
        self.toolCallID = toolCallID
        self.provider = provider
        self.startedAt = startedAt
    }
}

public struct PendingToolCompletion: Sendable, Equatable, Codable {
    public let handleID: String
    public let toolCallID: String
    public let result: ToolResult
    public let completedAt: Date

    public init(
        handleID: String,
        toolCallID: String,
        result: ToolResult,
        completedAt: Date = Date()
    ) {
        self.handleID = handleID
        self.toolCallID = toolCallID
        self.result = result
        self.completedAt = completedAt
    }
}

public protocol PendingToolCompletionSink: Sendable {
    func onPendingCompletion(_ completion: PendingToolCompletion) async
}

public enum ToolLifecycleState: Sendable, Equatable, Codable {
    case started
    case pending
    case completed
    case failed(String?)
    case cancelled
}

public struct ToolLifecycleEvent: Sendable, Equatable, Codable {
    public let toolCallID: String
    public let toolName: String?
    public let state: ToolLifecycleState
    public let timestamp: Date
    public let dispatchMode: ToolDispatchMode?

    public init(
        toolCallID: String,
        toolName: String?,
        state: ToolLifecycleState,
        timestamp: Date = Date(),
        dispatchMode: ToolDispatchMode? = nil
    ) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.state = state
        self.timestamp = timestamp
        self.dispatchMode = dispatchMode
    }
}

/// Broadcast hub for tool lifecycle events.
public final class ToolLifecycleEventHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<ToolLifecycleEvent>.Continuation] = [:]

    public init() {}

    public func publish(_ event: ToolLifecycleEvent) {
        let current: [AsyncStream<ToolLifecycleEvent>.Continuation]
        lock.lock()
        current = Array(continuations.values)
        lock.unlock()

        for continuation in current {
            continuation.yield(event)
        }
    }

    public func makeStream() -> AsyncStream<ToolLifecycleEvent> {
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
