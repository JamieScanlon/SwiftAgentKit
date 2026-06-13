//
//  ACPClient.swift
//  SwiftAgentKitACP
//

import Foundation
import Logging
import SwiftAgentKit
import EasyJSON

/// Supplies MCP server descriptors for session lifecycle requests when an ACP client connects.
public typealias ACPSessionMcpServersProvider = @Sendable (String) async -> [ACPMcpServer]

/// ACP Client role — connects to an external ACP agent subprocess.
public actor ACPClient {
    public enum State: Sendable {
        case disconnected
        case initialized
        case sessionReady
        case promptInProgress
    }

    public enum ACPClientError: Error, LocalizedError, Sendable {
        case alreadyConnected
        case notInitialized
        case noSession
        case bootFailed(String)
        case initializationFailed
        case capabilityNotSupported(String)
        case invalidAuthMethod(String)

        public var errorDescription: String? {
            switch self {
            case .alreadyConnected: return "ACP client is already connected"
            case .notInitialized: return "ACP client is not initialized"
            case .noSession: return "No active ACP session"
            case .bootFailed(let reason): return "Failed to boot ACP agent: \(reason)"
            case .initializationFailed: return "ACP initialize handshake failed"
            case .capabilityNotSupported(let method): return "Agent does not support \(method)"
            case .invalidAuthMethod(let methodId): return "Unknown auth method: \(methodId)"
            }
        }
    }

    public private(set) var state: State = .disconnected
    public private(set) var agentInfo: ACPImplementation?
    public private(set) var agentCapabilities: ACPAgentCapabilities?
    public private(set) var authMethods: [ACPAuthMethod] = []
    public private(set) var isAuthenticated: Bool = false
    public private(set) var sessionId: String?
    public private(set) var toolCallTimeout: TimeInterval?

    private let connection: JSONRPCConnection
    private let delegateBox: ACPClientDelegateBox
    private let clientInfo: ACPImplementation
    private let clientCapabilities: ACPClientCapabilities
    private let logger: Logger
    private var bootProcess: Process?
    private var sessionUpdateContinuation: AsyncStream<ACPSessionUpdate>.Continuation?
    private var name: String
    private let staticMcpBootServers: [ACPMcpServer]
    private let sessionMcpServersProvider: ACPSessionMcpServersProvider

    /// Default client capabilities advertised during `initialize`.
    public static func defaultClientCapabilities(advertiseTerminal: Bool = false) -> ACPClientCapabilities {
        ACPClientCapabilities(
            fs: ACPFilesystemCapabilities(readTextFile: true, writeTextFile: true),
            terminal: advertiseTerminal
        )
    }

    public init(
        name: String,
        transport: any JSONRPCTransport,
        delegate: any ACPClientDelegate = DefaultACPClientDelegate(),
        clientInfo: ACPImplementation = ACPImplementation(name: "swiftagentkit-acp-client", version: "1.0.0"),
        clientCapabilities: ACPClientCapabilities = ACPClient.defaultClientCapabilities(),
        toolCallTimeout: TimeInterval? = nil,
        staticMcpBootServers: [ACPMcpServer] = [],
        sessionMcpServersProvider: ACPSessionMcpServersProvider? = nil,
        logger: Logger? = nil
    ) {
        self.name = name
        self.delegateBox = ACPClientDelegateBox(delegate)
        self.clientInfo = clientInfo
        self.clientCapabilities = clientCapabilities
        self.toolCallTimeout = toolCallTimeout
        self.staticMcpBootServers = staticMcpBootServers
        self.sessionMcpServersProvider = sessionMcpServersProvider ?? { _ in [] }
        self.connection = JSONRPCConnection(transport: transport, logger: logger)
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .acp("ACPClient"),
            metadata: SwiftAgentKitLogging.metadata(("name", .string(name)))
        )
    }

    /// Boot an ACP agent subprocess, initialize, and create a default session.
    public static func boot(
        name: String,
        command: String,
        arguments: [String],
        environment: [String: String] = [:],
        useShell: Bool = false,
        cwd: String? = nil,
        delegate: any ACPClientDelegate = DefaultACPClientDelegate(),
        clientCapabilities: ACPClientCapabilities = ACPClient.defaultClientCapabilities(),
        toolCallTimeout: TimeInterval? = nil,
        staticMcpBootServers: [ACPMcpServer] = [],
        sessionMcpServersProvider: ACPSessionMcpServersProvider? = nil,
        logger: Logger? = nil
    ) async throws -> ACPClient {
        let launched = Shell.launchSubprocess(
            command: command,
            arguments: arguments,
            environment: environment,
            useShell: useShell
        )
        let transport = PipeStdioTransport(
            inPipe: launched.inPipe,
            outPipe: launched.outPipe,
            logger: logger
        )
        let client = ACPClient(
            name: name,
            transport: transport,
            delegate: delegate,
            clientCapabilities: clientCapabilities,
            toolCallTimeout: toolCallTimeout,
            staticMcpBootServers: staticMcpBootServers,
            sessionMcpServersProvider: sessionMcpServersProvider,
            logger: logger
        )
        await client.setBootProcess(launched.process)
        try await client.connect()
        _ = try await client.newSession(cwd: cwd ?? FileManager.default.currentDirectoryPath)
        return client
    }

    func setBootProcess(_ process: Process) {
        bootProcess = process
    }

    /// Replaces the client delegate used for agent → client RPCs (filesystem, permission, terminal).
    ///
    /// Takes effect immediately for subsequent inbound calls. Safe to call before or after ``connect()``.
    public func setDelegate(_ delegate: any ACPClientDelegate) {
        delegateBox.setDelegate(delegate)
    }

    /// Connects transport and completes the initialize handshake (and auth when required).
    public func connect(autoAuthenticate: Bool = true) async throws {
        guard state == .disconnected else { throw ACPClientError.alreadyConnected }
        await registerClientHandlers()
        try await connection.connect()

        let initResponse: ACPInitializeResponse = try await connection.call(
            "initialize",
            params: ACPInitializeRequest(
                protocolVersion: 1,
                clientCapabilities: clientCapabilities,
                clientInfo: clientInfo
            )
        )

        agentInfo = initResponse.agentInfo
        agentCapabilities = initResponse.agentCapabilities
        authMethods = initResponse.authMethods
        isAuthenticated = initResponse.authMethods.isEmpty

        if autoAuthenticate, let first = initResponse.authMethods.first {
            try await authenticate(methodId: first.id)
        }

        state = .initialized

        logger.info(
            "ACP client initialized",
            metadata: SwiftAgentKitLogging.metadata(
                ("agent", .string(initResponse.agentInfo?.name ?? "unknown"))
            )
        )
    }

    /// Authenticates with the agent using the given auth method id.
    public func authenticate(methodId: String) async throws {
        guard state == .disconnected || state == .initialized else {
            throw ACPClientError.notInitialized
        }
        guard !authMethods.isEmpty else { return }
        guard authMethods.contains(where: { $0.id == methodId }) else {
            throw ACPClientError.invalidAuthMethod(methodId)
        }

        let _: ACPAuthenticateResponse = try await connection.call(
            "authenticate",
            params: ACPAuthenticateRequest(methodId: methodId)
        )
        isAuthenticated = true
    }

    /// Terminates the authenticated session via `logout`.
    public func logout() async throws {
        try requireCapability(agentCapabilities?.auth.supportsLogout == true, method: "logout")
        try requireInitialized()
        let _: ACPLogoutResponse = try await connection.call("logout", params: ACPLogoutRequest())
        isAuthenticated = false
    }

    /// Creates a new session via `session/new`.
    public func newSession(cwd: String, additionalRoots: [String]? = nil) async throws -> ACPNewSessionResponse {
        try requireInitialized()
        let mcpServers = await resolvedMcpServers(for: cwd)
        let response: ACPNewSessionResponse = try await connection.call(
            "session/new",
            params: ACPNewSessionRequest(cwd: cwd, mcpServers: mcpServers, additionalRoots: additionalRoots)
        )
        sessionId = response.sessionId
        state = .sessionReady

        logger.info(
            "ACP session created",
            metadata: SwiftAgentKitLogging.metadata(("sessionId", .string(response.sessionId)))
        )
        return response
    }

    /// Loads an existing session and returns replayed history via `session/update` notifications.
    public func loadSession(
        sessionId: String,
        cwd: String,
        additionalDirectories: [String]? = nil
    ) async throws -> (response: ACPLoadSessionResponse, history: AsyncStream<ACPSessionUpdate>) {
        try requireCapability(agentCapabilities?.loadSession == true, method: "session/load")
        try requireInitialized()

        let mcpServers = await resolvedMcpServers(for: cwd)
        let (updates, _) = try await beginSessionUpdateStream(for: sessionId)
        let historyBox = HistoryCollector()
        let collectTask = Task {
            for await update in updates {
                historyBox.append(update)
            }
        }

        let request = ACPLoadSessionRequest(
            sessionId: sessionId,
            cwd: cwd,
            mcpServers: mcpServers,
            additionalDirectories: additionalDirectories
        )

        let response: ACPLoadSessionResponse
        do {
            response = try await connection.call("session/load", params: request)
        } catch {
            sessionUpdateContinuation?.finish()
            sessionUpdateContinuation = nil
            collectTask.cancel()
            throw error
        }

        sessionUpdateContinuation?.finish()
        sessionUpdateContinuation = nil
        await collectTask.value

        self.sessionId = sessionId
        state = .sessionReady

        let history = AsyncStream<ACPSessionUpdate> { continuation in
            for update in historyBox.snapshot {
                continuation.yield(update)
            }
            continuation.finish()
        }
        return (response, history)
    }

    /// Resumes an existing session without replaying conversation history.
    public func resumeSession(
        sessionId: String,
        cwd: String,
        additionalDirectories: [String]? = nil
    ) async throws -> ACPResumeSessionResponse {
        try requireCapability(agentCapabilities?.sessionCapabilities.supportsResume == true, method: "session/resume")
        try requireInitialized()

        let mcpServers = await resolvedMcpServers(for: cwd)
        let response: ACPResumeSessionResponse = try await connection.call(
            "session/resume",
            params: ACPResumeSessionRequest(
                sessionId: sessionId,
                cwd: cwd,
                mcpServers: mcpServers,
                additionalDirectories: additionalDirectories
            )
        )
        self.sessionId = sessionId
        state = .sessionReady
        return response
    }

    /// Lists sessions known to the agent.
    public func listSessions(cursor: String? = nil, cwd: String? = nil) async throws -> ACPListSessionsResponse {
        try requireCapability(agentCapabilities?.sessionCapabilities.supportsList == true, method: "session/list")
        try requireInitialized()
        return try await connection.call(
            "session/list",
            params: ACPListSessionsRequest(cursor: cursor, cwd: cwd)
        )
    }

    /// Closes the active session via `session/close`.
    public func closeSession() async throws -> ACPCloseSessionResponse {
        try requireCapability(agentCapabilities?.sessionCapabilities.supportsClose == true, method: "session/close")
        guard let sessionId else { throw ACPClientError.noSession }
        let response: ACPCloseSessionResponse = try await connection.call(
            "session/close",
            params: ACPCloseSessionRequest(sessionId: sessionId)
        )
        self.sessionId = nil
        state = .initialized
        return response
    }

    /// Deletes a session via `session/delete`.
    public func deleteSession(sessionId: String) async throws -> ACPDeleteSessionResponse {
        try requireCapability(agentCapabilities?.sessionCapabilities.supportsDelete == true, method: "session/delete")
        try requireInitialized()
        let response: ACPDeleteSessionResponse = try await connection.call(
            "session/delete",
            params: ACPDeleteSessionRequest(sessionId: sessionId)
        )
        if self.sessionId == sessionId {
            self.sessionId = nil
            state = .initialized
        }
        return response
    }

    /// Sets the active mode for a session via `session/set_mode`.
    public func setSessionMode(sessionId: String, modeId: String) async throws -> ACPSetSessionModeResponse {
        try requireCapability(agentCapabilities?.sessionCapabilities.supportsSetMode == true, method: "session/set_mode")
        try requireInitialized()
        return try await connection.call(
            "session/set_mode",
            params: ACPSetSessionModeRequest(sessionId: sessionId, modeId: modeId)
        )
    }

    /// Sets a session configuration option via `session/set_config_option`.
    public func setSessionConfigOption(
        sessionId: String,
        configId: String,
        value: String
    ) async throws -> ACPSetSessionConfigOptionResponse {
        try requireCapability(
            agentCapabilities?.sessionCapabilities.supportsSetConfigOption == true,
            method: "session/set_config_option"
        )
        try requireInitialized()
        return try await connection.call(
            "session/set_config_option",
            params: ACPSetSessionConfigOptionRequest(
                sessionId: sessionId,
                configId: configId,
                value: value
            )
        )
    }

    public func prompt(_ text: String) async throws -> (ACPPromptResponse, AsyncStream<ACPSessionUpdate>) {
        let (updates, responseTask) = try await promptStream(text)
        let response = try await responseTask.value
        return (response, updates)
    }

    /// Starts a prompt and returns the update stream immediately while `session/prompt` runs in the background.
    public func promptStream(_ text: String) async throws -> (
        updates: AsyncStream<ACPSessionUpdate>,
        response: Task<ACPPromptResponse, Error>
    ) {
        guard state == .sessionReady || state == .promptInProgress else {
            throw ACPClientError.noSession
        }
        guard let sessionId else { throw ACPClientError.noSession }

        state = .promptInProgress
        let (updates, _) = try await beginSessionUpdateStream(for: sessionId)

        let request = ACPPromptRequest(
            sessionId: sessionId,
            prompt: [.text(text)]
        )

        let responseTask = Task { [connection] in
            do {
                let response: ACPPromptResponse = try await connection.call("session/prompt", params: request)
                await self.finishPromptSession()
                return response
            } catch {
                await self.finishPromptSession()
                throw error
            }
        }

        return (updates, responseTask)
    }

    public func promptCollectingText(_ text: String) async throws -> String {
        let (updates, responseTask) = try await promptStream(text)
        var collected = ""
        for await update in updates {
            if case .agentMessageChunk(_, let content) = update,
               case .text(let chunk) = content {
                collected += chunk
            }
        }
        _ = try await responseTask.value
        return collected
    }

    public func cancelPrompt() async throws {
        guard let sessionId else { throw ACPClientError.noSession }
        try await connection.notify("session/cancel", params: ACPSessionCancelParams(sessionId: sessionId))
    }

    public func shutdown() async {
        sessionUpdateContinuation?.finish()
        sessionUpdateContinuation = nil
        await connection.disconnect()
        if let bootProcess {
            Shell.terminateProcess(bootProcess)
            self.bootProcess = nil
        }
        state = .disconnected
        sessionId = nil
        agentInfo = nil
        agentCapabilities = nil
        authMethods = []
        isAuthenticated = false
    }

    private func requireInitialized() throws {
        guard state == .initialized || state == .sessionReady || state == .promptInProgress else {
            throw ACPClientError.notInitialized
        }
    }

    private func requireCapability(_ supported: Bool, method: String) throws {
        guard supported else {
            throw ACPClientError.capabilityNotSupported(method)
        }
    }

    private func resolvedMcpServers(for cwd: String) async -> [ACPMcpServer] {
        let providedMcpServers = await sessionMcpServersProvider(cwd)
        var mcpServers = staticMcpBootServers
        mcpServers.append(contentsOf: providedMcpServers)
        return mcpServers
    }

    private func beginSessionUpdateStream(for sessionId: String) async throws -> (
        updates: AsyncStream<ACPSessionUpdate>,
        registration: Void
    ) {
        sessionUpdateContinuation?.finish()
        sessionUpdateContinuation = nil

        var continuation: AsyncStream<ACPSessionUpdate>.Continuation!
        let updates = AsyncStream<ACPSessionUpdate> { continuation = $0 }
        sessionUpdateContinuation = continuation

        await connection.registerNotification("session/update") { paramsData in
            let decoder = JSONDecoder()
            guard let notification = try? decoder.decode(ACPSessionUpdateNotification.self, from: paramsData),
                  notification.sessionId == sessionId else { return }
            await self.emitUpdate(notification.update)
        }

        return (updates, ())
    }

    private func finishSessionUpdateStream() {
        sessionUpdateContinuation?.finish()
        sessionUpdateContinuation = nil
    }

    private func registerClientHandlers() async {
        let delegateBox = self.delegateBox
        await connection.registerMethod("fs/read_text_file") { paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPReadTextFileRequest.self, from: paramsData)
            let response = try await delegateBox.readTextFile(request)
            return try JSONEncoder().encode(response)
        }
        await connection.registerMethod("fs/write_text_file") { paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPWriteTextFileRequest.self, from: paramsData)
            let response = try await delegateBox.writeTextFile(request)
            return try JSONEncoder().encode(response)
        }
        await connection.registerMethod("session/request_permission") { paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPRequestPermissionRequest.self, from: paramsData)
            let response = try await delegateBox.requestPermission(request)
            return try JSONEncoder().encode(response)
        }
        if clientCapabilities.terminal {
            await connection.registerMethod("terminal/create") { paramsData in
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPCreateTerminalRequest.self, from: paramsData)
                let response = try await delegateBox.createTerminal(request)
                return try JSONEncoder().encode(response)
            }
            await connection.registerMethod("terminal/output") { paramsData in
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPTerminalOutputRequest.self, from: paramsData)
                let response = try await delegateBox.terminalOutput(request)
                return try JSONEncoder().encode(response)
            }
            await connection.registerMethod("terminal/wait_for_exit") { paramsData in
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPWaitForExitRequest.self, from: paramsData)
                let response = try await delegateBox.waitForTerminalExit(request)
                return try JSONEncoder().encode(response)
            }
            await connection.registerMethod("terminal/kill") { paramsData in
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPKillTerminalRequest.self, from: paramsData)
                let response = try await delegateBox.killTerminal(request)
                return try JSONEncoder().encode(response)
            }
            await connection.registerMethod("terminal/release") { paramsData in
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPReleaseTerminalRequest.self, from: paramsData)
                let response = try await delegateBox.releaseTerminal(request)
                return try JSONEncoder().encode(response)
            }
        }
    }

    private func emitUpdate(_ update: ACPSessionUpdate) {
        sessionUpdateContinuation?.yield(update)
    }

    private func finishPromptSession() {
        sessionUpdateContinuation?.finish()
        sessionUpdateContinuation = nil
        state = .sessionReady
    }
}

