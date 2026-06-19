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
    var activePromptTasks: [String: Task<ACPStopReason, Error>] = [:]
    var cancelledSessionIds: Set<String> = []

    struct ACPSessionState: Sendable {
        let sessionId: String
        var cwd: String
        var mcpServers: [ACPMcpServer]
        var additionalDirectories: [String]
        var title: String?
        var updatedAt: String?
        var isActive: Bool
        var mode: ACPSessionModeState?
        var configOptions: [ACPSessionConfigOption]?

        init(
            sessionId: String,
            cwd: String,
            mcpServers: [ACPMcpServer],
            additionalDirectories: [String] = [],
            title: String? = nil,
            updatedAt: String? = nil,
            isActive: Bool = true,
            mode: ACPSessionModeState? = nil,
            configOptions: [ACPSessionConfigOption]? = nil
        ) {
            self.sessionId = sessionId
            self.cwd = cwd
            self.mcpServers = mcpServers
            self.additionalDirectories = additionalDirectories
            self.title = title
            self.updatedAt = updatedAt
            self.isActive = isActive
            self.mode = mode
            self.configOptions = configOptions
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
    private let transport: any JSONRPCTransport
    private let connection: JSONRPCConnection
    private let stateBox: ACPAgentState
    private let logger: Logging.Logger
    public private(set) var state: State = .idle

    public init(adapter: any ACPAgentAdapter, transport: any JSONRPCTransport, logger: Logging.Logger? = nil) {
        self.adapter = adapter
        self.transport = transport
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
        let tasks = stateBox.withLock { Array(stateBox.activePromptTasks.values) }
        for task in tasks {
            task.cancel()
        }
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
        let transport = self.transport

        await connection.registerMethod("initialize") { paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPInitializeRequest.self, from: paramsData)
            stateBox.withLock {
                stateBox.negotiatedProtocolVersion = min(request.protocolVersion, 1)
                stateBox.isAuthenticated = adapter.authMethods.isEmpty
                stateBox.lastClientCapabilities = request.clientCapabilities
            }
            let remoteConnectionId: String?
            if let remote = transport as? any ACPRemoteTransportContext {
                remoteConnectionId = await remote.connectionId()
            } else {
                remoteConnectionId = nil
            }
            let response = ACPInitializeResponse(
                protocolVersion: stateBox.negotiatedProtocolVersion,
                agentCapabilities: adapter.agentCapabilities,
                agentInfo: adapter.agentInfo,
                authMethods: adapter.authMethods,
                connectionId: remoteConnectionId
            )
            await connection.markInitialized()
            return try JSONEncoder().encode(response)
        }

        await connection.registerMethod("authenticate") { paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPAuthenticateRequest.self, from: paramsData)
            let validMethod = adapter.authMethods.contains { $0.id == request.methodId }
            guard validMethod else {
                throw JSONRPCConnectionError.remoteError(
                    JSONRPCError(
                        code: JSONRPCErrorCode.invalidParams.rawValue,
                        message: "Unknown auth method: \(request.methodId)"
                    )
                )
            }
            try await adapter.authenticate(methodId: request.methodId)
            stateBox.withLock { stateBox.isAuthenticated = true }
            return try JSONEncoder().encode(ACPAuthenticateResponse())
        }

        if adapter.agentCapabilities.auth.supportsLogout {
            await connection.registerMethod("logout") { _ in
                try await adapter.logout()
                stateBox.withLock { stateBox.isAuthenticated = false }
                return try JSONEncoder().encode(ACPLogoutResponse())
            }
        }

        await connection.registerMethod("session/new") { paramsData in
            try Self.requireAuthenticated(stateBox: stateBox, adapter: adapter)
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPNewSessionRequest.self, from: paramsData)
            let sessionId = UUID().uuidString
            let setup = try await adapter.sessionSetup(
                sessionId: sessionId,
                cwd: request.cwd,
                mcpServers: request.mcpServers
            )
            stateBox.withLock {
                stateBox.sessions[sessionId] = ACPAgentState.ACPSessionState(
                    sessionId: sessionId,
                    cwd: request.cwd,
                    mcpServers: request.mcpServers,
                    additionalDirectories: request.additionalRoots ?? [],
                    mode: setup.mode,
                    configOptions: setup.configOptions
                )
            }
            Self.scheduleAvailableCommandsPublication(
                sessionId: sessionId,
                adapter: adapter,
                connection: connection
            )
            return try JSONEncoder().encode(
                ACPNewSessionResponse(
                    sessionId: sessionId,
                    configOptions: setup.configOptions,
                    mode: setup.mode
                )
            )
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
                    try Self.throwSessionNotFound(request.sessionId)
                }

                let sessionId = request.sessionId
                let setup = try await adapter.sessionSetup(
                    sessionId: sessionId,
                    cwd: request.cwd,
                    mcpServers: request.mcpServers
                )
                stateBox.withLock {
                    guard var session = stateBox.sessions[sessionId] else { return }
                    session.cwd = request.cwd
                    session.mcpServers = request.mcpServers
                    session.additionalDirectories = request.additionalDirectories ?? []
                    session.isActive = true
                    if let mode = setup.mode { session.mode = mode }
                    if let configOptions = setup.configOptions { session.configOptions = configOptions }
                    stateBox.sessions[sessionId] = session
                }

                try await adapter.loadSessionHistory(sessionId: sessionId) { update in
                    try await connection.notify(
                        "session/update",
                        params: ACPSessionUpdateNotification(sessionId: sessionId, update: update)
                    )
                }

                Self.scheduleAvailableCommandsPublication(
                    sessionId: sessionId,
                    adapter: adapter,
                    connection: connection
                )

                let sessionState = stateBox.withLock { stateBox.sessions[sessionId] }
                return try JSONEncoder().encode(
                    ACPLoadSessionResponse(
                        configOptions: sessionState?.configOptions,
                        mode: sessionState?.mode
                    )
                )
            }
        }

        if adapter.agentCapabilities.sessionCapabilities.supportsResume {
            await connection.registerMethod("session/resume") { paramsData in
                try Self.requireAuthenticated(stateBox: stateBox, adapter: adapter)
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPResumeSessionRequest.self, from: paramsData)

                let exists = stateBox.withLock { stateBox.sessions[request.sessionId] != nil }
                guard exists else {
                    try Self.throwSessionNotFound(request.sessionId)
                }

                let setup = try await adapter.sessionSetup(
                    sessionId: request.sessionId,
                    cwd: request.cwd,
                    mcpServers: request.mcpServers ?? []
                )
                stateBox.withLock {
                    guard var session = stateBox.sessions[request.sessionId] else { return }
                    session.cwd = request.cwd
                    if let mcpServers = request.mcpServers {
                        session.mcpServers = mcpServers
                    }
                    session.additionalDirectories = request.additionalDirectories ?? []
                    session.isActive = true
                    if let mode = setup.mode { session.mode = mode }
                    if let configOptions = setup.configOptions { session.configOptions = configOptions }
                    stateBox.sessions[request.sessionId] = session
                }

                Self.scheduleAvailableCommandsPublication(
                    sessionId: request.sessionId,
                    adapter: adapter,
                    connection: connection
                )

                let sessionState = stateBox.withLock { stateBox.sessions[request.sessionId] }
                return try JSONEncoder().encode(
                    ACPResumeSessionResponse(
                        configOptions: sessionState?.configOptions,
                        mode: sessionState?.mode
                    )
                )
            }
        }

        if adapter.agentCapabilities.sessionCapabilities.supportsClose {
            await connection.registerMethod("session/close") { paramsData in
                try Self.requireAuthenticated(stateBox: stateBox, adapter: adapter)
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPCloseSessionRequest.self, from: paramsData)

                let exists = stateBox.withLock { stateBox.sessions[request.sessionId] != nil }
                guard exists else {
                    try Self.throwSessionNotFound(request.sessionId)
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
                    try Self.throwSessionNotFound(request.sessionId)
                }

                try await adapter.onSessionDeleted(sessionId: request.sessionId)
                return try JSONEncoder().encode(ACPDeleteSessionResponse())
            }
        }

        if adapter.agentCapabilities.sessionCapabilities.supportsSetMode {
            await connection.registerMethod("session/set_mode") { paramsData in
                try Self.requireAuthenticated(stateBox: stateBox, adapter: adapter)
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPSetSessionModeRequest.self, from: paramsData)

                let session = stateBox.withLock { stateBox.sessions[request.sessionId] }
                guard let session, session.isActive else {
                    try Self.throwSessionNotFound(request.sessionId)
                }

                if let availableModes = session.mode?.availableModes, !availableModes.isEmpty {
                    guard availableModes.contains(where: { $0.id == request.modeId }) else {
                        throw JSONRPCConnectionError.remoteError(
                            JSONRPCError(
                                code: JSONRPCErrorCode.invalidParams.rawValue,
                                message: "Unknown mode: \(request.modeId)"
                            )
                        )
                    }
                }

                let updatedMode = try await adapter.setSessionMode(
                    sessionId: request.sessionId,
                    modeId: request.modeId
                )
                stateBox.withLock {
                    guard var stored = stateBox.sessions[request.sessionId] else { return }
                    if let updatedMode {
                        stored.mode = updatedMode
                    } else if var mode = stored.mode {
                        mode.currentModeId = request.modeId
                        stored.mode = mode
                    } else {
                        stored.mode = ACPSessionModeState(currentModeId: request.modeId)
                    }
                    stateBox.sessions[request.sessionId] = stored
                }

                return try JSONEncoder().encode(ACPSetSessionModeResponse())
            }
        }

        if adapter.agentCapabilities.sessionCapabilities.supportsSetConfigOption {
            await connection.registerMethod("session/set_config_option") { paramsData in
                try Self.requireAuthenticated(stateBox: stateBox, adapter: adapter)
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPSetSessionConfigOptionRequest.self, from: paramsData)

                let session = stateBox.withLock { stateBox.sessions[request.sessionId] }
                guard let session, session.isActive else {
                    try Self.throwSessionNotFound(request.sessionId)
                }

                let configOptions = try await adapter.setSessionConfigOption(
                    sessionId: request.sessionId,
                    configId: request.configId,
                    value: request.value
                )
                stateBox.withLock {
                    guard var stored = stateBox.sessions[request.sessionId] else { return }
                    stored.configOptions = configOptions
                    stateBox.sessions[request.sessionId] = stored
                }

                return try JSONEncoder().encode(
                    ACPSetSessionConfigOptionResponse(configOptions: configOptions)
                )
            }
        }

        await connection.registerMethod("session/prompt") { paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPPromptRequest.self, from: paramsData)
            let session = stateBox.withLock { stateBox.sessions[request.sessionId] }
            guard let session, session.isActive else {
                try Self.throwSessionNotFound(request.sessionId)
            }

            let sessionId = request.sessionId
            let caps = stateBox.withLock { stateBox.lastClientCapabilities }
            let client = ACPAgentClient(
                connection: connection,
                capabilities: caps ?? ACPClientCapabilities()
            )
            let promptTask = Task {
                try await adapter.handlePrompt(sessionId: sessionId, prompt: request.prompt, client: client) { update in
                    try await connection.notify(
                        "session/update",
                        params: ACPSessionUpdateNotification(sessionId: sessionId, update: update)
                    )
                }
            }
            stateBox.withLock {
                stateBox.cancelledSessionIds.remove(sessionId)
                stateBox.activePromptTasks[sessionId] = promptTask
            }
            defer {
                _ = stateBox.withLock {
                    stateBox.activePromptTasks.removeValue(forKey: sessionId)
                    stateBox.cancelledSessionIds.remove(sessionId)
                }
            }

            let stopReason = try await Self.runCancellablePrompt(
                sessionId: sessionId,
                stateBox: stateBox,
                promptTask: promptTask
            )
            return try JSONEncoder().encode(ACPPromptResponse(stopReason: stopReason))
        }

        await connection.registerNotification("session/cancel") { paramsData in
            let decoder = JSONDecoder()
            guard let params = try? decoder.decode(ACPSessionCancelParams.self, from: paramsData) else {
                return
            }
            _ = stateBox.withLock { stateBox.cancelledSessionIds.insert(params.sessionId) }
            let task = stateBox.withLock { stateBox.activePromptTasks[params.sessionId] }
            task?.cancel()
            await adapter.cancelPrompt(sessionId: params.sessionId)
        }

        await connection.setExtensionMethodHandler { method, paramsData in
            let params = try ACPExtensionSupport.decodeParams(paramsData)
            let result = try await adapter.extMethod(method: method, params: params)
            return try ACPExtensionSupport.encodeResult(result)
        }
        await connection.setExtensionNotificationHandler { method, paramsData in
            let params = (try? ACPExtensionSupport.decodeParams(paramsData)) ?? .object([:])
            await adapter.extNotification(method: method, params: params)
        }
    }

    private static func runCancellablePrompt(
        sessionId: String,
        stateBox: ACPAgentState,
        promptTask: Task<ACPStopReason, Error>
    ) async throws -> ACPStopReason {
        try await withThrowingTaskGroup(of: ACPStopReason.self) { group in
            group.addTask {
                do {
                    return try await promptTask.value
                } catch is CancellationError {
                    return .cancelled
                }
            }
            group.addTask {
                while true {
                    if stateBox.withLock({ stateBox.cancelledSessionIds.contains(sessionId) }) {
                        promptTask.cancel()
                        return .cancelled
                    }
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
            }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }

    private static func publishAvailableCommands(
        sessionId: String,
        adapter: any ACPAgentAdapter,
        connection: JSONRPCConnection
    ) async throws {
        let commands = try await adapter.availableCommands(sessionId: sessionId)
        guard !commands.isEmpty else { return }
        try await connection.notify(
            "session/update",
            params: ACPSessionUpdateNotification(
                sessionId: sessionId,
                update: .availableCommandsUpdate(commands: commands)
            )
        )
    }

    private static func scheduleAvailableCommandsPublication(
        sessionId: String,
        adapter: any ACPAgentAdapter,
        connection: JSONRPCConnection
    ) {
        Task {
            try? await publishAvailableCommands(
                sessionId: sessionId,
                adapter: adapter,
                connection: connection
            )
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

    private static func throwSessionNotFound(_ sessionId: String) throws -> Never {
        throw JSONRPCConnectionError.remoteError(
            JSONRPCError(code: ACPErrorCode.sessionNotFound.rawValue, message: "Session not found: \(sessionId)")
        )
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
