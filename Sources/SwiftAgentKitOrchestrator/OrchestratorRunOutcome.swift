import Foundation
import SwiftAgentKit

public enum AssistantPersistenceMode: Sendable, Equatable, Codable {
    case immediate
    case stagedCommit
}

public enum OrchestratorTerminalState: Sendable, Equatable, Codable {
    case completed
    case cancelled
    case failed
}

public enum OrchestratorTerminalReason: Sendable, Equatable, Codable {
    case externalCancellation
    case naturalStop
    case boundedStop(limit: Int)
    case failure(String?)
}

public struct UpdateConversationOutcome: Sendable, Equatable, Codable {
    public let runID: AgenticLoopID
    public let terminalState: OrchestratorTerminalState
    public let terminalReason: OrchestratorTerminalReason
    public let assistantCommitted: Bool

    public init(
        runID: AgenticLoopID,
        terminalState: OrchestratorTerminalState,
        terminalReason: OrchestratorTerminalReason,
        assistantCommitted: Bool
    ) {
        self.runID = runID
        self.terminalState = terminalState
        self.terminalReason = terminalReason
        self.assistantCommitted = assistantCommitted
    }
}

public struct CancelOutcome: Sendable, Equatable, Codable {
    public let runID: AgenticLoopID
    public let cancelledToolHandles: [PendingToolHandle]
    public let terminalState: OrchestratorTerminalState

    public init(
        runID: AgenticLoopID,
        cancelledToolHandles: [PendingToolHandle],
        terminalState: OrchestratorTerminalState
    ) {
        self.runID = runID
        self.cancelledToolHandles = cancelledToolHandles
        self.terminalState = terminalState
    }
}

public struct RecoverableActiveRunMetadata: Sendable, Equatable, Codable {
    public let runID: AgenticLoopID
    public let pendingHandleIDs: [String]
    public let cancellationRequested: Bool

    public init(
        runID: AgenticLoopID,
        pendingHandleIDs: [String],
        cancellationRequested: Bool
    ) {
        self.runID = runID
        self.pendingHandleIDs = pendingHandleIDs
        self.cancellationRequested = cancellationRequested
    }
}
