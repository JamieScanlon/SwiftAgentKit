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
    var lastClientCapabilities: ACPClientCapabilities?

    struct ACPSessionState: Sendable {
        let sessionId: String
        var cwd: String
        var mcpServers: [ACPMcpServer]
        var additionalDirectories: [String]
        var title: String?
        var updatedAt: String?
        var isActive: Bool

        init(
            sessionId: String,
            cwd: String,
            mcpServers: [ACPMcpServer],
            additionalDirectories: [String] = [],
            title: String? = nil,
            updatedAt: String? = nil,
            isActive: Bool = true
        ) {
            self.sessionId = sessionId
            self.cwd = cwd
            self.mcpServers = mcpServers
            self.additionalDirectories = additionalDirectories
            self.title = title
            self.updatedAt = updatedAt
            self.isActive = isActive
        }

        func asSessionInfo() -> ACPSessionInfo {
            ACPSessionInfo(
                sessionId: sessionId,
                cwd: cwd,
                title: title,
                updatedAt: updatedAt,
                additionalDirectories: additionalDirectories.isEmpty ? nil : additionalDirectories
            )
        }
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

    private static let defaultPageSize = 50

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

    /// Returns MCP servers supplied at session creation for the given session, if it exists.
    public func mcpServers(forSessionId sessionId: String) async -> [ACPMcpServer]? {
        stateBox.withLock { stateBox.sessions[sessionId]?.mcpServers }
    }

    /// Returns client capabilities from the most recent `initialize` handshake.
    public func clientCapabilitiesFromInitialize() async -> ACPClientCapabilities? {
        stateBox.withLock { stateBox.lastClientCapabilities }
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
                stateBox.lastClientCapabilities = request.clientCapabilities
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
            try Self.requireAuthenticated(stateBox: stateBox, adapter: adapter)
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPNewSessionRequest.self, from: paramsData)
            let sessionId = UUID().uuidString
            stateBox.withLock {
                stateBox.sessions[sessionId] = ACPAgentState.ACPSessionState(
                    sessionId: sessionId,
                    cwd: request.cwd,
                    mcpServers: request.mcpServers,
                    additionalDirectories: request.additionalRoots ?? []
                )
            }
            return try JSONEncoder().encode(ACPNewSessionResponse(sessionId: sessionId))
        }

        if adapter.agentCapabilities.sessionCapabilities.supportsList {
            await connection.registerMethod("session/list") { paramsData in
                try Self.requireAuthenticated(stateBox: stateBox, adapter: adapter)
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPListSessionsRequest.self, from: paramsData)

                let knownSessions = stateBox.withLock {
                    stateBox.sessions.values
                        .filter { session in
                            guard let cwd = request.cwd else { return true }
                            return session.cwd == cwd
                        }
                        .sorted { $0.sessionId < $1.sessionId }
                        .map { $0.asSessionInfo() }
                }

                let supplemented = try await adapter.supplementSessionList(
                    cursor: request.cursor,
                    cwd: request.cwd,
                    knownSessions: knownSessions
                )

                let (page, nextCursor) = Self.paginateSessions(
                    supplemented.sessions,
                    cursor: request.cursor,
                    pageSize: Self.defaultPageSize
                )
                let resolvedNextCursor = supplemented.nextCursor ?? nextCursor

                return try JSONEncoder().encode(
                    ACPListSessionsResponse(sessions: page, nextCursor: resolvedNextCursor)
                )
            }
        }

        if adapter.agentCapabilities.loadSession {
            await connection.registerMethod("session/load") { paramsData in
                try Self.requireAuthenticated(stateBox: stateBox, adapter: adapter)
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPLoadSessionRequest.self, from: paramsData)

                let exists = stateBox.withLock { stateBox.sessions[request.sessionId] != nil }
                guard exists else {
                    throw ACPAgentError.sessionNotFound(request.sessionId)
                }

                let sessionId = request.sessionId
                stateBox.withLock {
                    guard var session = stateBox.sessions[sessionId] else { return }
                    session.cwd = request.cwd
                    session.mcpServers = request.mcpServers
                    session.additionalDirectories = request.additionalDirectories ?? []
                    session.isActive = true
                    stateBox.sessions[sessionId] = session
                }

                try await adapter.loadSessionHistory(sessionId: sessionId) { update in
                    try await connection.notify(
                        "session/update",
                        params: ACPSessionUpdateNotification(sessionId: sessionId, update: update)
                    )
                }

                return try JSONEncoder().encode(ACPLoadSessionResponse())
            }
        }

        if adapter.agentCapabilities.sessionCapabilities.supportsResume {
            await connection.registerMethod("session/resume") { paramsData in
                try Self.requireAuthenticated(stateBox: stateBox, adapter: adapter)
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPResumeSessionRequest.self, from: paramsData)

                let exists = stateBox.withLock { stateBox.sessions[request.sessionId] != nil }
                guard exists else {
                    throw ACPAgentError.sessionNotFound(request.sessionId)
                }

                stateBox.withLock {
                    guard var session = stateBox.sessions[request.sessionId] else { return }
                    session.cwd = request.cwd
                    if let mcpServers = request.mcpServers {
                        session.mcpServers = mcpServers
                    }
                    session.additionalDirectories = request.additionalDirectories ?? []
                    session.isActive = true
                    stateBox.sessions[request.sessionId] = session
                }

                return try JSONEncoder().encode(ACPResumeSessionResponse())
            }
        }

        if adapter.agentCapabilities.sessionCapabilities.supportsClose {
            await connection.registerMethod("session/close") { paramsData in
                try Self.requireAuthenticated(stateBox: stateBox, adapter: adapter)
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPCloseSessionRequest.self, from: paramsData)

                let exists = stateBox.withLock { stateBox.sessions[request.sessionId] != nil }
                guard exists else {
                    throw ACPAgentError.sessionNotFound(request.sessionId)
                }

                stateBox.withLock {
                    guard var session = stateBox.sessions[request.sessionId] else { return }
                    session.isActive = false
                    stateBox.sessions[request.sessionId] = session
                }

                try await adapter.onSessionClosed(sessionId: request.sessionId)
                return try JSONEncoder().encode(ACPCloseSessionResponse())
            }
        }

        if adapter.agentCapabilities.sessionCapabilities.supportsDelete {
            await connection.registerMethod("session/delete") { paramsData in
                try Self.requireAuthenticated(stateBox: stateBox, adapter: adapter)
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPDeleteSessionRequest.self, from: paramsData)

                let removed = stateBox.withLock { stateBox.sessions.removeValue(forKey: request.sessionId) != nil }
                guard removed else {
                    throw ACPAgentError.sessionNotFound(request.sessionId)
                }

                try await adapter.onSessionDeleted(sessionId: request.sessionId)
                return try JSONEncoder().encode(ACPDeleteSessionResponse())
            }
        }

        await connection.registerMethod("session/prompt") { paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPPromptRequest.self, from: paramsData)
            let session = stateBox.withLock { stateBox.sessions[request.sessionId] }
            guard let session, session.isActive else {
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

    private static func requireAuthenticated(stateBox: ACPAgentState, adapter: any ACPAgentAdapter) throws {
        let authenticated = stateBox.withLock {
            stateBox.isAuthenticated || adapter.authMethods.isEmpty
        }
        guard authenticated else {
            throw JSONRPCConnectionError.remoteError(
                JSONRPCError(code: ACPErrorCode.authRequired.rawValue, message: "Authentication required")
            )
        }
    }

    private static func paginateSessions(
        _ sessions: [ACPSessionInfo],
        cursor: String?,
        pageSize: Int
    ) -> (page: [ACPSessionInfo], nextCursor: String?) {
        let startIndex: Int
        if let cursor, let index = sessions.firstIndex(where: { $0.sessionId == cursor }) {
            startIndex = index + 1
        } else {
            startIndex = 0
        }

        guard startIndex < sessions.count else {
            return ([], nil)
        }

        let endIndex = min(startIndex + pageSize, sessions.count)
        let page = Array(sessions[startIndex..<endIndex])
        let nextCursor = endIndex < sessions.count ? sessions[endIndex - 1].sessionId : nil
        return (page, nextCursor)
    }
}
