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
    public private(set) var connectionId: String?
    public private(set) var availableCommands: [ACPAvailableCommand] = []
    public private(set) var toolCallTimeout: TimeInterval?

    private let transport: any JSONRPCTransport
    private let connection: JSONRPCConnection
    private let delegateBox: ACPClientDelegateBox
    private let clientInfo: ACPImplementation
    private let clientCapabilities: ACPClientCapabilities
    private let logger: Logger
    #if os(macOS) || os(Linux) || os(Windows)
    private var bootProcess: Process?
    #endif
    private var sessionUpdateContinuation: AsyncStream<ACPSessionUpdate>.Continuation?
    private var sessionUpdateHandlerRegistered = false
    private var pendingAvailableCommandsBySessionId: [String: [ACPAvailableCommand]] = [:]
    private let pendingPermissions = PendingPermissionTracker()
    private var name: String
    private let staticMcpBootServers: [ACPMcpServer]
    private let sessionMcpServersProvider: ACPSessionMcpServersProvider
    private var registeredExtensionMethods: [String: @Sendable (JSON) async throws -> JSON] = [:]
    private var registeredExtensionNotifications: [String: @Sendable (JSON) async -> Void] = [:]

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
        self.transport = transport
        self.connection = JSONRPCConnection(transport: transport, logger: logger)
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .acp("ACPClient"),
            metadata: SwiftAgentKitLogging.metadata(("name", .string(name)))
        )
    }

    #if os(macOS) || os(Linux) || os(Windows)
    /// Boot an ACP agent subprocess, initialize, and create a default session.
    ///
    /// Only available on platforms where ``SwiftAgentKit/SubprocessAvailability/isSupported`` is `true`
    /// (macOS, Linux, Windows). On platforms without the `Process` API (e.g. iOS, visionOS), use the
    /// remote connection helpers (``connectWebSocket(name:url:delegate:clientCapabilities:additionalHeaders:toolCallTimeout:staticMcpBootServers:sessionMcpServersProvider:logger:)``
    /// or ``connectStreamableHTTP(name:url:delegate:clientCapabilities:additionalHeaders:toolCallTimeout:staticMcpBootServers:sessionMcpServersProvider:logger:)``).
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
    #endif

    /// Connects to a remote ACP agent over WebSocket.
    public static func connectWebSocket(
        name: String,
        url: URL,
        delegate: any ACPClientDelegate = DefaultACPClientDelegate(),
        clientCapabilities: ACPClientCapabilities = ACPClient.defaultClientCapabilities(),
        additionalHeaders: [String: String] = [:],
        toolCallTimeout: TimeInterval? = nil,
        staticMcpBootServers: [ACPMcpServer] = [],
        sessionMcpServersProvider: ACPSessionMcpServersProvider? = nil,
        logger: Logger? = nil
    ) async throws -> ACPClient {
        let transport = ACPWebSocketClientTransport(
            endpointURL: url,
            additionalHeaders: additionalHeaders,
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
        try await client.connect()
        return client
    }

    /// Connects to a remote ACP agent over Streamable HTTP.
    public static func connectStreamableHTTP(
        name: String,
        url: URL,
        delegate: any ACPClientDelegate = DefaultACPClientDelegate(),
        clientCapabilities: ACPClientCapabilities = ACPClient.defaultClientCapabilities(),
        additionalHeaders: [String: String] = [:],
        toolCallTimeout: TimeInterval? = nil,
        staticMcpBootServers: [ACPMcpServer] = [],
        sessionMcpServersProvider: ACPSessionMcpServersProvider? = nil,
        logger: Logger? = nil
    ) async throws -> ACPClient {
        let transport = ACPStreamableHTTPClientTransport(
            endpointURL: url,
            additionalHeaders: additionalHeaders,
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
        try await client.connect()
        return client
    }

    #if os(macOS) || os(Linux) || os(Windows)
    func setBootProcess(_ process: Process) {
        bootProcess = process
    }
    #endif

    /// Replaces the client delegate used for agent → client RPCs (filesystem, permission, terminal).
    ///
    /// Takes effect immediately for subsequent inbound calls. Safe to call before or after ``connect()``.
    public func setDelegate(_ delegate: any ACPClientDelegate) {
        delegateBox.setDelegate(delegate)
    }

    /// Registers a handler for a specific `_`-prefixed extension method (takes precedence over delegate catch-all).
    public func registerExtensionMethod(
        _ method: String,
        handler: @escaping @Sendable (JSON) async throws -> JSON
    ) throws {
        try ACPExtensionSupport.validateExtensionMethod(method)
        registeredExtensionMethods[method] = handler
    }

    /// Registers a handler for a specific `_`-prefixed extension notification (takes precedence over delegate catch-all).
    public func registerExtensionNotification(
        _ method: String,
        handler: @escaping @Sendable (JSON) async -> Void
    ) throws {
        try ACPExtensionSupport.validateExtensionMethod(method)
        registeredExtensionNotifications[method] = handler
    }

    /// Sends a custom `_`-prefixed extension request to the agent.
    public func extMethod(method: String, params: JSON = .object([:])) async throws -> JSON {
        try ACPExtensionSupport.validateExtensionMethod(method)
        guard state != .disconnected else { throw ACPClientError.notInitialized }
        let paramsData = try JSONEncoder().encode(params)
        let resultData = try await connection.callRaw(method, params: paramsData)
        return try JSONDecoder().decode(JSON.self, from: resultData)
    }

    /// Sends a custom `_`-prefixed extension notification to the agent.
    public func extNotification(method: String, params: JSON = .object([:])) async throws {
        try ACPExtensionSupport.validateExtensionMethod(method)
        guard state != .disconnected else { throw ACPClientError.notInitialized }
        let paramsData = try JSONEncoder().encode(params)
        try await connection.notifyRaw(method, params: paramsData)
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
        connectionId = initResponse.connectionId
        await updateRemoteTransportContext(connectionId: initResponse.connectionId)

        if autoAuthenticate, let first = initResponse.authMethods.first {
            try await authenticate(methodId: first.id)
        }

        state = .initialized

        await ensureSessionUpdateHandlerRegistered()

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
        await updateRemoteTransportContext(sessionId: response.sessionId)
        applyPendingAvailableCommands(for: response.sessionId)
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
        self.sessionId = sessionId
        await updateRemoteTransportContext(sessionId: sessionId)
        applyPendingAvailableCommands(for: sessionId)
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
        await updateRemoteTransportContext(sessionId: sessionId)
        applyPendingAvailableCommands(for: sessionId)
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
        availableCommands = []
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
            availableCommands = []
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
        await pendingPermissions.cancelAll()
        try await connection.notify("session/cancel", params: ACPSessionCancelParams(sessionId: sessionId))
    }

    public func shutdown() async {
        sessionUpdateContinuation?.finish()
        sessionUpdateContinuation = nil
        await connection.disconnect()
        #if os(macOS) || os(Linux) || os(Windows)
        if let bootProcess {
            Shell.terminateProcess(bootProcess)
            self.bootProcess = nil
        }
        #endif
        state = .disconnected
        sessionId = nil
        connectionId = nil
        availableCommands = []
        sessionUpdateHandlerRegistered = false
        pendingAvailableCommandsBySessionId = [:]
        await updateRemoteTransportContext(connectionId: nil, sessionId: nil)
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

    private func updateRemoteTransportContext(connectionId: String? = nil, sessionId: String? = nil) async {
        guard let remote = transport as? any ACPRemoteTransportContext else { return }
        if connectionId != nil {
            await remote.setConnectionId(connectionId)
        }
        if sessionId != nil {
            await remote.setSessionId(sessionId)
        }
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

        await ensureSessionUpdateHandlerRegistered()

        return (updates, ())
    }

    private func ensureSessionUpdateHandlerRegistered() async {
        guard !sessionUpdateHandlerRegistered else { return }
        sessionUpdateHandlerRegistered = true
        await connection.registerNotification("session/update") { paramsData in
            let decoder = JSONDecoder()
            guard let notification = try? decoder.decode(ACPSessionUpdateNotification.self, from: paramsData) else { return }
            await self.dispatchSessionUpdate(notification.update, sessionId: notification.sessionId)
        }
    }

    private func applyPendingAvailableCommands(for sessionId: String) {
        if let pending = pendingAvailableCommandsBySessionId.removeValue(forKey: sessionId) {
            availableCommands = pending
        }
    }

    private func dispatchSessionUpdate(_ update: ACPSessionUpdate, sessionId: String) {
        if case .availableCommandsUpdate(let commands) = update {
            if self.sessionId == sessionId {
                availableCommands = commands
            } else {
                pendingAvailableCommandsBySessionId[sessionId] = commands
            }
        }
        guard self.sessionId == sessionId else { return }
        sessionUpdateContinuation?.yield(update)
    }

    private func dispatchSessionUpdate(_ update: ACPSessionUpdate) {
        guard let sessionId else { return }
        dispatchSessionUpdate(update, sessionId: sessionId)
    }

    private func finishSessionUpdateStream() {
        sessionUpdateContinuation?.finish()
        sessionUpdateContinuation = nil
    }

    private func registerClientHandlers() async {
        let delegateBox = self.delegateBox
        let pendingPermissions = self.pendingPermissions
        if clientCapabilities.fs.readTextFile {
            await connection.registerMethod("fs/read_text_file") { paramsData in
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPReadTextFileRequest.self, from: paramsData)
                let response = try await delegateBox.readTextFile(request)
                return try JSONEncoder().encode(response)
            }
        }
        if clientCapabilities.fs.writeTextFile {
            await connection.registerMethod("fs/write_text_file") { paramsData in
                let decoder = JSONDecoder()
                let request = try decoder.decode(ACPWriteTextFileRequest.self, from: paramsData)
                let response = try await delegateBox.writeTextFile(request)
                return try JSONEncoder().encode(response)
            }
        }
        await connection.registerMethod("session/request_permission") { paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPRequestPermissionRequest.self, from: paramsData)
            let waitID = UUID()

            let outcome: ACPPermissionOutcome
            do {
                outcome = try await withThrowingTaskGroup(of: ACPPermissionOutcome.self) { group in
                    group.addTask {
                        await pendingPermissions.waitForCancellation(id: waitID)
                    }
                    group.addTask {
                        let response = try await delegateBox.requestPermission(request)
                        return response.outcome
                    }
                    guard let first = try await group.next() else {
                        return ACPPermissionOutcome.cancelled
                    }
                    await pendingPermissions.abandonWait(id: waitID)
                    group.cancelAll()
                    return first
                }
            } catch {
                await pendingPermissions.abandonWait(id: waitID)
                throw error
            }
            await pendingPermissions.removeWait(id: waitID)
            return try JSONEncoder().encode(ACPRequestPermissionResponse(outcome: outcome))
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

        for (method, handler) in registeredExtensionMethods {
            await connection.registerExtensionMethod(method) { paramsData in
                let params = try ACPExtensionSupport.decodeParams(paramsData)
                let result = try await handler(params)
                return try ACPExtensionSupport.encodeResult(result)
            }
        }
        for (method, handler) in registeredExtensionNotifications {
            await connection.registerExtensionNotification(method) { paramsData in
                let params = (try? ACPExtensionSupport.decodeParams(paramsData)) ?? .object([:])
                await handler(params)
            }
        }
        await connection.setExtensionMethodHandler { method, paramsData in
            let params = try ACPExtensionSupport.decodeParams(paramsData)
            let result = try await delegateBox.extMethod(method: method, params: params)
            return try ACPExtensionSupport.encodeResult(result)
        }
        await connection.setExtensionNotificationHandler { method, paramsData in
            let params = (try? ACPExtensionSupport.decodeParams(paramsData)) ?? .object([:])
            await delegateBox.extNotification(method: method, params: params)
        }
    }

    private func emitUpdate(_ update: ACPSessionUpdate) {
        dispatchSessionUpdate(update)
    }

    private func finishPromptSession() {
        sessionUpdateContinuation?.finish()
        sessionUpdateContinuation = nil
        state = .sessionReady
    }
}

private actor PendingPermissionTracker {
    private var continuations: [UUID: CheckedContinuation<ACPPermissionOutcome, Never>] = [:]
    private var cancelled = false

    func waitForCancellation(id: UUID) async -> ACPPermissionOutcome {
        if cancelled {
            return .cancelled
        }
        return await withCheckedContinuation { continuation in
            if cancelled {
                continuation.resume(returning: .cancelled)
                return
            }
            continuations[id] = continuation
        }
    }

    func cancelAll() {
        cancelled = true
        for (_, continuation) in continuations {
            continuation.resume(returning: .cancelled)
        }
        continuations.removeAll()
    }

    func abandonWait(id: UUID) {
        if let continuation = continuations.removeValue(forKey: id) {
            continuation.resume(returning: .cancelled)
        }
    }

    func removeWait(id: UUID) {
        continuations.removeValue(forKey: id)
        if continuations.isEmpty {
            cancelled = false
        }
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

    func extMethod(method: String, params: JSON) async throws -> JSON {
        let delegate = currentDelegate()
        return try await delegate.extMethod(method: method, params: params)
    }

    func extNotification(method: String, params: JSON) async {
        let delegate = currentDelegate()
        await delegate.extNotification(method: method, params: params)
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
