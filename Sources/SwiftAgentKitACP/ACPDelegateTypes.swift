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
    case messageChunk(text: String)
    case plan(entries: [ACPPlanEntry])
    case toolCall(toolCallId: String, title: String?, kind: String?, status: String?)
    case toolCallUpdate(toolCallId: String, status: String?, content: [ACPContentBlock]?)
    case completed(content: String, stopReason: ACPStopReason, sessionID: String?)
    case failed(error: String, sessionID: String?)
}
