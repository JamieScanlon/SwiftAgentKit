//
//  ACPAgentAdapter.swift
//  SwiftAgentKitACP
//

import Foundation
import SwiftAgentKit

/// Pluggable behavior for an ACP Agent process.
public protocol ACPAgentAdapter: Sendable {
    var agentInfo: ACPImplementation { get }
    var agentCapabilities: ACPAgentCapabilities { get }
    var authMethods: [ACPAuthMethod] { get }

    func handlePrompt(
        sessionId: String,
        prompt: [ACPContentBlock],
        eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
    ) async throws -> ACPStopReason

    /// Streams prior conversation history during `session/load`.
    func loadSessionHistory(
        sessionId: String,
        eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
    ) async throws

    /// Called when a session is closed via `session/close`.
    func onSessionClosed(sessionId: String) async throws

    /// Called when a session is deleted via `session/delete`.
    func onSessionDeleted(sessionId: String) async throws

    /// Merges adapter-persisted sessions into in-memory list results.
    func supplementSessionList(
        cursor: String?,
        cwd: String?,
        knownSessions: [ACPSessionInfo]
    ) async throws -> (sessions: [ACPSessionInfo], nextCursor: String?)

    /// Validates credentials for the given auth method during `authenticate`.
    func authenticate(methodId: String) async throws

    /// Clears authenticated state during `logout`.
    func logout() async throws

    /// Supplies initial session configuration during `session/new`, `session/load`, and `session/resume`.
    func sessionSetup(
        sessionId: String,
        cwd: String,
        mcpServers: [ACPMcpServer]
    ) async throws -> (configOptions: [ACPSessionConfigOption]?, mode: ACPSessionModeState?)

    /// Changes the active mode for a session via `session/set_mode`.
    func setSessionMode(sessionId: String, modeId: String) async throws -> ACPSessionModeState?

    /// Changes a session configuration option via `session/set_config_option`.
    func setSessionConfigOption(
        sessionId: String,
        configId: String,
        value: String
    ) async throws -> [ACPSessionConfigOption]

    /// Called when the client sends a `session/cancel` notification.
    func cancelPrompt(sessionId: String) async
}

public enum ACPAgentAdapterError: Error, LocalizedError, Sendable {
    case methodNotSupported(String)

    public var errorDescription: String? {
        switch self {
        case .methodNotSupported(let method):
            return "Adapter does not support \(method)"
        }
    }
}

public extension ACPAgentAdapter {
    var authMethods: [ACPAuthMethod] { [] }

    func loadSessionHistory(
        sessionId: String,
        eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
    ) async throws {}

    func onSessionClosed(sessionId: String) async throws {}

    func onSessionDeleted(sessionId: String) async throws {}

    func supplementSessionList(
        cursor: String?,
        cwd: String?,
        knownSessions: [ACPSessionInfo]
    ) async throws -> (sessions: [ACPSessionInfo], nextCursor: String?) {
        (knownSessions, nil)
    }

    func authenticate(methodId: String) async throws {}

    func logout() async throws {}

    func sessionSetup(
        sessionId: String,
        cwd: String,
        mcpServers: [ACPMcpServer]
    ) async throws -> (configOptions: [ACPSessionConfigOption]?, mode: ACPSessionModeState?) {
        (nil, nil)
    }

    func setSessionMode(sessionId: String, modeId: String) async throws -> ACPSessionModeState? {
        throw ACPAgentAdapterError.methodNotSupported("session/set_mode")
    }

    func setSessionConfigOption(
        sessionId: String,
        configId: String,
        value: String
    ) async throws -> [ACPSessionConfigOption] {
        throw ACPAgentAdapterError.methodNotSupported("session/set_config_option")
    }

    func cancelPrompt(sessionId: String) async {}
}

/// Simple echo adapter for tests and examples.
public struct EchoACPAgentAdapter: ACPAgentAdapter {
    public let agentInfo: ACPImplementation
    public let agentCapabilities: ACPAgentCapabilities
    private let responseText: String

    public init(
        name: String = "echo-acp-agent",
        version: String = "1.0.0",
        responseText: String = "Echo response"
    ) {
        self.agentInfo = ACPImplementation(name: name, title: "Echo ACP Agent", version: version)
        self.agentCapabilities = ACPAgentCapabilities()
        self.responseText = responseText
    }

    public func handlePrompt(
        sessionId: String,
        prompt: [ACPContentBlock],
        eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
    ) async throws -> ACPStopReason {
        let userText = prompt.compactMap { block -> String? in
            if case .text(let text) = block { return text }
            return nil
        }.joined(separator: " ")

        try await eventSink(.agentMessageChunk(
            messageId: UUID().uuidString,
            content: .text("Echo: \(userText.isEmpty ? responseText : userText)")
        ))
        return .endTurn
    }
}
