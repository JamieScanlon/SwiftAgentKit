//
//  MCPClient.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 5/17/25.
//

import EasyJSON
import Foundation
import Logging
import MCP
import System
import SwiftAgentKit

/// MCP clients maintain 1:1 connections with servers, inside the MCP host application
public actor MCPClient {
    
    public enum State: Sendable {
        case notConnected
        case connected
        case error
    }
    
    public enum MCPClientError: LocalizedError {
        case notConnected
        case connectionTimeout(TimeInterval)
        case pipeError(String)
        case processTerminated(String)
        case connectionFailed(String)
        
        public var errorDescription: String? {
            switch self {
            case .notConnected:
                return "MCP client is not connected"
            case .connectionTimeout(let timeout):
                return "MCP client connection timed out after \(timeout) seconds"
            case .pipeError(let message):
                return "Pipe error: \(message)"
            case .processTerminated(let message):
                return "Process terminated: \(message)"
            case .connectionFailed(let message):
                return "Connection failed: \(message)"
            }
        }
    }
    
    public let name: String
    public let version: String
    public let isStrict: Bool
    public let connectionTimeout: TimeInterval
    /// Per-server tool-call limit from MCP config (seconds); `nil` means use manager/orchestrator defaults.
    public let toolCallTimeout: TimeInterval?
    public let clientID: String
    public var state: State = .notConnected
    
    public private(set) var tools: [ToolDefinition] = []
    /// Preserved MCP `inputSchema` JSON keyed by tool name. Last writer wins within this client.
    public private(set) var toolInputSchemasByName: [String: JSON] = [:]
    public private(set) var resources: [Resource] = []
    public private(set) var prompts: [Prompt] = []
    private let logger: Logger
    private let messageFilterConfig: MessageFilter.Configuration
    
    public init(
        name: String, 
        version: String = "1.0", 
        isStrict: Bool = false,
        connectionTimeout: TimeInterval = 30.0,
        toolCallTimeout: TimeInterval? = nil,
        clientID: String = "swiftagentkit-mcp-client",
        messageFilterConfig: MessageFilter.Configuration = .default,
        logger: Logger? = nil
    ) {
        self.name = name
        self.version = version
        self.isStrict = isStrict
        self.connectionTimeout = connectionTimeout
        self.toolCallTimeout = toolCallTimeout
        self.clientID = clientID
        self.messageFilterConfig = messageFilterConfig
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .mcp("MCPClient"),
            metadata: SwiftAgentKitLogging.metadata(
                ("client", .string(name)),
                ("version", .string(version)),
                ("strict", .string(isStrict ? "true" : "false"))
            )
        )
        // Client will be created when connecting to transport
    }
    
    /// Connect to an MCP server using the provided transport
    /// - Parameter transport: The transport to use for communication
    public func connect(transport: Transport) async throws {
        // Set up signal handling for SIGPIPE to prevent process termination
        let originalSIGPIPEHandler = signal(SIGPIPE, SIG_IGN)
        defer {
            signal(SIGPIPE, originalSIGPIPEHandler)
        }
        
        let configuration = Client.Configuration(strict: isStrict)
        let newClient = Client(name: name, version: version, configuration: configuration)
        
        do {
            // Race connect against a wall-clock timeout. On timeout we must call
            // `disconnect()` so SDK pending-request continuations resume; Task
            // cancellation alone cannot unblock `sendAndAwait` waiting for a response.
            _ = try await withTimeout(
                seconds: connectionTimeout,
                onTimeout: { await newClient.disconnect() }
            ) {
                try await newClient.connect(transport: transport)
            }
            
            // Store the connected client
            self.client = newClient
            
            // Get capabilities after connection
            self.capabilities = await newClient.capabilities
            state = .connected
            logger.info(
                "MCP client connected successfully",
                metadata: SwiftAgentKitLogging.metadata(("client", .string(name)))
            )
        } catch {
            // Preserve OAuthManualFlowRequired errors for manual OAuth flow handling
            if let oauthFlowError = error as? OAuthManualFlowRequired {
                throw oauthFlowError
            }
            
            // Preserve RemoteTransportError types for OAuth discovery handling
            if let remoteTransportError = error as? RemoteTransport.RemoteTransportError {
                throw remoteTransportError
            }
            
            // Convert pipe errors to proper MCP errors
            let nsError = error as NSError
            switch nsError.code {
            case Int(EPIPE):
                throw MCPClientError.pipeError("Broken pipe during transport connection: \(nsError.localizedDescription)")
            case Int(ECONNREFUSED):
                throw MCPClientError.connectionFailed("Connection refused: \(nsError.localizedDescription)")
            case Int(ECONNRESET):
                throw MCPClientError.connectionFailed("Connection reset by peer: \(nsError.localizedDescription)")
            case Int(EAGAIN), Int(EWOULDBLOCK):
                throw MCPClientError.connectionFailed("I/O operation would block: \(nsError.localizedDescription)")
            default:
                // Check if it's a timeout error we already handled
                if case MCPClientError.connectionTimeout = error {
                    throw error
                }
                throw MCPClientError.connectionFailed("Transport connection error: \(nsError.localizedDescription)")
            }
        }
    }
    
    /// Connect to a remote MCP server using HTTP/HTTPS
    /// - Parameters:
    ///   - serverURL: URL of the remote MCP server
    ///   - authProvider: Authentication provider (optional)
    ///   - connectionTimeout: Connection timeout override (optional)
    ///   - requestTimeout: Request timeout override (optional)
    ///   - maxRetries: Maximum retry attempts override (optional)
    public func connectToRemoteServer(
        serverURL: URL,
        authProvider: (any AuthenticationProvider)? = nil,
        connectionTimeout: TimeInterval? = nil,
        requestTimeout: TimeInterval? = nil,
        maxRetries: Int? = nil
    ) async throws {
        let transport = RemoteTransport(
            serverURL: serverURL,
            authProvider: authProvider,
            connectionTimeout: connectionTimeout ?? self.connectionTimeout,
            requestTimeout: requestTimeout ?? 60.0,
            maxRetries: maxRetries ?? 3
        )
        
        try await connect(transport: transport)
        try await getTools()
    }
    
    /// Connect to a remote MCP server using a RemoteServerConfig
    /// - Parameter config: Remote server configuration containing URL, auth, and connection settings
    public func connectToRemoteServer(config: MCPConfig.RemoteServerConfig) async throws {
        // Parse and validate the server URL
        guard let serverURL = URL(string: config.url),
              let scheme = serverURL.scheme,
              !scheme.isEmpty,
              serverURL.host != nil else {
            logger.error(
                "Invalid server URL in RemoteServerConfig",
                metadata: SwiftAgentKitLogging.metadata(
                    ("server", .string(config.name)),
                    ("url", .string(config.url))
                )
            )
            throw MCPClientError.connectionFailed("Invalid server URL: \(config.url)")
        }
        
        // Create authentication provider: config first, then environment-based (so OAuth discovery still runs when server returns 401 + resource_metadata)
        let authProvider: (any AuthenticationProvider)?
        if let authType = config.authType, let authConfig = config.authConfig {
            do {
                authProvider = try AuthenticationFactory.createAuthProvider(
                    authType: authType,
                    config: authConfig,
                    serverURL: config.url
                )
                logger.info(
                    "Created authentication provider",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("server", .string(config.name)),
                        ("authType", .string(authType))
                    )
                )
            } catch {
                logger.error(
                    "Failed to create authentication provider",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("server", .string(config.name)),
                        ("error", .string(String(describing: error)))
                    )
                )
                throw MCPClientError.connectionFailed("Authentication configuration error: \(error.localizedDescription)")
            }
        } else if let envAuthProvider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: config.name) {
            authProvider = envAuthProvider
            logger.info(
                "Using environment-based authentication for server",
                metadata: SwiftAgentKitLogging.metadata(("server", .string(config.name)))
            )
        } else {
            authProvider = nil
        }
        
        // Create RemoteTransport with configuration values
        let transport = RemoteTransport(
            serverURL: serverURL,
            authProvider: authProvider,
            connectionTimeout: config.connectionTimeout ?? self.connectionTimeout,
            requestTimeout: config.requestTimeout ?? 60.0,
            maxRetries: config.maxRetries ?? 3
        )
        
        logger.info(
            "Connecting to remote server",
            metadata: SwiftAgentKitLogging.metadata(
                ("server", .string(config.name)),
                ("url", .string(config.url))
            )
        )
        
        do {
            try await connect(transport: transport)
            try await getTools()
            logger.info(
                "Successfully connected to remote server",
                metadata: SwiftAgentKitLogging.metadata(("server", .string(config.name)))
            )
        } catch let oauthFlowError as OAuthManualFlowRequired {
            logger.info(
                "OAuth manual flow required for MCP server",
                metadata: SwiftAgentKitLogging.metadata(("server", .string(config.name)))
            )
            // Re-throw the OAuth manual flow required error to preserve all metadata
            throw oauthFlowError
        } catch let transportError as RemoteTransport.RemoteTransportError {
            // Check if this is an OAuth discovery requirement
            if case .oauthDiscoveryRequired(let resourceMetadataURL) = transportError {
                logger.info(
                    "OAuth discovery required for MCP server",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("server", .string(config.name)),
                        ("resourceMetadataURL", .string(resourceMetadataURL))
                    )
                )
                
                // Attempt OAuth discovery and retry connection
                try await connectWithOAuthDiscovery(serverURL: serverURL, config: config, resourceMetadataURL: resourceMetadataURL)
            } else {
                // Convert RemoteTransportError to MCPClientError
                throw MCPClientError.connectionFailed("Transport connection error: \(transportError.localizedDescription)")
            }
        } catch let error as MCPClientError {
            throw error
        } catch {
            throw MCPClientError.connectionFailed("Unexpected connection error: \(error.localizedDescription)")
        }
    }
    
    /// Attempt OAuth discovery and dynamic client registration for MCP server
    /// - Parameters:
    ///   - serverURL: The MCP server URL
    ///   - config: The remote server configuration
    ///   - resourceMetadataURL: The resource metadata URL from the OAuth challenge
    private func connectWithOAuthDiscovery(serverURL: URL, config: MCPConfig.RemoteServerConfig, resourceMetadataURL: String) async throws {
        logger.info(
            "Starting OAuth discovery process for MCP server",
            metadata: SwiftAgentKitLogging.metadata(
                ("server", .string(config.name)),
                ("resourceMetadataURL", .string(resourceMetadataURL))
            )
        )
        
        // Extract redirect URI from configuration or use default
        let redirectURIString: String
        if let authConfig = config.authConfig,
           case .object(let authDict) = authConfig,
           case .array(let redirectUris) = authDict["redirectUris"],
           case .string(let firstRedirectURI) = redirectUris.first {
            redirectURIString = firstRedirectURI
        } else {
            // Default fallback redirect URI
            redirectURIString = "http://localhost:8080/oauth/callback"
        }
        
        // Extract scope from configuration or use default
        let scopeString: String
        if let authConfig = config.authConfig,
           case .object(let authDict) = authConfig,
           case .string(let scope) = authDict["scope"] {
            scopeString = scope
        } else {
            // Default scope that works for most MCP servers
            scopeString = "mcp"
        }
        
        guard let redirectURI = URL(string: redirectURIString) else {
            throw MCPClientError.connectionFailed("Invalid redirect URI: \(redirectURIString)")
        }
        
        let clientID = config.clientID ?? self.clientID
        // When config already has a client ID (top-level or in authConfig), skip DCR so we don't attempt
        // registration against servers that don't support it.
        let hasExplicitClientId: Bool
        if config.clientID != nil {
            hasExplicitClientId = true
        } else if let authConfig = config.authConfig, case .object(let authDict) = authConfig, case .string = authDict["clientId"] {
            hasExplicitClientId = true
        } else {
            hasExplicitClientId = false
        }
        let discoveryAuthProvider = try OAuthDiscoveryAuthProvider(
            resourceServerURL: serverURL,
            clientId: clientID,
            scope: scopeString,
            redirectURI: redirectURI,
            resourceType: "mcp",
            preConfiguredAuthServerURL: nil,
            resourceURI: nil,
            resourceMetadataURL: URL(string: resourceMetadataURL),
            attemptDynamicClientRegistration: !hasExplicitClientId
        )
        
        // Create new transport with OAuth discovery provider
        let discoveryTransport = RemoteTransport(
            serverURL: serverURL,
            authProvider: discoveryAuthProvider,
            connectionTimeout: config.connectionTimeout ?? self.connectionTimeout,
            requestTimeout: config.requestTimeout ?? 60.0,
            maxRetries: config.maxRetries ?? 3
        )
        
        do {
            logger.info(
                "Attempting connection with OAuth discovery provider",
                metadata: SwiftAgentKitLogging.metadata(("server", .string(config.name)))
            )
            try await connect(transport: discoveryTransport)
            try await getTools()
            logger.info(
                "Successfully connected to remote server using OAuth discovery",
                metadata: SwiftAgentKitLogging.metadata(("server", .string(config.name)))
            )
        } catch let oauthFlowError as OAuthManualFlowRequired {
            logger.info(
                "OAuth manual flow required for MCP server",
                metadata: SwiftAgentKitLogging.metadata(("server", .string(config.name)))
            )
            // Re-throw the OAuth manual flow required error to preserve all metadata
            throw oauthFlowError
        } catch {
            logger.error(
                "OAuth discovery failed for MCP server",
                metadata: SwiftAgentKitLogging.metadata(
                    ("server", .string(config.name)),
                    ("error", .string(String(describing: error)))
                )
            )
            throw MCPClientError.connectionFailed("OAuth discovery failed: \(error.localizedDescription)")
        }
    }
    
    /// Connect to an MCP server using stdio pipes
    /// - Parameters:
    ///   - inPipe: Input pipe for receiving data from the server
    ///   - outPipe: Output pipe for sending data to the server
    public func connect(inPipe: Pipe, outPipe: Pipe) async throws {
        // Set up signal handling for SIGPIPE to prevent process termination
        let originalSIGPIPEHandler = signal(SIGPIPE, SIG_IGN)
        defer {
            signal(SIGPIPE, originalSIGPIPEHandler)
        }
        
        do {
            let filter = JSONRPCMessageFilter(configuration: messageFilterConfig, logger: logger)
            let transport = ClientTransport(inPipe: inPipe, outPipe: outPipe, messageFilter: filter, logger: logger)
            try await connect(transport: transport)
            try await getTools()
        } catch {
            // Convert pipe errors to proper MCP errors
            let nsError = error as NSError
            switch nsError.code {
            case Int(EPIPE):
                throw MCPClientError.pipeError("Broken pipe during connection: \(nsError.localizedDescription)")
            case Int(ECONNREFUSED):
                throw MCPClientError.connectionFailed("Connection refused: \(nsError.localizedDescription)")
            case Int(ECONNRESET):
                throw MCPClientError.connectionFailed("Connection reset by peer: \(nsError.localizedDescription)")
            case Int(EAGAIN), Int(EWOULDBLOCK):
                throw MCPClientError.connectionFailed("I/O operation would block: \(nsError.localizedDescription)")
            default:
                // Check if it's a timeout error we already handled
                if case MCPClientError.connectionTimeout = error {
                    throw error
                }
                throw MCPClientError.connectionFailed("Connection error: \(nsError.localizedDescription)")
            }
        }
    }
    

    
    func getTools() async throws {
        guard let client = client else {
            throw MCPClientError.notConnected
        }
        // Bound tools/list so a silent server fails closed (same wall clock as connect).
        let (tools, _) = try await withTimeout(
            seconds: connectionTimeout,
            onTimeout: { await client.disconnect() }
        ) {
            try await client.listTools()
        }
        var schemasByName: [String: JSON] = [:]
        for tool in tools {
            schemasByName[tool.name] = MCPValueJSONConversion.convert(tool.inputSchema)
        }
        self.toolInputSchemasByName = schemasByName
        self.tools = tools.map { ToolDefinition(tool: $0) }
    }

    /// Returns the preserved MCP `inputSchema` for a tool, if discovered on this client.
    public func rawInputSchema(for toolName: String) -> JSON? {
        toolInputSchemasByName[toolName]
    }

    /// Installs tool definitions and preserved schemas without a live MCP connection (tests only).
    internal func installToolsForTesting(tools: [ToolDefinition], inputSchemasByName: [String: JSON]) {
        self.tools = tools
        self.toolInputSchemasByName = inputSchemasByName
    }
    
    /// Invokes an MCP `tools/call` RPC with a hard wall-clock timeout.
    ///
    /// On timeout this calls SDK `Client.disconnect()` so hung JSON-RPC waiters resume,
    /// then marks this client ``State/notConnected``. Cooperative `Task` cancellation alone
    /// is not enough for wedged stdio transports — treat a timed-out client as unhealthy
    /// until ``MCPManager/reconnectClient(named:)`` (or a fresh connect).
    ///
    /// - Parameters:
    ///   - toolName: Tool to invoke (must already appear in ``tools``).
    ///   - arguments: MCP tool arguments.
    ///   - timeoutSeconds: Maximum wait. When `nil` or non-positive, uses ``toolCallTimeout``
    ///     if set and positive; otherwise `300`.
    /// - Returns: Tool content, or `nil` if this client does not expose `toolName`
    ///   (including when disconnected — ownership is checked before connectedness).
    /// - Throws: ``MCPClientError/notConnected`` when this client advertises `toolName` but
    ///   has no live session; ``ToolCallTimeoutError`` when the timer wins; other transport/RPC
    ///   errors as thrown by the SDK.
    public func callTool(
        _ toolName: String,
        arguments: [String: Value]? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) async throws -> [Tool.Content]? {
        
        // Ownership first: a disconnected client must soft-skip tools it does not advertise
        // so MCPManager can continue to other clients / fall through to built-ins.
        guard tools.contains(where: { $0.name == toolName }) else {
            return nil
        }
        
        guard let sdkClient = client else {
            throw MCPClientError.notConnected
        }

        let seconds = Self.resolvedCallToolTimeout(
            explicit: timeoutSeconds,
            clientConfigured: toolCallTimeout
        )
        
        let content: [Tool.Content]
        do {
            // Race tools/call against wall clock. On timeout we must disconnect so SDK
            // pending-request continuations resume (same pattern as connect / listTools).
            let (result, _) = try await withTimeout(
                seconds: seconds,
                onTimeout: { await sdkClient.disconnect() }
            ) {
                try await sdkClient.callTool(name: toolName, arguments: arguments)
            }
            content = result
        } catch let error as MCPClientError {
            if case .connectionTimeout(let elapsed) = error {
                markDisconnectedAfterTimeout()
                throw ToolCallTimeoutError(timeout: elapsed, toolName: toolName)
            }
            throw error
        } catch is CancellationError {
            // Outer cooperative timeout (e.g. MCPManager.withToolCallTimeout) cancelled us;
            // withTimeout's catch path already requested disconnect — clear local session state.
            markDisconnectedAfterTimeout()
            throw CancellationError()
        }

        // Handle tool content
        for item in content {
            switch item {
            case .text(let text, _, _):
                logger.info(
                    "Generated text content",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("tool", .string(toolName)),
                        ("characters", .stringConvertible(text.count))
                    )
                )
            case .image(_, let mimeType, _, let _meta):
                if let width = _meta?["width"]?.intValue ?? _meta?["width"]?.stringValue.flatMap(Int.init),
                   let height = _meta?["height"]?.intValue ?? _meta?["height"]?.stringValue.flatMap(Int.init) {
                    logger.info(
                        "Generated image content",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("tool", .string(toolName)),
                            ("mimeType", .string(mimeType)),
                            ("width", .stringConvertible(width)),
                            ("height", .stringConvertible(height))
                        )
                    )
                    // Save or display the image data
                }
            case .audio(_, let mimeType, _, _):
                logger.info(
                    "Received audio content",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("tool", .string(toolName)),
                        ("mimeType", .string(mimeType))
                    )
                )
            case .resource(let resourceContent, _, _):
                let uri = resourceContent.uri
                let mimeType = resourceContent.mimeType ?? ""
                logger.info(
                    "Received resource content",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("tool", .string(toolName)),
                        ("uri", .string(uri)),
                        ("mimeType", .string(mimeType))
                    )
                )
                if let text = resourceContent.text {
                    logger.info(
                        "Resource text content",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("tool", .string(toolName)),
                            ("uri", .string(uri)),
                            ("characters", .stringConvertible(text.count))
                        )
                    )
                }
            case .resourceLink(let uri, let name, _, _, let mimeType, _):
                logger.info(
                    "Received resource link",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("tool", .string(toolName)),
                        ("uri", .string(uri)),
                        ("name", .string(name)),
                        ("mimeType", .string(mimeType ?? ""))
                    )
                )
            }
        }
        return content
    }

    private nonisolated static func resolvedCallToolTimeout(
        explicit: TimeInterval?,
        clientConfigured: TimeInterval?
    ) -> TimeInterval {
        if let explicit, explicit > 0 { return explicit }
        if let clientConfigured, clientConfigured > 0 { return clientConfigured }
        return 300
    }

    /// Clears the local session after a hard disconnect so later calls fail fast with ``MCPClientError/notConnected``.
    ///
    /// Cached ``tools`` (and schemas) are intentionally retained: non-owned names return `nil`
    /// from ``callTool`` so dispatch is not poisoned, while owned names still throw
    /// ``MCPClientError/notConnected`` (fail closed until reconnect).
    private func markDisconnectedAfterTimeout() {
        client = nil
        capabilities = nil
        state = .notConnected
        logger.warning(
            "MCP client disconnected after tools/call timeout; reconnect before further use",
            metadata: SwiftAgentKitLogging.metadata(("client", .string(name)))
        )
    }
    
    func getResources() async throws {
        guard let client = client else {
            throw MCPClientError.notConnected
        }
        // List available tools
        let (resources, _) = try await client.listResources()
        self.resources = resources
    }
    
    func readResource(_ uri: String) async throws -> [Resource.Content] {
        guard let client = client else {
            throw MCPClientError.notConnected
        }
        let contents = try await client.readResource(uri: uri)
        return contents
    }
    
    func subscribeToResource(_ uri: String) async throws {
        guard let client = client else {
            throw MCPClientError.notConnected
        }
        // Subscribe to resource updates if supported
        // Note: Resource subscription capabilities may vary by MCP implementation
        try await client.subscribeToResource(uri: uri)
        
        // Register notification handler
        await client.onNotification(ResourceUpdatedNotification.self) { message in
            let uri = message.params.uri
            self.logger.info(
                "Resource updated with new content",
                metadata: SwiftAgentKitLogging.metadata(("uri", .string(uri)))
            )
            
            // Fetch the updated resource content
            _ = try await self.client?.readResource(uri: uri)
            self.logger.info(
                "Updated resource content received",
                metadata: SwiftAgentKitLogging.metadata(("uri", .string(uri)))
            )
        }
    }
    
    func getPrompts() async throws {
        guard let client = client else {
            throw MCPClientError.notConnected
        }
        // List available tools
        let (prompts, _) = try await client.listPrompts()
        self.prompts = prompts
    }
    
    func getPrompt(_ name: String, arguments: [String: Value]? = nil) async throws -> [Prompt.Message] {
        guard let client = client else {
            throw MCPClientError.notConnected
        }
        let stringArguments = try Self.promptArgumentsAsStrings(arguments)
        let (_, messages) = try await client.getPrompt(name: name, arguments: stringArguments)
        return messages
    }

    /// Converts MCP ``Value`` arguments to strings for ``Client/getPrompt``, which expects `[String: String]`.
    private nonisolated static func promptArgumentsAsStrings(_ arguments: [String: Value]?) throws -> [String: String]? {
        guard let arguments else { return nil }
        var result: [String: String] = [:]
        result.reserveCapacity(arguments.count)
        for (key, value) in arguments {
            result[key] = try promptArgumentString(value)
        }
        return result
    }

    private nonisolated static func promptArgumentString(_ value: Value) throws -> String {
        switch value {
        case .string(let s):
            return s
        case .bool(let b):
            return b ? "true" : "false"
        case .int(let i):
            return String(i)
        case .double(let d):
            return String(d)
        case .null:
            return ""
        case .data:
            return value.description
        case .array, .object:
            let encoded = try JSONEncoder().encode(value)
            return String(decoding: encoded, as: UTF8.self)
        }
    }

    /// Disconnects the SDK session (unblocking any hung JSON-RPC waiters), then clears cached tools.
    /// Local stdio servers are torn down by ``MCPManager/shutdown()`` via subprocess termination.
    public func shutdown() async {
        if let client {
            await client.disconnect()
        }
        client = nil
        capabilities = nil
        tools = []
        toolInputSchemasByName = [:]
        resources = []
        prompts = []
        state = .notConnected
    }
    
    // MARK: - Private
    
    private var client: Client?
    private var capabilities: Client.Capabilities?

    /// Runs `operation` against a wall-clock timeout.
    ///
    /// When the timer wins, `onTimeout` runs (typically `Client.disconnect()` so hung
    /// JSON-RPC waiters resume) and ``MCPClientError/connectionTimeout`` is thrown.
    /// Call sites that need a different error (e.g. ``ToolCallTimeoutError`` for `tools/call`)
    /// map `connectionTimeout` after this returns.
    /// Preferring an explicit timed-out result avoids racing a disconnect-induced
    /// connect failure ahead of the timeout error.
    ///
    /// Cancellation from an outer cooperative timeout also invokes `onTimeout` so stdio
    /// waiters are unblocked even when the outer timer wins the race.
    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        onTimeout: @Sendable @escaping () async -> Void,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: TimeoutRaceResult<T>.self) { group in
            group.addTask {
                .success(try await operation())
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                return .timedOut
            }

            let first: TimeoutRaceResult<T>
            do {
                guard let value = try await group.next() else {
                    throw MCPClientError.connectionFailed("Timeout race produced no result")
                }
                first = value
            } catch {
                await onTimeout()
                group.cancelAll()
                while let _ = try? await group.next() {}
                throw error
            }

            switch first {
            case .success(let value):
                group.cancelAll()
                return value
            case .timedOut:
                await onTimeout()
                group.cancelAll()
                // Drain the cancelled/unblocked operation so the task group can exit.
                while let _ = try? await group.next() {}
                throw MCPClientError.connectionTimeout(seconds)
            }
        }
    }
}

private enum TimeoutRaceResult<T: Sendable>: Sendable {
    case success(T)
    case timedOut
}


extension ToolDefinition {
    public init(tool: Tool) {
        
        var parameters: [ToolDefinition.Parameter] = []
        if case .object(let inputSchema) = tool.inputSchema {
            if case .object(let propertiesValue) = inputSchema["properties"] {
                
                var requiredArray: [String] = []
                if case .array(let requiredValue) = inputSchema["required"] {
                    requiredArray = requiredValue.compactMap({
                        if case .string(let stringValue) = $0 {
                            return stringValue
                        } else {
                            return nil
                        }
                    })
                    
                }
                
                for (key, value) in propertiesValue {
                    
                    guard case .object(let objectValue) = value else { continue }
                    let name: String = key
                    var description = ""
                    var type: String = ""
                    let required: Bool = requiredArray.contains(key)
                    if case .string(let stringValue) = objectValue["type"] {
                        type = stringValue
                    }
                    if case .string(let stringValue) = objectValue["description"] {
                        description = stringValue
                    }
                    parameters.append(.init(name: name, description: description, type: type, required: required))
                }
            }
        }
        self.init(name: tool.name, description: tool.description ?? "", parameters: parameters, type: .mcpTool)
    }
}
