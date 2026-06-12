//
//  ACPClient.swift
//  SwiftAgentKitACP
//

import Foundation
import Logging
import SwiftAgentKit
import EasyJSON

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

        public var errorDescription: String? {
            switch self {
            case .alreadyConnected: return "ACP client is already connected"
            case .notInitialized: return "ACP client is not initialized"
            case .noSession: return "No active ACP session"
            case .bootFailed(let reason): return "Failed to boot ACP agent: \(reason)"
            case .initializationFailed: return "ACP initialize handshake failed"
            }
        }
    }

    public private(set) var state: State = .disconnected
    public private(set) var agentInfo: ACPImplementation?
    public private(set) var agentCapabilities: ACPAgentCapabilities?
    public private(set) var sessionId: String?
    public private(set) var toolCallTimeout: TimeInterval?

    private let connection: JSONRPCConnection
    private let delegate: any ACPClientDelegate
    private let clientInfo: ACPImplementation
    private let clientCapabilities: ACPClientCapabilities
    private let logger: Logger
    private var bootProcess: Process?
    private var sessionUpdateContinuation: AsyncStream<ACPSessionUpdate>.Continuation?
    private var name: String

    public init(
        name: String,
        transport: any JSONRPCTransport,
        delegate: any ACPClientDelegate = DefaultACPClientDelegate(),
        clientInfo: ACPImplementation = ACPImplementation(name: "swiftagentkit-acp-client", version: "1.0.0"),
        clientCapabilities: ACPClientCapabilities = ACPClientCapabilities(
            fs: ACPFilesystemCapabilities(readTextFile: true, writeTextFile: true),
            terminal: false
        ),
        toolCallTimeout: TimeInterval? = nil,
        logger: Logger? = nil
    ) {
        self.name = name
        self.delegate = delegate
        self.clientInfo = clientInfo
        self.clientCapabilities = clientCapabilities
        self.toolCallTimeout = toolCallTimeout
        self.connection = JSONRPCConnection(transport: transport, logger: logger)
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .acp("ACPClient"),
            metadata: SwiftAgentKitLogging.metadata(("name", .string(name)))
        )
    }

    /// Boot an ACP agent subprocess and connect via stdio.
    public static func boot(
        name: String,
        command: String,
        arguments: [String],
        environment: [String: String] = [:],
        useShell: Bool = false,
        cwd: String? = nil,
        delegate: any ACPClientDelegate = DefaultACPClientDelegate(),
        toolCallTimeout: TimeInterval? = nil,
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
            toolCallTimeout: toolCallTimeout,
            logger: logger
        )
        await client.setBootProcess(launched.process)
        try await client.connect(cwd: cwd ?? FileManager.default.currentDirectoryPath)
        return client
    }

    func setBootProcess(_ process: Process) {
        bootProcess = process
    }

    public func connect(cwd: String) async throws {
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

        if !initResponse.authMethods.isEmpty, let first = initResponse.authMethods.first {
            let _: ACPAuthenticateResponse = try await connection.call(
                "authenticate",
                params: ACPAuthenticateRequest(methodId: first.id)
            )
        }

        let sessionResponse: ACPNewSessionResponse = try await connection.call(
            "session/new",
            params: ACPNewSessionRequest(cwd: cwd, mcpServers: [])
        )
        sessionId = sessionResponse.sessionId
        state = .sessionReady

        logger.info(
            "ACP client connected",
            metadata: SwiftAgentKitLogging.metadata(
                ("agent", .string(initResponse.agentInfo?.name ?? "unknown")),
                ("sessionId", .string(sessionResponse.sessionId))
            )
        )
    }

    public func prompt(_ text: String) async throws -> (ACPPromptResponse, AsyncStream<ACPSessionUpdate>) {
        guard state == .sessionReady || state == .promptInProgress else {
            throw ACPClientError.noSession
        }
        guard let sessionId else { throw ACPClientError.noSession }

        state = .promptInProgress
        var continuation: AsyncStream<ACPSessionUpdate>.Continuation!
        let updates = AsyncStream<ACPSessionUpdate> { continuation = $0 }
        sessionUpdateContinuation = continuation

        await connection.registerNotification("session/update") { paramsData in
            let decoder = JSONDecoder()
            guard let notification = try? decoder.decode(ACPSessionUpdateNotification.self, from: paramsData),
                  notification.sessionId == sessionId else { return }
            await self.emitUpdate(notification.update)
        }

        let request = ACPPromptRequest(
            sessionId: sessionId,
            prompt: [.text(text)]
        )

        let response: ACPPromptResponse = try await connection.call("session/prompt", params: request)
        sessionUpdateContinuation?.finish()
        sessionUpdateContinuation = nil
        state = .sessionReady
        return (response, updates)
    }

    public func promptCollectingText(_ text: String) async throws -> String {
        let (response, updates) = try await prompt(text)
        var collected = ""
        for await update in updates {
            if case .agentMessageChunk(_, let content) = update,
               case .text(let chunk) = content {
                collected += chunk
            }
        }
        _ = response
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
    }

    private func registerClientHandlers() async {
        await connection.registerMethod("fs/read_text_file") { [delegate] paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPReadTextFileRequest.self, from: paramsData)
            let response = try await delegate.readTextFile(request)
            return try JSONEncoder().encode(response)
        }
        await connection.registerMethod("fs/write_text_file") { [delegate] paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPWriteTextFileRequest.self, from: paramsData)
            let response = try await delegate.writeTextFile(request)
            return try JSONEncoder().encode(response)
        }
        await connection.registerMethod("session/request_permission") { [delegate] paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPRequestPermissionRequest.self, from: paramsData)
            let response = try await delegate.requestPermission(request)
            return try JSONEncoder().encode(response)
        }
        await connection.registerMethod("terminal/create") { [delegate] paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPCreateTerminalRequest.self, from: paramsData)
            let response = try await delegate.createTerminal(request)
            return try JSONEncoder().encode(response)
        }
        await connection.registerMethod("terminal/output") { [delegate] paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPTerminalOutputRequest.self, from: paramsData)
            let response = try await delegate.terminalOutput(request)
            return try JSONEncoder().encode(response)
        }
        await connection.registerMethod("terminal/wait_for_exit") { [delegate] paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPWaitForExitRequest.self, from: paramsData)
            let response = try await delegate.waitForTerminalExit(request)
            return try JSONEncoder().encode(response)
        }
        await connection.registerMethod("terminal/kill") { [delegate] paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPKillTerminalRequest.self, from: paramsData)
            let response = try await delegate.killTerminal(request)
            return try JSONEncoder().encode(response)
        }
        await connection.registerMethod("terminal/release") { [delegate] paramsData in
            let decoder = JSONDecoder()
            let request = try decoder.decode(ACPReleaseTerminalRequest.self, from: paramsData)
            let response = try await delegate.releaseTerminal(request)
            return try JSONEncoder().encode(response)
        }
    }

    private func emitUpdate(_ update: ACPSessionUpdate) {
        sessionUpdateContinuation?.yield(update)
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
