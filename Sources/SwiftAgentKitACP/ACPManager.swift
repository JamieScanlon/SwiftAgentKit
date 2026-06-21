//
//  ACPManager.swift
//  SwiftAgentKitACP
//

import Foundation
import Logging
import SwiftAgentKit
import EasyJSON

/// Protocol for ACP clients that support prompt streaming; allows injection of test doubles.
public protocol ACPAgentStreamClient: Sendable {
    var agentInfo: ACPImplementation? { get async }
    var sessionId: String? { get async }
    func promptStream(_ instructions: String) async throws -> (
        updates: AsyncStream<ACPSessionUpdate>,
        response: Task<ACPPromptResponse, Error>
    )
    func shutdown() async
    var toolCallTimeout: TimeInterval? { get async }
}

public extension ACPAgentStreamClient {
    var sessionId: String? {
        get async { nil }
    }

    var toolCallTimeout: TimeInterval? {
        get async { nil }
    }
}

/// Protocol for ACP clients that support prompt lifecycle operations such as cancellation.
public protocol ACPPromptLifecycleClient: ACPAgentStreamClient {
    func cancelPrompt() async throws
}

/// Protocol for ACP clients that support session lifecycle operations.
public protocol ACPSessionLifecycleClient: ACPPromptLifecycleClient {
    var agentCapabilities: ACPAgentCapabilities? { get async }
    var authMethods: [ACPAuthMethod] { get async }
    var isAuthenticated: Bool { get async }
    func authenticate(methodId: String) async throws
    func logout() async throws
    func newSession(cwd: String, additionalRoots: [String]?) async throws -> ACPNewSessionResponse
    func listSessions(cursor: String?, cwd: String?) async throws -> ACPListSessionsResponse
    func loadSession(
        sessionId: String,
        cwd: String,
        additionalDirectories: [String]?
    ) async throws -> (response: ACPLoadSessionResponse, history: AsyncStream<ACPSessionUpdate>)
    func resumeSession(
        sessionId: String,
        cwd: String,
        additionalDirectories: [String]?
    ) async throws -> ACPResumeSessionResponse
    func closeSession() async throws -> ACPCloseSessionResponse
    func deleteSession(sessionId: String) async throws -> ACPDeleteSessionResponse
    func setSessionMode(sessionId: String, modeId: String) async throws -> ACPSetSessionModeResponse
    func setSessionConfigOption(
        sessionId: String,
        configId: String,
        value: String
    ) async throws -> ACPSetSessionConfigOptionResponse
}

public extension ACPSessionLifecycleClient {
    func newSession(cwd: String) async throws -> ACPNewSessionResponse {
        try await newSession(cwd: cwd, additionalRoots: nil)
    }

    func loadSession(sessionId: String, cwd: String) async throws -> (
        response: ACPLoadSessionResponse,
        history: AsyncStream<ACPSessionUpdate>
    ) {
        try await loadSession(sessionId: sessionId, cwd: cwd, additionalDirectories: nil)
    }

    func resumeSession(sessionId: String, cwd: String) async throws -> ACPResumeSessionResponse {
        try await resumeSession(sessionId: sessionId, cwd: cwd, additionalDirectories: nil)
    }
}

extension ACPClient: ACPSessionLifecycleClient {}

