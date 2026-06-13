//
//  ACPAgentAdapter.swift
//  SwiftAgentKitACP
//

import Foundation

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
