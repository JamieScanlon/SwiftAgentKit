//
//  MCPManager.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 4/12/25.
//

import Foundation
import Logging
import MCP
import SwiftAgentKit
import EasyJSON

/// Manages tool calling via MCP
/// Loads a configuration of available MCP servers
/// Creates a MCPClient for every available server
/// Dispatches tool calls to clients
///
/// For remote servers that require OAuth, pass an ``MCPOAuthHandler``
/// so the manager can complete the manual OAuth flow (callback server, token exchange, storage)
/// instead of only logging and failing. Without a handler, ``OAuthManualFlowRequired`` is
/// surfaced and the server is added to the failed list.
public actor MCPManager {
    private let logger: Logger
    private let connectionTimeout: TimeInterval
    private let oauthHandler: MCPOAuthHandler?

    /// - Parameters:
    ///   - connectionTimeout: Timeout for MCP connections.
    ///   - logger: Optional logger; a default is created if nil.
    ///   - oauthHandler: Optional OAuth handler. When set, remote servers that require manual OAuth
    ///     are connected via the handler (callback server, token exchange, storage). When nil,
    ///     such servers fail with ``OAuthManualFlowRequired`` and are not opened in a browser.
    public init(
        connectionTimeout: TimeInterval = 30.0,
        logger: Logger? = nil,
        oauthHandler: MCPOAuthHandler? = nil
    ) {
        self.connectionTimeout = connectionTimeout
        self.oauthHandler = oauthHandler
        let resolvedLogger = logger ?? SwiftAgentKitLogging.logger(
            for: .mcp("MCPManager"),
            metadata: SwiftAgentKitLogging.metadata(
                ("connectionTimeout", .stringConvertible(connectionTimeout))
            )
        )
        self.logger = resolvedLogger
    }

    /// Convenience initializer without an OAuth handler (same as passing `oauthHandler: nil`).
    public init(connectionTimeout: TimeInterval = 30.0, logger: Logger? = nil) {
        self.init(connectionTimeout: connectionTimeout, logger: logger, oauthHandler: nil)
    }
    
    public enum State: Sendable {
        case notReady
        case initialized
    }
    
    public var state: State = .notReady
    public var toolCallsJsonString: String? {
        if let data = try? JSONSerialization.data(withJSONObject: toolCallsJson) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    public var toolCallsJson: [[String: Any]] = []
    public private(set) var ingestionDiagnostics: [ToolIngestionDiagnostic] = []
    public private(set) var clients: [MCPClient] = []

    /// Local stdio server boot descriptors from the last config-file initialization.
    public private(set) var serverBootCalls: [MCPConfig.ServerBootCall] = []

    /// Remote server configs from the last config-file initialization (used by ``reconnectClient(named:)``).
    public private(set) var remoteServers: [MCPConfig.RemoteServerConfig] = []

    /// Global environment from the last config-file initialization (re-applied on local reconnect).
    private var globalEnvironment: JSON = .object([:])

    /// When the manager was initialized from a config file that set ``MCPConfig/toolCallTimeout``, that value is stored here. Otherwise `nil` (call sites fall back to the orchestrator’s default tool-call timeout).
    public private(set) var toolCallTimeout: TimeInterval? = nil

    /// Subprocess handles for locally booted stdio MCP servers (used by ``shutdown()``).
    #if os(macOS) || os(Linux) || os(Windows)
    private var localServerProcesses: [String: Process] = [:]
    #endif
    
    /// Initialize the MCPManager with a config file URL
    public func initialize(configFileURL: URL) async throws {
        do {
            try await loadMCPConfiguration(configFileURL: configFileURL)
        } catch {
            logger.error(
                "Failed to initialize MCPManager",
                metadata: SwiftAgentKitLogging.metadata(("error", .string(String(describing: error))))
            )
        }
    }
    
    /// Initialize the MCPManager with an array of `MCPClient` objects (no local subprocess handles; ``shutdown()`` will not terminate external processes).
    ///
    /// ``reconnectClient(named:)`` requires config-backed initialization and returns `false` after this path.
    public func initialize(clients: [MCPClient]) async throws {
        toolCallTimeout = nil
        self.clients = clients
        serverBootCalls = []
        remoteServers = []
        globalEnvironment = .object([:])
        #if os(macOS) || os(Linux) || os(Windows)
        localServerProcesses = [:]
        #endif
        await buildToolsJson()
        state = .initialized
    }

    /// Returns local stdio MCP server boot descriptors from config-file initialization.
    public func localServerBootCalls() -> [MCPConfig.ServerBootCall] {
        serverBootCalls
    }

    /// Disconnects MCP clients and terminates locally spawned MCP server subprocesses. Call this from app shutdown (e.g. `NSApplication.willTerminate`); it does not run when the process is killed with `SIGKILL`.
    public func shutdown() async {
        #if os(macOS) || os(Linux) || os(Windows)
        let processes = localServerProcesses
        localServerProcesses.removeAll()
        #endif
        for client in clients {
            await client.shutdown()
        }
        clients.removeAll()
        #if os(macOS) || os(Linux) || os(Windows)
        for (_, process) in processes {
            Shell.terminateProcess(process)
        }
        #endif
        toolCallsJson = []
        toolCallTimeout = nil
        serverBootCalls = []
        remoteServers = []
        globalEnvironment = .object([:])
        state = .notReady
    }
    
    /// Dispatches a tool call to the first MCP client that handles it. Each client uses its own resolved timeout (per-server config, then root MCP config, then `orchestratorDefaultTimeout`).
    ///
    /// Primary unblock on timeout is ``MCPClient/callTool(_:arguments:timeoutSeconds:)`` which
    /// disconnects the SDK client so hung JSON-RPC waiters resume. The outer
    /// ``withToolCallTimeout`` is defense in depth (cooperative cancel).
    public func toolCall(_ toolCall: ToolCall, orchestratorDefaultTimeout: TimeInterval = 300) async throws -> [LLMResponse]? {
        for client in clients {
            let seconds = Self.resolvedToolCallTimeout(
                client: client.toolCallTimeout,
                configDefault: toolCallTimeout,
                orchestrator: orchestratorDefaultTimeout
            )
            let contents = try await withToolCallTimeout(seconds, toolName: toolCall.name) {
                try await client.callTool(
                    toolCall.name,
                    arguments: toolCall.argumentsToValue(),
                    timeoutSeconds: seconds
                )
            }
            if let contents = contents {
                var returnResponses: [LLMResponse] = []
                for content in contents {
                    switch content {
                    case .text(let text, _, _):
                        returnResponses.append(LLMResponse.complete(content: text))
                    default:
                        continue
                    }
                }
                return returnResponses
            }
        }
        return nil
    }

    /// Disconnects the named client, reconnects (local stdio re-boot or remote reconnect),
    /// re-runs tools/list, and rebuilds tool JSON. Does **not** retry a hung tool call.
    ///
    /// Requires config-file initialization (``initialize(configFileURL:)``) so boot/remote
    /// descriptors are available. After ``initialize(clients:)`` only, this returns `false`.
    ///
    /// - Returns: `true` on success; `false` if no client matched or reconnect failed (logged).
    public func reconnectClient(named name: String) async -> Bool {
        guard let index = await indexOfClient(named: name) else {
            logger.warning(
                "reconnectClient: no MCP client matched name",
                metadata: SwiftAgentKitLogging.metadata(("server", .string(name)))
            )
            return false
        }

        let existing = clients[index]
        await existing.shutdown()
        clients.remove(at: index)

        #if os(macOS) || os(Linux) || os(Windows)
        if let process = localServerProcesses.removeValue(forKey: name) {
            Shell.terminateProcess(process)
        }
        #endif

        if let bootCall = serverBootCalls.first(where: { $0.name == name }) {
            #if os(macOS) || os(Linux) || os(Windows)
            let result = await Self.bootAndConnectOneLocalServer(
                bootCall: bootCall,
                globalEnvironment: globalEnvironment,
                connectionTimeout: connectionTimeout,
                serverManager: MCPServerManager()
            )
            switch result {
            case .success(_, let client, let process):
                let insertAt = min(index, clients.count)
                clients.insert(client, at: insertAt)
                localServerProcesses[name] = process.value
                await buildToolsJson()
                logger.info(
                    "Reconnected local MCP client",
                    metadata: SwiftAgentKitLogging.metadata(("server", .string(name)))
                )
                return true
            case .failure(_, let kind, let elapsed):
                logger.error(
                    "reconnectClient failed for local MCP server",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("server", .string(name)),
                        ("failure", .string(kind)),
                        ("elapsedSeconds", .stringConvertible(elapsed))
                    )
                )
                return false
            }
            #else
            logger.warning(
                "reconnectClient: local stdio servers are not supported on this platform",
                metadata: SwiftAgentKitLogging.metadata(("server", .string(name)))
            )
            return false
            #endif
        }

        if let remoteConfig = remoteServers.first(where: { $0.name == name }) {
            do {
                let client = MCPClient(
                    name: remoteConfig.name,
                    version: "0.1.3",
                    connectionTimeout: remoteConfig.connectionTimeout ?? connectionTimeout,
                    toolCallTimeout: remoteConfig.toolCallTimeout
                )
                let effectiveOAuthHandler = oauthHandler ?? MCPOAuthHandler()
                try await effectiveOAuthHandler.connectToRemoteServer(client: client, config: remoteConfig)
                let insertAt = min(index, clients.count)
                clients.insert(client, at: insertAt)
                await buildToolsJson()
                logger.info(
                    "Reconnected remote MCP client",
                    metadata: SwiftAgentKitLogging.metadata(("server", .string(name)))
                )
                return true
            } catch {
                logger.error(
                    "reconnectClient failed for remote MCP server",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("server", .string(name)),
                        ("error", .string(String(describing: error)))
                    )
                )
                return false
            }
        }

        logger.warning(
            "reconnectClient requires config-backed initialization; no boot or remote config for server",
            metadata: SwiftAgentKitLogging.metadata(("server", .string(name)))
        )
        return false
    }

    private func indexOfClient(named name: String) async -> Int? {
        for (index, client) in clients.enumerated() {
            if await client.name == name {
                return index
            }
        }
        return nil
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
    
    /// Get all available tools from MCP clients
    public func availableTools() async -> [ToolDefinition] {
        var allTools: [ToolDefinition] = []
        for client in clients {
            allTools.append(contentsOf: await client.tools)
        }
        return allTools
    }

    /// Canonical typed registration rows for MCP-ingested tools.
    public func registeredToolDescriptors(
        targetProviderCapabilities: ToolSchemaTargetProviderCapabilities = .providerSafe
    ) async -> [RegisteredToolDescriptor] {
        var descriptors: [RegisteredToolDescriptor] = []
        var diagnostics: [ToolIngestionDiagnostic] = []
        let normalizer = ToolSchemaNormalizer()
        for client in clients {
            let tools = await client.tools
            for tool in tools {
                let rawSchema = await client.rawInputSchema(for: tool.name) ?? tool.inferredSchemaJSON
                let normalized = normalizer.normalize(
                    rawSchema: rawSchema,
                    source: .mcp,
                    toolName: tool.name,
                    targetProviderCapabilities: targetProviderCapabilities
                )
                descriptors.append(
                    RegisteredToolDescriptor(
                        definition: tool,
                        source: .mcp,
                        effectClass: .mutating,
                        parallelHint: .serialOnly,
                        policyTags: [],
                        normalizedSchema: normalized
                    )
                )
                if normalized.report.didFallback {
                    diagnostics.append(
                        ToolIngestionDiagnostic(
                            toolName: tool.name,
                            source: .mcp,
                            message: "Schema normalization applied fallback policy."
                        )
                    )
                }
            }
        }
        ingestionDiagnostics = diagnostics
        return descriptors
    }
    
    // MARK: - Private
    
    private func loadMCPConfiguration(configFileURL: URL) async throws {
        do {
            let config = try MCPConfigHelper.parseMCPConfig(fileURL: configFileURL)
            try await createClients(config)
            state = .initialized
        } catch {
            logger.error(
                "Error loading MCP configuration",
                metadata: SwiftAgentKitLogging.metadata(("error", .string(String(describing: error))))
            )
            state = .notReady
        }
    }
    
    private func createClients(_ config: MCPConfig) async throws {
        toolCallTimeout = config.toolCallTimeout
        serverBootCalls = config.serverBootCalls
        remoteServers = config.remoteServers
        globalEnvironment = config.globalEnvironment
        var failedServers: [String] = []
        
        // Create clients for local servers (stdio): boot-and-connect each server
        // independently so a slow peer (e.g. cold `swift run`) cannot starve others.
        #if os(macOS) || os(Linux) || os(Windows)
        if !config.serverBootCalls.isEmpty {
            await bootAndConnectLocalServers(config: config, failedServers: &failedServers)
        }
        #else
        if !config.serverBootCalls.isEmpty {
            let skipped = config.serverBootCalls.map(\.name)
            logger.warning(
                "Local MCP stdio servers are not supported on this platform; skipping",
                metadata: SwiftAgentKitLogging.metadata(
                    ("count", .stringConvertible(skipped.count)),
                    ("servers", .string(skipped.joined(separator: ", ")))
                )
            )
            failedServers.append(contentsOf: skipped)
        }
        #endif
        
        // Create clients for remote servers (HTTP/HTTPS).
        // Use the provided oauthHandler, or create a default so remote servers requiring
        // manual OAuth can complete the flow.
        let effectiveOAuthHandler: MCPOAuthHandler?
        if !config.remoteServers.isEmpty {
            effectiveOAuthHandler = oauthHandler ?? MCPOAuthHandler()
        } else {
            effectiveOAuthHandler = nil
        }

        for remoteConfig in config.remoteServers {
            do {
                let client = MCPClient(
                    name: remoteConfig.name,
                    version: "0.1.3",
                    connectionTimeout: remoteConfig.connectionTimeout ?? connectionTimeout,
                    toolCallTimeout: remoteConfig.toolCallTimeout
                )

                if let handler = effectiveOAuthHandler {
                    try await handler.connectToRemoteServer(client: client, config: remoteConfig)
                } else {
                    try await client.connectToRemoteServer(config: remoteConfig)
                }

                clients.append(client)
                logger.info(
                    "Successfully connected to remote MCP server",
                    metadata: SwiftAgentKitLogging.metadata(("server", .string(remoteConfig.name)))
                )

            } catch let mcpError as MCPClient.MCPClientError {
                logMCPClientError(mcpError, serverName: remoteConfig.name)
                failedServers.append(remoteConfig.name)
            } catch let oauthFlowError as OAuthManualFlowRequired {
                logger.warning(
                    "OAuth sign-in required for MCP server — use MCPOAuthHandler to complete authentication",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("server", .string(remoteConfig.name)),
                        ("authorizationURL", .string(oauthFlowError.authorizationURL.absoluteString))
                    )
                )
                failedServers.append(remoteConfig.name)
            } catch {
                logger.error(
                    "Failed to connect to remote MCP server",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("server", .string(remoteConfig.name)),
                        ("error", .string(String(describing: error)))
                    )
                )
                failedServers.append(remoteConfig.name)
            }
        }
        
        if !failedServers.isEmpty {
            logger.warning(
                "Failed to connect to MCP servers",
                metadata: SwiftAgentKitLogging.metadata(
                    ("count", .stringConvertible(failedServers.count)),
                    ("servers", .string(failedServers.joined(separator: ", ")))
                )
            )
        }
        
        await buildToolsJson()
    }

    #if os(macOS) || os(Linux) || os(Windows)
    /// Boots and connects each local stdio server in parallel. Failures terminate that
    /// subprocess and continue; peers are never blocked behind a hung boot/connect.
    private func bootAndConnectLocalServers(
        config: MCPConfig,
        failedServers: inout [String]
    ) async {
        let serverManager = MCPServerManager()
        let timeout = connectionTimeout
        let globalEnvironment = config.globalEnvironment
        let bootCalls = config.serverBootCalls

        await withTaskGroup(of: LocalBootResult.self) { group in
            for bootCall in bootCalls {
                group.addTask {
                    await Self.bootAndConnectOneLocalServer(
                        bootCall: bootCall,
                        globalEnvironment: globalEnvironment,
                        connectionTimeout: timeout,
                        serverManager: serverManager
                    )
                }
            }

            for await result in group {
                switch result {
                case .success(let name, let client, let process):
                    clients.append(client)
                    localServerProcesses[name] = process.value
                    logger.info(
                        "Successfully connected to local MCP server",
                        metadata: SwiftAgentKitLogging.metadata(("server", .string(name)))
                    )
                case .failure(let name, let kind, let elapsed):
                    failedServers.append(name)
                    logger.warning(
                        "MCP server failed; continuing with remaining clients",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("server", .string(name)),
                            ("elapsedSeconds", .stringConvertible(elapsed)),
                            ("failure", .string(kind)),
                            ("connectedCount", .stringConvertible(clients.count))
                        )
                    )
                }
            }
        }
    }

    /// Boot → connect (including timed getTools) for a single local server.
    private nonisolated static func bootAndConnectOneLocalServer(
        bootCall: MCPConfig.ServerBootCall,
        globalEnvironment: JSON,
        connectionTimeout: TimeInterval,
        serverManager: MCPServerManager
    ) async -> LocalBootResult {
        let start = ContinuousClock.now
        var process: Process?
        do {
            let pipes = try await serverManager.bootServer(
                bootCall: bootCall,
                globalEnvironment: globalEnvironment
            )
            process = pipes.process
            let client = MCPClient(
                name: bootCall.name,
                version: "0.1.3",
                connectionTimeout: connectionTimeout,
                toolCallTimeout: bootCall.toolCallTimeout
            )
            // connect(inPipe:) already loads tools under connectionTimeout.
            try await client.connect(inPipe: pipes.inPipe, outPipe: pipes.outPipe)
            return .success(
                name: bootCall.name,
                client: client,
                process: UncheckedProcess(pipes.process)
            )
        } catch {
            if let process {
                Shell.terminateProcess(process)
            }
            let elapsed = start.elapsedSeconds(until: ContinuousClock.now)
            let kind: String
            if let mcpError = error as? MCPClient.MCPClientError {
                switch mcpError {
                case .connectionTimeout(let timeout):
                    kind = "timeout(\(timeout)s)"
                case .pipeError(let message):
                    kind = "pipeError(\(message))"
                case .processTerminated(let message):
                    kind = "processTerminated(\(message))"
                case .connectionFailed(let message):
                    kind = "connectionFailed(\(message))"
                case .notConnected:
                    kind = "notConnected"
                }
            } else {
                kind = String(describing: error)
            }
            return .failure(name: bootCall.name, kind: kind, elapsed: elapsed)
        }
    }
    #endif

    private func logMCPClientError(_ mcpError: MCPClient.MCPClientError, serverName: String) {
        switch mcpError {
        case .connectionTimeout(let timeout):
            logger.warning(
                "MCP server connection timed out",
                metadata: SwiftAgentKitLogging.metadata(
                    ("server", .string(serverName)),
                    ("timeoutSeconds", .stringConvertible(timeout))
                )
            )
        case .pipeError(let message):
            logger.warning(
                "MCP server pipe error",
                metadata: SwiftAgentKitLogging.metadata(
                    ("server", .string(serverName)),
                    ("message", .string(message))
                )
            )
        case .processTerminated(let message):
            logger.warning(
                "MCP server process terminated",
                metadata: SwiftAgentKitLogging.metadata(
                    ("server", .string(serverName)),
                    ("message", .string(message))
                )
            )
        case .connectionFailed(let message):
            logger.warning(
                "MCP server connection failed",
                metadata: SwiftAgentKitLogging.metadata(
                    ("server", .string(serverName)),
                    ("message", .string(message))
                )
            )
        case .notConnected:
            logger.warning(
                "MCP server not connected",
                metadata: SwiftAgentKitLogging.metadata(("server", .string(serverName)))
            )
        }
    }
    
    private func createAuthProvider(for remoteConfig: MCPConfig.RemoteServerConfig) throws -> (any AuthenticationProvider)? {
        // Try environment-based auth first
        if let envAuthProvider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: remoteConfig.name) {
            logger.info(
                "Using environment-based authentication for server",
                metadata: SwiftAgentKitLogging.metadata(("server", .string(remoteConfig.name)))
            )
            return envAuthProvider
        }
        
        // Try config-based auth
        guard let authType = remoteConfig.authType,
              let authConfig = remoteConfig.authConfig else {
            logger.info(
                "No authentication configured for remote server",
                metadata: SwiftAgentKitLogging.metadata(("server", .string(remoteConfig.name)))
            )
            return nil
        }
        
        logger.info(
            "Creating authentication provider from config",
            metadata: SwiftAgentKitLogging.metadata(("server", .string(remoteConfig.name)))
        )
        return try AuthenticationFactory.createAuthProvider(authType: authType, config: authConfig, serverURL: remoteConfig.url)
    }
    
    private func buildToolsJson() async {
        var json: [[String: Any]] = []
        for client in clients {
            for tool in await client.tools {
                json.append(tool.toolCallJson())
            }
        }
        toolCallsJson = json
    }
    
}

