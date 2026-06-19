//
//  ACPDelegateTypes.swift
//  SwiftAgentKitACP
//

import Foundation
import SwiftAgentKit

/// Errors thrown by ``ACPManager/streamAgentCall(_:invocationID:orchestratorDefaultTimeout:)`` before streaming begins.
public enum ACPManagerError: Error, Sendable, Equatable {
    case agentNotFound(String)
    case invalidArguments
}

/// Snapshot of an in-flight ACP delegate invocation tracked by ``ACPManager``.
public struct ACPInFlightInvocation: Sendable, Equatable {
    public let invocationID: String
    public let toolCallID: String?
    public let agentName: String
    public var sessionID: String?

    public init(
        invocationID: String,
        toolCallID: String?,
        agentName: String,
        sessionID: String? = nil
    ) {
        self.invocationID = invocationID
        self.toolCallID = toolCallID
        self.agentName = agentName
        self.sessionID = sessionID
    }
}

/// Correlates an in-flight ACP delegate invocation with lifecycle and tool-call identity.
public struct ACPDelegateInvocationHandle: Sendable, Equatable {
    public let invocationID: String
    public let toolCallID: String?
    public let agentName: String
    public var sessionID: String?

    public init(
        invocationID: String,
        toolCallID: String?,
        agentName: String,
        sessionID: String? = nil
    ) {
        self.invocationID = invocationID
        self.toolCallID = toolCallID
        self.agentName = agentName
        self.sessionID = sessionID
    }
}

/// Normalized incremental events emitted while an ACP agent call is in flight.
public enum ACPDelegateStreamEvent: Sendable {
    case connecting(agentName: String)
    case userMessageChunk(messageId: String?, text: String)
    case messageChunk(text: String)
    case thoughtChunk(messageId: String?, text: String)
    case availableCommandsUpdate(commands: [ACPAvailableCommand])
    case plan(entries: [ACPPlanEntry])
    case toolCall(ACPToolCallUpdate)
    case toolCallUpdate(ACPToolCallUpdate)
    case usageUpdate(used: Int, size: Int, cost: ACPUsageCost?)
    case sessionInfoUpdate(ACPSessionInfoUpdate)
    case currentModeUpdate(modeId: String)
    case configOptionUpdate(configOptions: [ACPSessionConfigOption])
    case completed(content: String, stopReason: ACPStopReason, sessionID: String?)
    case failed(error: String, sessionID: String?)
}
