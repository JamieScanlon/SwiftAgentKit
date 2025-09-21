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
    public var state: State = .notConnected
    
    public private(set) var tools: [ToolDefinition] = []
    public private(set) var resources: [Resource] = []
    public private(set) var prompts: [Prompt] = []
    private let logger = Logger(label: "MCPClient")
    private let messageFilterConfig: MessageFilter.Configuration
    
    public init(
        name: String, 
        version: String = "1.0", 
        isStrict: Bool = false,
        connectionTimeout: TimeInterval = 30.0,
        messageFilterConfig: MessageFilter.Configuration = .default
    ) {
        self.name = name
        self.version = version
        self.isStrict = isStrict
        self.connectionTimeout = connectionTimeout
        self.messageFilterConfig = messageFilterConfig
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
            // Connect the client to the transport with timeout
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Add the connection task
                group.addTask {
                    try await newClient.connect(transport: transport)
                }
                
                // Add the timeout task
                group.addTask {
                    try await Task.sleep(for: .seconds(self.connectionTimeout))
                    throw MCPClientError.connectionTimeout(self.connectionTimeout)
                }
                
                // Wait for either connection or timeout
                try await group.next()
                
                // Cancel remaining tasks
                group.cancelAll()
            }
            
            // Store the connected client
            self.client = newClient
            
            // Get capabilities after connection
            self.capabilities = await newClient.capabilities
            state = .connected
            logger.info("MCP client '\(name)' connected successfully")
        } catch {
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
            logger.error("Invalid server URL in RemoteServerConfig: \(config.url)")
            throw MCPClientError.connectionFailed("Invalid server URL: \(config.url)")
        }
        
        // Create authentication provider if auth configuration is provided
        let authProvider: (any AuthenticationProvider)?
        if let authType = config.authType, let authConfig = config.authConfig {
            do {
                authProvider = try AuthenticationFactory.createAuthProvider(
                    authType: authType,
                    config: authConfig
                )
                logger.info("Created authentication provider for type: \(authType)")
            } catch {
                logger.error("Failed to create authentication provider: \(error)")
                throw MCPClientError.connectionFailed("Authentication configuration error: \(error.localizedDescription)")
            }
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
        
        logger.info("Connecting to remote server '\(config.name)' at \(config.url)")
        
        do {
            try await connect(transport: transport)
            try await getTools()
            logger.info("Successfully connected to remote server '\(config.name)'")
        } catch let oauthFlowError as OAuthManualFlowRequired {
            logger.info("OAuth manual flow required for MCP server - propagating error with metadata")
            // Re-throw the OAuth manual flow required error to preserve all metadata
            throw oauthFlowError
        } catch let transportError as RemoteTransport.RemoteTransportError {
            // Check if this is an OAuth discovery requirement
            if case .oauthDiscoveryRequired(let resourceMetadataURL) = transportError {
                logger.info("OAuth discovery required for MCP server, resource metadata: \(resourceMetadataURL)")
                
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
        logger.info("Starting OAuth discovery process for MCP server")
        
        // Create OAuthDiscoveryAuthProvider with MCP-specific configuration
        let redirectURI = URL(string: "com.swiftagentkit.mcp://oauth-callback")!
        let discoveryAuthProvider = try OAuthDiscoveryAuthProvider(
            resourceServerURL: serverURL,
            clientId: "swiftagentkit-mcp-client",
            scope: "mcp",
            redirectURI: redirectURI,
            resourceType: "mcp"
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
            logger.info("Attempting connection with OAuth discovery provider")
            try await connect(transport: discoveryTransport)
            try await getTools()
            logger.info("Successfully connected to remote server '\(config.name)' using OAuth discovery")
        } catch let oauthFlowError as OAuthManualFlowRequired {
            logger.info("OAuth manual flow required for MCP server - propagating error with metadata")
            // Re-throw the OAuth manual flow required error to preserve all metadata
            throw oauthFlowError
        } catch {
            logger.error("OAuth discovery failed for MCP server: \(error)")
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
            let transport = ClientTransport(inPipe: inPipe, outPipe: outPipe, logger: logger)
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
        // List available tools
        let (tools, _) = try await client.listTools()
        self.tools = tools.map { ToolDefinition(tool: $0) }
    }
    
    public func callTool(_ toolName: String, arguments: [String: Value]? = nil) async throws -> [Tool.Content]? {
        
        guard let client = client else {
            throw MCPClientError.notConnected
        }
        
        guard tools.map(\.name).firstIndex(of: toolName) != nil else {
            return nil
        }
        
        let (content, _) = try await client.callTool(name: toolName, arguments: arguments)
        // Handle tool content
        for item in content {
            switch item {
            case .text(let text):
                logger.info("Generated text: \(text)")
            case .image(_, let mimeType, let metadata):
                if let width = metadata?["width"] as? Int,
                   let height = metadata?["height"] as? Int {
                    logger.info("Generated \(width)x\(height) image of type \(mimeType)")
                    // Save or display the image data
                }
            case .audio(_, let mimeType):
                logger.info("Received audio data of type \(mimeType)")
            case .resource(let uri, let mimeType, let text):
                logger.info("Received resource from \(uri) of type \(mimeType)")
                if let text = text {
                    logger.info("Resource text: \(text)")
                }
            }
        }
        return content
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
            self.logger.info("Resource \(uri) updated with new content")
            
            // Fetch the updated resource content
            _ = try await self.client?.readResource(uri: uri)
            self.logger.info("Updated resource content received")
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
        let (_, messages) = try await client.getPrompt(name: name, arguments: arguments)
        return messages
    }
    
    // MARK: - Private
    
    private var client: Client?
    private var capabilities: Client.Capabilities?
    private var process: Process?
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
        self.init(name: tool.name, description: tool.description, parameters: parameters, type: .mcpTool)
    }
}
