//
//  A2ADelegateTypes.swift
//  SwiftAgentKitA2A
//

import Foundation
import SwiftAgentKit

/// Alias for A2A task state used in delegate stream events.
public typealias A2ATaskState = TaskState

/// Errors thrown by ``A2AManager/streamAgentCall(_:invocationID:orchestratorDefaultTimeout:)`` before streaming begins.
public enum A2AManagerError: Error, Sendable, Equatable {
    case agentNotFound(String)
    case invalidArguments
}

/// Snapshot of an in-flight A2A delegate invocation tracked by ``A2AManager``.
public struct A2AInFlightInvocation: Sendable, Equatable {
    public let invocationID: String
    public let toolCallID: String?
    public let agentName: String
    public var taskID: String?
    public var contextID: String?

    public init(
        invocationID: String,
        toolCallID: String?,
        agentName: String,
        taskID: String? = nil,
        contextID: String? = nil
    ) {
        self.invocationID = invocationID
        self.toolCallID = toolCallID
        self.agentName = agentName
        self.taskID = taskID
        self.contextID = contextID
    }
}

/// Correlates an in-flight A2A delegate invocation with lifecycle and tool-call identity.
public struct A2ADelegateInvocationHandle: Sendable, Equatable {
    public let invocationID: String
    public let toolCallID: String?
    public let agentName: String
    public var taskID: String?
    public var contextID: String?

    public init(
        invocationID: String,
        toolCallID: String?,
        agentName: String,
        taskID: String? = nil,
        contextID: String? = nil
    ) {
        self.invocationID = invocationID
        self.toolCallID = toolCallID
        self.agentName = agentName
        self.taskID = taskID
        self.contextID = contextID
    }
}

/// Normalized incremental events emitted while an A2A agent call is in flight.
public enum A2ADelegateStreamEvent: Sendable {
    case connecting(agentName: String)
    case taskStarted(taskID: String, contextID: String)
    case statusUpdate(taskID: String, state: A2ATaskState, final: Bool)
    case artifactChunk(taskID: String, text: String, append: Bool, lastChunk: Bool)
    case messageChunk(text: String, images: [Message.Image], files: [LLMResponseFile])
    case completed(A2ADelegateCompletion)
    case failed(A2ADelegateFailure)
}

/// Terminal success payload for an A2A delegate stream.
public struct A2ADelegateCompletion: Sendable {
    public let content: String
    public let metadata: LLMMetadata?
    public let taskID: String?
    public let contextID: String?

    public init(content: String, metadata: LLMMetadata?, taskID: String?, contextID: String?) {
        self.content = content
        self.metadata = metadata
        self.taskID = taskID
        self.contextID = contextID
    }
}

/// Terminal failure payload for an A2A delegate stream.
public struct A2ADelegateFailure: Sendable {
    public let error: String
    public let taskID: String?

    public init(error: String, taskID: String?) {
        self.error = error
        self.taskID = taskID
    }
}