/// Manages tool calling via ACP agents.
public actor ACPManager {
    private let logger: Logger

    public enum State: Sendable {
        case notReady
        case initialized
    }

    public var state: State = .notReady
    public var toolCallsJson: [[String: Any]] = []
    public var toolCallsJsonString: String? {
        guard let data = try? JSONSerialization.data(withJSONObject: toolCallsJson) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    public private(set) var ingestionDiagnostics: [ToolIngestionDiagnostic] = []
    public private(set) var toolCallTimeout: TimeInterval? = nil
    public private(set) var clients: [ACPClient] = []

    private var streamClients: [any ACPAgentStreamClient] = []
    private var localProcesses: [String: Process] = [:]
    private var sessionMcpServersProvider: ACPSessionMcpServersProvider = { _ in [] }

    private struct InFlightRecord {
        var snapshot: ACPInFlightInvocation
        let client: any ACPAgentStreamClient
        var streamTask: Task<Void, Never>?
    }

    private var inFlightByInvocationID: [String: InFlightRecord] = [:]
    private var inFlightByToolCallID: [String: String] = [:]
    private var inFlightBySessionID: [String: String] = [:]

    public init(logger: Logger? = nil) {
        self.logger = logger ?? SwiftAgentKitLogging.logger(for: .acp("ACPManager"))
    }

    public func initialize(configFileURL: URL, sessionMcpServersProvider: ACPSessionMcpServersProvider? = nil) async throws {
        if let sessionMcpServersProvider {
            self.sessionMcpServersProvider = sessionMcpServersProvider
        }
        try await loadACPConfiguration(configFileURL: configFileURL)
    }

    public func initialize(
        clients: [any ACPAgentStreamClient],
        sessionMcpServersProvider: ACPSessionMcpServersProvider? = nil
    ) async throws {
        if let sessionMcpServersProvider {
            self.sessionMcpServersProvider = sessionMcpServersProvider
        }
        toolCallTimeout = nil
        streamClients = clients
        localProcesses = [:]
        await buildToolsJson()
        state = .initialized
    }

    /// Streams normalized incremental ACP delegate events for a tool call.
    ///
    /// - Parameter orchestratorDefaultTimeout: Used when neither per-agent nor root ACP config sets a tool-call timeout.
    /// - Throws: ``ACPManagerError/agentNotFound(_:)`` or ``ACPManagerError/invalidArguments`` before the stream starts.
    public func streamAgentCall(
        _ toolCall: ToolCall,
        invocationID: String,
        orchestratorDefaultTimeout: TimeInterval = 300
    ) async throws -> (handle: ACPDelegateInvocationHandle, events: AsyncStream<ACPDelegateStreamEvent>) {
        guard let client = await resolveClient(for: toolCall) else {
            throw ACPManagerError.agentNotFound(toolCall.name)
        }
        guard let instructions = validateInstructions(in: toolCall) else {
            throw ACPManagerError.invalidArguments
        }

        let handle = ACPDelegateInvocationHandle(
            invocationID: invocationID,
            toolCallID: toolCall.id,
            agentName: toolCall.name
        )
        let timeout = Self.resolvedToolCallTimeout(
            client: await client.toolCallTimeout,
            configDefault: toolCallTimeout,
            orchestrator: orchestratorDefaultTimeout
        )

        registerInFlight(
            invocationID: invocationID,
            toolCallID: toolCall.id,
            agentName: toolCall.name,
            client: client
        )

        let events = AsyncStream(ACPDelegateStreamEvent.self) { continuation in
            let streamTask = Task {
                final class TerminalState: @unchecked Sendable {
                    var terminalEmitted = false
                }
                let terminalState = TerminalState()
                let yield: @Sendable (ACPDelegateStreamEvent) -> Void = { event in
                    switch event {
                    case .completed, .failed:
                        terminalState.terminalEmitted = true
                    default:
                        break
                    }
                    continuation.yield(event)
                }
                defer {
                    Task { await self.deregisterInFlight(invocationID: invocationID) }
                }
                do {
                    try await withToolCallTimeout(timeout, toolName: toolCall.name) {
                        _ = try await self.processACPStream(
                            client: client,
                            toolCall: toolCall,
                            instructions: instructions,
                            agentName: toolCall.name,
                            invocationID: invocationID,
                            yield: yield
                        )
                    }
                } catch is CancellationError {
                    if !terminalState.terminalEmitted {
                        let snapshot = await self.inFlightByInvocationID[invocationID]?.snapshot
                        continuation.yield(.failed(
                            error: "Cancelled",
                            sessionID: snapshot?.sessionID
                        ))
                    }
                } catch {
                    if !terminalState.terminalEmitted {
                        let snapshot = await self.inFlightByInvocationID[invocationID]?.snapshot
                        continuation.yield(.failed(
                            error: String(describing: error),
                            sessionID: snapshot?.sessionID
                        ))
                    }
                }
                continuation.finish()
            }
            Task { await self.setStreamTask(invocationID: invocationID, task: streamTask) }
        }
        return (handle, events)
    }

    /// Cancels an in-flight ACP agent call by invocation ID, tool call ID, or session ID.
    ///
    /// Cancels the local stream task and, when the client supports it, calls `session/cancel` on the matching client.
    /// - Returns: `true` if a matching in-flight invocation was found and cancellation was attempted.
    public func cancelAgentCall(
        invocationID: String? = nil,
        toolCallID: String? = nil,
        sessionID: String? = nil
    ) async -> Bool {
        guard let resolvedInvocationID = resolveInFlightInvocationID(
            invocationID: invocationID,
            toolCallID: toolCallID,
            sessionID: sessionID
        ), let record = inFlightByInvocationID[resolvedInvocationID] else {
            return false
        }

        record.streamTask?.cancel()

        if let lifecycleClient = record.client as? any ACPPromptLifecycleClient {
            do {
                try await lifecycleClient.cancelPrompt()
            } catch {
                logger.debug(
                    "Remote ACP prompt cancel failed",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("sessionID", .string(record.snapshot.sessionID ?? "unknown")),
                        ("error", .string(String(describing: error)))
                    )
                )
            }
        } else {
            logger.debug(
                "Skipping remote ACP prompt cancel; client does not conform to ACPPromptLifecycleClient",
                metadata: SwiftAgentKitLogging.metadata(
                    ("agentName", .string(record.snapshot.agentName))
                )
            )
        }

        deregisterInFlight(invocationID: resolvedInvocationID)
        return true
    }

    public func agentCall(_ toolCall: ToolCall, orchestratorDefaultTimeout: TimeInterval = 300) async throws -> [LLMResponse]? {
        do {
            let (_, events) = try await streamAgentCall(
                toolCall,
                invocationID: toolCall.id ?? UUID().uuidString,
                orchestratorDefaultTimeout: orchestratorDefaultTimeout
            )
            return await collectResponses(from: events)
        } catch ACPManagerError.agentNotFound, ACPManagerError.invalidArguments {
            return nil
        }
    }

    // MARK: - Session lifecycle

    public func newSession(agentName: String, cwd: String, additionalRoots: [String]? = nil) async throws -> ACPNewSessionResponse {
        guard let client = await resolveClientByName(agentName) else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        guard let lifecycleClient = client as? any ACPSessionLifecycleClient else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        return try await lifecycleClient.newSession(cwd: cwd, additionalRoots: additionalRoots)
    }

    public func listSessions(
        agentName: String,
        cursor: String? = nil,
        cwd: String? = nil
    ) async throws -> ACPListSessionsResponse {
        guard let client = await resolveClientByName(agentName) else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        guard let lifecycleClient = client as? any ACPSessionLifecycleClient else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        return try await lifecycleClient.listSessions(cursor: cursor, cwd: cwd)
    }

    public func loadSession(
        agentName: String,
        sessionId: String,
        cwd: String,
        additionalDirectories: [String]? = nil
    ) async throws -> (response: ACPLoadSessionResponse, history: AsyncStream<ACPSessionUpdate>) {
        guard let client = await resolveClientByName(agentName) else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        guard let lifecycleClient = client as? any ACPSessionLifecycleClient else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        return try await lifecycleClient.loadSession(
            sessionId: sessionId,
            cwd: cwd,
            additionalDirectories: additionalDirectories
        )
    }

    public func resumeSession(
        agentName: String,
        sessionId: String,
        cwd: String,
        additionalDirectories: [String]? = nil
    ) async throws -> ACPResumeSessionResponse {
        guard let client = await resolveClientByName(agentName) else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        guard let lifecycleClient = client as? any ACPSessionLifecycleClient else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        return try await lifecycleClient.resumeSession(
            sessionId: sessionId,
            cwd: cwd,
            additionalDirectories: additionalDirectories
        )
    }

    public func closeSession(agentName: String) async throws -> ACPCloseSessionResponse {
        guard let client = await resolveClientByName(agentName) else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        guard let lifecycleClient = client as? any ACPSessionLifecycleClient else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        return try await lifecycleClient.closeSession()
    }

    public func deleteSession(agentName: String, sessionId: String) async throws -> ACPDeleteSessionResponse {
        guard let client = await resolveClientByName(agentName) else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        guard let lifecycleClient = client as? any ACPSessionLifecycleClient else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        return try await lifecycleClient.deleteSession(sessionId: sessionId)
    }

    public func authenticate(agentName: String, methodId: String) async throws {
        guard let client = await resolveClientByName(agentName) else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        guard let lifecycleClient = client as? any ACPSessionLifecycleClient else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        try await lifecycleClient.authenticate(methodId: methodId)
    }

    public func logout(agentName: String) async throws {
        guard let client = await resolveClientByName(agentName) else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        guard let lifecycleClient = client as? any ACPSessionLifecycleClient else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        try await lifecycleClient.logout()
    }

    public func setSessionMode(
        agentName: String,
        sessionId: String,
        modeId: String
    ) async throws -> ACPSetSessionModeResponse {
        guard let client = await resolveClientByName(agentName) else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        guard let lifecycleClient = client as? any ACPSessionLifecycleClient else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        return try await lifecycleClient.setSessionMode(sessionId: sessionId, modeId: modeId)
    }

    public func setSessionConfigOption(
        agentName: String,
        sessionId: String,
        configId: String,
        value: String
    ) async throws -> ACPSetSessionConfigOptionResponse {
        guard let client = await resolveClientByName(agentName) else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        guard let lifecycleClient = client as? any ACPSessionLifecycleClient else {
            throw ACPManagerError.agentNotFound(agentName)
        }
        return try await lifecycleClient.setSessionConfigOption(
            sessionId: sessionId,
            configId: configId,
            value: value
        )
    }

    public func availableTools() async -> [ToolDefinition] {
        var tools: [ToolDefinition] = []
        for client in streamClients {
            guard let info = await client.agentInfo else { continue }
            tools.append(ToolDefinition(
                name: info.name,
                description: info.title ?? "ACP agent \(info.name)",
                parameters: [
                    .init(name: "instructions", description: "Instructions for the ACP agent.", type: "string", required: true)
                ],
                type: .acpAgent
            ))
        }
        return tools
    }

    public func registeredToolDescriptors(
        targetProviderCapabilities: ToolSchemaTargetProviderCapabilities = .providerSafe
    ) async -> [RegisteredToolDescriptor] {
        let normalizer = ToolSchemaNormalizer()
        var descriptors: [RegisteredToolDescriptor] = []
        for client in streamClients {
            guard let info = await client.agentInfo else { continue }
            let definition = ToolDefinition(
                name: info.name,
                description: info.title ?? "ACP agent \(info.name)",
                parameters: [
                    .init(name: "instructions", description: "Instructions for the ACP agent.", type: "string", required: true)
                ],
                type: .acpAgent
            )
            let normalized = normalizer.normalize(
                rawSchema: definition.inferredSchemaJSON,
                source: .acp,
                targetProviderCapabilities: targetProviderCapabilities
            )
            descriptors.append(
                RegisteredToolDescriptor(
                    definition: definition,
                    source: .acp,
                    effectClass: .mutating,
                    parallelHint: .serialOnly,
                    policyTags: [],
                    normalizedSchema: normalized
                )
            )
        }
        return descriptors
    }

    public func shutdown() async {
        cancelAllInFlight()
        for client in streamClients {
            await client.shutdown()
        }
        for (_, process) in localProcesses {
            Shell.terminateProcess(process)
        }
        localProcesses.removeAll()
        streamClients.removeAll()
        clients.removeAll()
        state = .notReady
    }

    // MARK: - Private

    private func resolveClient(for toolCall: ToolCall) async -> (any ACPAgentStreamClient)? {
        await resolveClientByName(toolCall.name)
    }

    private func resolveClientByName(_ agentName: String) async -> (any ACPAgentStreamClient)? {
        for client in streamClients {
            guard let info = await client.agentInfo else { continue }
            if info.name == agentName {
                return client
            }
        }
        return nil
    }

    private func validateInstructions(in toolCall: ToolCall) -> String? {
        guard case .object(let argsDict) = toolCall.arguments,
              case .string(let instructions) = argsDict["instructions"] else {
            return nil
        }
        return instructions
    }

    private func processACPStream(
        client: any ACPAgentStreamClient,
        toolCall: ToolCall,
        instructions: String,
        agentName: String,
        invocationID: String,
        yield: (@Sendable (ACPDelegateStreamEvent) -> Void)?
    ) async throws -> [LLMResponse] {
        yield?(.connecting(agentName: agentName))

        let sessionID = await client.sessionId
        if let sessionID {
            updateInFlightSessionID(invocationID: invocationID, sessionID: sessionID)
        }

        let (updates, responseTask) = try await client.promptStream(instructions)

        var responseText = ""
        var terminalEmitted = false
        var returnResponses: [LLMResponse] = []

        func emitFailed(_ error: String) {
            guard !terminalEmitted else { return }
            terminalEmitted = true
            let snapshot = inFlightByInvocationID[invocationID]?.snapshot
            yield?(.failed(error: error, sessionID: snapshot?.sessionID ?? sessionID))
        }

        func emitCompleted(stopReason: ACPStopReason) {
            guard !terminalEmitted else { return }
            terminalEmitted = true
            let snapshot = inFlightByInvocationID[invocationID]?.snapshot
            let resolvedSessionID = snapshot?.sessionID ?? sessionID
            var content = responseText
            if content.isEmpty {
                content = "ACP agent completed with stop reason: \(stopReason.rawValue)"
            }
            let metadata = LLMMetadata(
                modelMetadata: .object([
                    "source": .string("acp_agent"),
                    "stopReason": .string(stopReason.rawValue)
                ])
            )
            yield?(.completed(content: content, stopReason: stopReason, sessionID: resolvedSessionID))
            returnResponses.append(LLMResponse.complete(content: content, metadata: metadata))
        }

        do {
            try await withTaskCancellationHandler {
                for await update in updates {
                    try Task.checkCancellation()

                    switch update {
                    case .userMessageChunk(let messageId, let content):
                        if case .text(let chunk) = content {
                            yield?(.userMessageChunk(messageId: messageId, text: chunk))
                        }
                    case .agentMessageChunk(_, let content):
                        if case .text(let chunk) = content {
                            responseText += chunk
                            yield?(.messageChunk(text: chunk))
                            returnResponses.append(LLMResponse.complete(content: chunk))
                        }
                    case .agentThoughtChunk(let messageId, let content):
                        if case .text(let chunk) = content {
                            yield?(.thoughtChunk(messageId: messageId, text: chunk))
                        }
                    case .availableCommandsUpdate(let commands):
                        yield?(.availableCommandsUpdate(commands: commands))
                    case .plan(let entries):
                        yield?(.plan(entries: entries))
                    case .toolCall(let update):
                        yield?(.toolCall(update))
                    case .toolCallUpdate(let update):
                        yield?(.toolCallUpdate(update))
                    case .usageUpdate(let used, let size, let cost):
                        yield?(.usageUpdate(used: used, size: size, cost: cost))
                    case .sessionInfoUpdate(let update):
                        yield?(.sessionInfoUpdate(update))
                    case .currentModeUpdate(let modeId):
                        yield?(.currentModeUpdate(modeId: modeId))
                    case .configOptionUpdate(let configOptions):
                        yield?(.configOptionUpdate(configOptions: configOptions))
                    }
                }
            } onCancel: {
                responseTask.cancel()
            }

            let response = try await responseTask.value

            if !terminalEmitted {
                emitCompleted(stopReason: response.stopReason)
            }
        } catch is CancellationError {
            if !terminalEmitted {
                emitFailed("Cancelled")
            }
        }

        return returnResponses
    }

    private func collectResponses(from events: AsyncStream<ACPDelegateStreamEvent>) async -> [LLMResponse] {
        var returnResponses: [LLMResponse] = []
        for await event in events {
            switch event {
            case .messageChunk(let text):
                returnResponses.append(LLMResponse.complete(content: text))
            case .completed(let content, let stopReason, _):
                let metadata = LLMMetadata(
                    modelMetadata: .object([
                        "source": .string("acp_agent"),
                        "stopReason": .string(stopReason.rawValue)
                    ])
                )
                returnResponses = [LLMResponse.complete(content: content, metadata: metadata)]
            default:
                break
            }
        }
        return returnResponses
    }

    private func registerInFlight(
        invocationID: String,
        toolCallID: String?,
        agentName: String,
        client: any ACPAgentStreamClient
    ) {
        let snapshot = ACPInFlightInvocation(
            invocationID: invocationID,
            toolCallID: toolCallID,
            agentName: agentName
        )
        inFlightByInvocationID[invocationID] = InFlightRecord(snapshot: snapshot, client: client)
        if let toolCallID {
            inFlightByToolCallID[toolCallID] = invocationID
        }
    }

    private func setStreamTask(invocationID: String, task: Task<Void, Never>) {
        guard var record = inFlightByInvocationID[invocationID] else { return }
        record.streamTask = task
        inFlightByInvocationID[invocationID] = record
    }

    private func updateInFlightSessionID(invocationID: String, sessionID: String) {
        guard var record = inFlightByInvocationID[invocationID] else { return }
        if let previousSessionID = record.snapshot.sessionID, previousSessionID != sessionID {
            inFlightBySessionID.removeValue(forKey: previousSessionID)
        }
        record.snapshot.sessionID = sessionID
        inFlightByInvocationID[invocationID] = record
        inFlightBySessionID[sessionID] = invocationID
    }

    private func resolveInFlightInvocationID(
        invocationID: String?,
        toolCallID: String?,
        sessionID: String?
    ) -> String? {
        if let invocationID, inFlightByInvocationID[invocationID] != nil {
            return invocationID
        }
        if let toolCallID, let resolved = inFlightByToolCallID[toolCallID] {
            return resolved
        }
        if let sessionID, let resolved = inFlightBySessionID[sessionID] {
            return resolved
        }
        return nil
    }

    private func deregisterInFlight(invocationID: String) {
        guard let record = inFlightByInvocationID.removeValue(forKey: invocationID) else { return }
        if let toolCallID = record.snapshot.toolCallID {
            if inFlightByToolCallID[toolCallID] == invocationID {
                inFlightByToolCallID.removeValue(forKey: toolCallID)
            }
        }
        if let sessionID = record.snapshot.sessionID {
            if inFlightBySessionID[sessionID] == invocationID {
                inFlightBySessionID.removeValue(forKey: sessionID)
            }
        }
    }

    private func cancelAllInFlight() {
        let invocationIDs = Array(inFlightByInvocationID.keys)
        for invocationID in invocationIDs {
            inFlightByInvocationID[invocationID]?.streamTask?.cancel()
        }
        inFlightByInvocationID.removeAll()
        inFlightByToolCallID.removeAll()
        inFlightBySessionID.removeAll()
    }

    private func loadACPConfiguration(configFileURL: URL) async throws {
        let config = try ACPConfigHelper.parseACPConfig(fileURL: configFileURL)
        toolCallTimeout = config.toolCallTimeout
        var bootedClients: [ACPClient] = []
        let mcpProvider = sessionMcpServersProvider

        for bootCall in config.agentBootCalls {
            var environment = config.globalEnvironment.acpEnvironment
            environment.merge(bootCall.environment.acpEnvironment, uniquingKeysWith: { _, new in new })
            let clientCapabilities = ACPClient.defaultClientCapabilities(
                advertiseTerminal: bootCall.advertiseTerminal
            )
            let timeout = bootCall.toolCallTimeout ?? config.toolCallTimeout
            do {
                let client: ACPClient
                if let urlString = bootCall.url, let url = URL(string: urlString) {
                    var headers: [String: String] = [:]
                    if let token = bootCall.auth?.bearerToken {
                        headers["Authorization"] = "Bearer \(token)"
                    }
                    switch bootCall.transport ?? .websocket {
                    case .websocket:
                        client = try await ACPClient.connectWebSocket(
                            name: bootCall.name,
                            url: url,
                            clientCapabilities: clientCapabilities,
                            additionalHeaders: headers,
                            toolCallTimeout: timeout,
                            staticMcpBootServers: config.mcpBootServers,
                            sessionMcpServersProvider: mcpProvider
                        )
                    case .streamableHTTP:
                        client = try await ACPClient.connectStreamableHTTP(
                            name: bootCall.name,
                            url: url,
                            clientCapabilities: clientCapabilities,
                            additionalHeaders: headers,
                            toolCallTimeout: timeout,
                            staticMcpBootServers: config.mcpBootServers,
                            sessionMcpServersProvider: mcpProvider
                        )
                    }
                    _ = try await client.newSession(cwd: FileManager.default.currentDirectoryPath)
                } else {
                    guard let command = bootCall.command else {
                        throw ACPClient.ACPClientError.bootFailed("Missing command or url for agent \(bootCall.name)")
                    }
                    client = try await ACPClient.boot(
                        name: bootCall.name,
                        command: command,
                        arguments: bootCall.arguments,
                        environment: environment,
                        useShell: bootCall.useShell,
                        clientCapabilities: clientCapabilities,
                        toolCallTimeout: timeout,
                        staticMcpBootServers: config.mcpBootServers,
                        sessionMcpServersProvider: mcpProvider
                    )
                }
                bootedClients.append(client)
            } catch {
                ingestionDiagnostics.append(ToolIngestionDiagnostic(
                    toolName: bootCall.name,
                    source: .acp,
                    message: "Failed to boot ACP agent: \(error)"
                ))
                logger.error(
                    "Failed to boot ACP agent",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("name", .string(bootCall.name)),
                        ("error", .string(String(describing: error)))
                    )
                )
            }
        }

        clients = bootedClients
        streamClients = bootedClients
        await buildToolsJson()
        state = .initialized
    }

    private func buildToolsJson() async {
        toolCallsJson = await availableTools().map { $0.toolCallJson() }
    }

    private nonisolated static func resolvedToolCallTimeout(
        client: TimeInterval?,
        configDefault: TimeInterval?,
        orchestrator: TimeInterval
    ) -> TimeInterval {
        if let v = client, v > 0 { return v }
        if let v = configDefault, v > 0 { return v }
        return orchestrator
    }
}
