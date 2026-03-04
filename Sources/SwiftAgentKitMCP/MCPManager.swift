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
/// For remote servers that require OAuth (e.g. Todoist, Zapier), pass an ``MCPOAuthHandler``
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
    public private(set) var clients: [MCPClient] = []
    
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
    
    /// Initialize the A2AManager with an arrat of `MCPClient` objects
    public func initialize(clients: [MCPClient]) async throws {
        self.clients = clients
        await buildToolsJson()
    }
    
    public func toolCall(_ toolCall: ToolCall) async throws -> [LLMResponse]? {
        for client in clients {
            if let contents = try await client.callTool(toolCall.name, arguments: toolCall.argumentsToValue()) {
                var returnResponses: [LLMResponse] = []
                for content in contents {
                    switch content {
                    case .text(let text):
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
    
    /// Get all available tools from MCP clients
    public func availableTools() async -> [ToolDefinition] {
        var allTools: [ToolDefinition] = []
        for client in clients {
            allTools.append(contentsOf: await client.tools)
        }
        return allTools
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
        var failedServers: [String] = []
        
        // Create clients for local servers (stdio)
        if !config.serverBootCalls.isEmpty {
            let serverManager = MCPServerManager()
            let serverPipes = try await serverManager.bootServers(config: config)
            
            for (serverName, pipes) in serverPipes {
                do {
                    let client = MCPClient(name: serverName, version: "0.1.3", connectionTimeout: connectionTimeout)
                    try await client.connect(inPipe: pipes.inPipe, outPipe: pipes.outPipe)
                    try await client.getTools()
                    clients.append(client)
                    logger.info(
                        "Successfully connected to local MCP server",
                        metadata: SwiftAgentKitLogging.metadata(("server", .string(serverName)))
                    )
                } catch let mcpError as MCPClient.MCPClientError {
                    logMCPClientError(mcpError, serverName: serverName)
                    failedServers.append(serverName)
                } catch {
                    logger.error(
                        "Failed to connect to local MCP server",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("server", .string(serverName)),
                            ("error", .string(String(describing: error)))
                        )
                    )
                    failedServers.append(serverName)
                }
            }
        }
        
        // Create clients for remote servers (HTTP/HTTPS).
        // Use the provided oauthHandler, or create a default so remote servers requiring
        // manual OAuth (e.g. Todoist, Zapier) can complete the flow.
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
                    connectionTimeout: remoteConfig.connectionTimeout ?? connectionTimeout
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