extension Tool {
    
    func toolCallJson() -> [String: Any] {
        var returnValue: [String: Any] = ["type": "function"]
        var properties: [String: Any] = [:]
        var required: [String] = []
        if case .object(let schema) = inputSchema {
            if case .array(let requiredValues) = schema["required"] {
                required = requiredValues.compactMap { value in
                    if case .string(let stringValue) = value { return stringValue }
                    return nil
                }
            }
            if case .object(let propertiesObject) = schema["properties"] {
                for (key, value) in propertiesObject {
                    guard case .object(let objectValue) = value else { continue }
                    var typeString = "string"
                    var descriptionString = ""
                    if case .string(let stringValue) = objectValue["type"] {
                        typeString = stringValue
                    }
                    if case .string(let stringValue) = objectValue["description"] {
                        descriptionString = stringValue
                    }
                    properties[key] = [
                        "type": typeString,
                        "description": descriptionString
                    ]
                }
            }
        }
        returnValue["function"] = [
            "name": name,
            "description": description ?? "",
            "parameters": [
                "type": "object",
                "properties": properties,
                "required": required,
            ]
        ]
        return returnValue
    }
}

extension ToolCall {
    public func argumentsToValue() -> [String: Value] {
        func convertJSONToValue(_ json: JSON) -> Value {
            switch json {
            case .boolean(let boolValue):
                return Value.bool(boolValue)
            case .integer(let intValue):
                return Value.int(intValue)
            case .double(let doubleValue):
                return Value.double(doubleValue)
            case .string(let stringValue):
                return Value.string(stringValue)
            case .array(let arrayValue):
                return Value.array(arrayValue.map(convertJSONToValue))
            case .object(let objectValue):
                return Value.object(objectValue.mapValues(convertJSONToValue))
            }
        }
        
        // Extract the object dictionary from JSON
        guard case .object(let dict) = arguments else {
            return [:]
        }
        
        return dict.mapValues(convertJSONToValue)
    }
}

#if os(macOS) || os(Linux) || os(Windows)
/// Result of a parallel local MCP boot-and-connect attempt.
/// `Process` is wrapped as `@unchecked Sendable` so it can cross the task-group boundary.
private enum LocalBootResult: Sendable {
    case success(name: String, client: MCPClient, process: UncheckedProcess)
    case failure(name: String, kind: String, elapsed: TimeInterval)
}

private struct UncheckedProcess: @unchecked Sendable {
    let value: Process
    init(_ value: Process) { self.value = value }
}

private extension ContinuousClock.Instant {
    func elapsedSeconds(until end: ContinuousClock.Instant) -> TimeInterval {
        let duration = self.duration(to: end)
        let (seconds, attoseconds) = duration.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
#endif