private final class ACPClientDelegateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var delegate: any ACPClientDelegate

    init(_ delegate: any ACPClientDelegate) {
        self.delegate = delegate
    }

    func setDelegate(_ delegate: any ACPClientDelegate) {
        lock.lock()
        self.delegate = delegate
        lock.unlock()
    }

    func readTextFile(_ request: ACPReadTextFileRequest) async throws -> ACPReadTextFileResponse {
        let delegate = currentDelegate()
        return try await delegate.readTextFile(request)
    }

    func writeTextFile(_ request: ACPWriteTextFileRequest) async throws -> ACPWriteTextFileResponse {
        let delegate = currentDelegate()
        return try await delegate.writeTextFile(request)
    }

    func requestPermission(_ request: ACPRequestPermissionRequest) async throws -> ACPRequestPermissionResponse {
        let delegate = currentDelegate()
        return try await delegate.requestPermission(request)
    }

    func createTerminal(_ request: ACPCreateTerminalRequest) async throws -> ACPCreateTerminalResponse {
        let delegate = currentDelegate()
        return try await delegate.createTerminal(request)
    }

    func terminalOutput(_ request: ACPTerminalOutputRequest) async throws -> ACPTerminalOutputResponse {
        let delegate = currentDelegate()
        return try await delegate.terminalOutput(request)
    }

    func waitForTerminalExit(_ request: ACPWaitForExitRequest) async throws -> ACPWaitForExitResponse {
        let delegate = currentDelegate()
        return try await delegate.waitForTerminalExit(request)
    }

    func killTerminal(_ request: ACPKillTerminalRequest) async throws -> ACPKillTerminalResponse {
        let delegate = currentDelegate()
        return try await delegate.killTerminal(request)
    }

    func releaseTerminal(_ request: ACPReleaseTerminalRequest) async throws -> ACPReleaseTerminalResponse {
        let delegate = currentDelegate()
        return try await delegate.releaseTerminal(request)
    }

    private func currentDelegate() -> any ACPClientDelegate {
        lock.lock()
        defer { lock.unlock() }
        return delegate
    }
}

private final class HistoryCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [ACPSessionUpdate] = []

    func append(_ update: ACPSessionUpdate) {
        lock.lock()
        updates.append(update)
        lock.unlock()
    }

    var snapshot: [ACPSessionUpdate] {
        lock.lock()
        defer { lock.unlock() }
        return updates
    }
}

extension JSON {
    var acpEnvironment: [String: String] {
        guard case .object(let dict) = self else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in dict {
            if case .string(let str) = value {
                result[key] = str
            }
        }
        return result
    }
}
