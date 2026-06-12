//
//  ACPAgent.swift
//  SwiftAgentKitACP
//

import Foundation
import Logging
import SwiftAgentKit

/// Shared mutable state for ACP agent handlers (Sendable-safe via lock).
final class ACPAgentState: @unchecked Sendable {
    private let lock = NSLock()
    var sessions: [String: ACPSessionState] = [:]
    var isAuthenticated = false
    var negotiatedProtocolVersion: ACPProtocolVersion = 1

    struct ACPSessionState: Sendable {
        let sessionId: String
        let cwd: String
    }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

/// ACP Agent role — handles Client requests over stdio.
public actor ACPAgent {
    public enum State: Sendable {
        case idle
        case running
        case stopped
    }

    public enum ACPAgentError: Error, LocalizedError, Sendable {
        case alreadyRunning
        case notRunning
        case sessionNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .alreadyRunning: return "ACP agent is already running"
            case .notRunning: return "ACP agent is not running"
            case .sessionNotFound(let id): return "Session not found: \(id)"
            }
        }
    }

    private let adapter: any ACPAgentAdapter
    private let connection: JSONRPCConnection
    private let stateBox: ACPAgentState
    private let logger: Logging.Logger
    public private(set) var state: State = .idle

    public init(adapter: any ACPAgentAdapter, transport: any JSONRPCTransport, logger: Logging.Logger? = nil) {
        self.adapter = adapter
        self.stateBox = ACPAgentState()
        self.connection = JSONRPCConnection(transport: transport, logger: logger)
        self.logger = logger ?? SwiftAgentKitLogging.logger(for: .acp("ACPAgent"))
    }

    public func run() async throws {
        guard state == .idle else { throw ACPAgentError.alreadyRunning }
        await registerHandlers()
        try await connection.connect()
        state = .running
        logger.info("ACP agent started")
    }

    public func stop() async {
        guard state == .running else { return }
        await connection.disconnect()
        state = .stopped
        logger.info("ACP agent stopped")
    }

    private func registerHandlers() async {
        let adapter = self.adapter
        let stateBox = self.stateBox
        let connection = self.connection

        await connection.registerMethod("initialize") { paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPInitializeRequest.self, from: paramsData)
            stateBox.withLock {
                stateBox.negotiatedProtocolVersion = min(request.protocolVersion, 1)
                stateBox.isAuthenticated = adapter.authMethods.isEmpty
            }
            let response = ACPInitializeResponse(
                protocolVersion: stateBox.negotiatedProtocolVersion,
                agentCapabilities: adapter.agentCapabilities,
                agentInfo: adapter.agentInfo,
                authMethods: adapter.authMethods
            )
            await connection.markInitialized()
            return try JSONEncoder().encode(response)
        }

        await connection.registerMethod("authenticate") { paramsData in
            let decoder = JSONDecoder()
            _ = try decoder.decode(ACPAuthenticateRequest.self, from: paramsData)
            stateBox.withLock { stateBox.isAuthenticated = true }
            return try JSONEncoder().encode(ACPAuthenticateResponse())
        }

        await connection.registerMethod("session/new") { paramsData in
            let authenticated = stateBox.withLock {
                stateBox.isAuthenticated || adapter.authMethods.isEmpty
            }
            guard authenticated else {
                throw JSONRPCConnectionError.remoteError(
                    JSONRPCError(code: ACPErrorCode.authRequired.rawValue, message: "Authentication required")
                )
            }
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPNewSessionRequest.self, from: paramsData)
            let sessionId = UUID().uuidString
            stateBox.withLock {
                stateBox.sessions[sessionId] = ACPAgentState.ACPSessionState(sessionId: sessionId, cwd: request.cwd)
            }
            return try JSONEncoder().encode(ACPNewSessionResponse(sessionId: sessionId))
        }

        await connection.registerMethod("session/prompt") { paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPPromptRequest.self, from: paramsData)
            let exists = stateBox.withLock { stateBox.sessions[request.sessionId] != nil }
            guard exists else {
                throw ACPAgentError.sessionNotFound(request.sessionId)
            }

            let sessionId = request.sessionId
            let stopReason = try await adapter.handlePrompt(sessionId: sessionId, prompt: request.prompt) { update in
                try await connection.notify(
                    "session/update",
                    params: ACPSessionUpdateNotification(sessionId: sessionId, update: update)
                )
            }
            return try JSONEncoder().encode(ACPPromptResponse(stopReason: stopReason))
        }

        await connection.registerNotification("session/cancel") { _ in
            // Cooperative cancellation handled by prompt task in full implementation
        }
    }
}
