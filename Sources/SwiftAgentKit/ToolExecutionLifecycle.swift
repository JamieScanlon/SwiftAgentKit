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

public enum ToolLifecycleEventName: String, Sendable, Equatable, Codable {
    case toolCallStarted = "tool.callStarted"
    case toolCallCompleted = "tool.callCompleted"
    case toolCallFailed = "tool.callFailed"
    case toolApprovalRequired = "tool.approvalRequired"
    case toolApprovalResolved = "tool.approvalResolved"
    case toolElevatedExecuted = "tool.elevatedExecuted"
}

public struct ToolLifecycleEvent: Sendable, Equatable, Codable {
    public let eventName: ToolLifecycleEventName
    public let toolCallID: String
    public let toolName: String?
    public let state: ToolLifecycleState
    public let timestamp: Date
    public let dispatchMode: ToolDispatchMode?
    public let conversationID: String?
    public let runID: String?
    public let source: String?
    public let reasonCode: String?
    public let reasonText: String?
    public let policyDecision: String?

    public init(
        eventName: ToolLifecycleEventName,
        toolCallID: String,
        toolName: String?,
        state: ToolLifecycleState,
        timestamp: Date = Date(),
        dispatchMode: ToolDispatchMode? = nil,
        conversationID: String? = nil,
        runID: String? = nil,
        source: String? = nil,
        reasonCode: String? = nil,
        reasonText: String? = nil,
        policyDecision: String? = nil
    ) {
        self.eventName = eventName
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.state = state
        self.timestamp = timestamp
        self.dispatchMode = dispatchMode
        self.conversationID = conversationID
        self.runID = runID
        self.source = source
        self.reasonCode = reasonCode
        self.reasonText = reasonText
        self.policyDecision = policyDecision
    }

    public init(
        toolCallID: String,
        toolName: String?,
        state: ToolLifecycleState,
        timestamp: Date = Date(),
        dispatchMode: ToolDispatchMode? = nil
    ) {
        let derivedEventName: ToolLifecycleEventName
        switch state {
        case .started:
            derivedEventName = .toolCallStarted
        case .pending:
            derivedEventName = .toolApprovalRequired
        case .completed:
            derivedEventName = .toolCallCompleted
        case .failed:
            derivedEventName = .toolCallFailed
        case .cancelled:
            derivedEventName = .toolCallFailed
        }
        self.init(
            eventName: derivedEventName,
            toolCallID: toolCallID,
            toolName: toolName,
            state: state,
            timestamp: timestamp,
            dispatchMode: dispatchMode
        )
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
