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

/// Manages tool calling via MCP
/// Loads a configuration of available MCP servers
/// Creates a MCPClient for every available server
/// Dispatches tool calls to clients
public actor MCPManager {
    private let logger = Logger(label: "MCPManager")
    private let connectionTimeout: TimeInterval
    
    public init(connectionTimeout: TimeInterval = 30.0) {
        self.connectionTimeout = connectionTimeout
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
            logger.error("Failed to initialize MCPManager: \(error)")
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
            logger.error("Error loading MCP configuration: \(error)")
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
                    logger.info("Successfully connected to local MCP server: \(serverName)")
                } catch let mcpError as MCPClient.MCPClientError {
                    logMCPClientError(mcpError, serverName: serverName)
                    failedServers.append(serverName)
                } catch {
                    logger.error("Failed to connect to local MCP server '\(serverName)': \(error)")
                    failedServers.append(serverName)
                }
            }
        }
        
        // Create clients for remote servers (HTTP/HTTPS)
        for remoteConfig in config.remoteServers {
            do {
                let client = MCPClient(
                    name: remoteConfig.name,
                    version: "0.1.3",
                    connectionTimeout: remoteConfig.connectionTimeout ?? connectionTimeout
                )
                
                guard let serverURL = URL(string: remoteConfig.url) else {
                    logger.error("Invalid URL for remote server '\(remoteConfig.name)': \(remoteConfig.url)")
                    failedServers.append(remoteConfig.name)
                    continue
                }
                
                // Create authentication provider if configured
                let authProvider = try createAuthProvider(for: remoteConfig)
                
                try await client.connectToRemoteServer(
                    serverURL: serverURL,
                    authProvider: authProvider,
                    connectionTimeout: remoteConfig.connectionTimeout,
                    requestTimeout: remoteConfig.requestTimeout,
                    maxRetries: remoteConfig.maxRetries
                )
                
                clients.append(client)
                logger.info("Successfully connected to remote MCP server: \(remoteConfig.name)")
                
            } catch let mcpError as MCPClient.MCPClientError {
                logMCPClientError(mcpError, serverName: remoteConfig.name)
                failedServers.append(remoteConfig.name)
            } catch {
                logger.error("Failed to connect to remote MCP server '\(remoteConfig.name)': \(error)")
                failedServers.append(remoteConfig.name)
            }
        }
        
        if !failedServers.isEmpty {
            logger.warning("Failed to connect to \(failedServers.count) MCP servers: \(failedServers.joined(separator: ", "))")
        }
        
        await buildToolsJson()
    }
    
    private func logMCPClientError(_ mcpError: MCPClient.MCPClientError, serverName: String) {
        switch mcpError {
        case .connectionTimeout(let timeout):
            logger.warning("MCP server '\(serverName)' connection timed out after \(timeout) seconds")
        case .pipeError(let message):
            logger.warning("MCP server '\(serverName)' pipe error: \(message)")
        case .processTerminated(let message):
            logger.warning("MCP server '\(serverName)' process terminated: \(message)")
        case .connectionFailed(let message):
            logger.warning("MCP server '\(serverName)' connection failed: \(message)")
        case .notConnected:
            logger.warning("MCP server '\(serverName)' not connected")
        }
    }
    
    private func createAuthProvider(for remoteConfig: MCPConfig.RemoteServerConfig) throws -> (any AuthenticationProvider)? {
        // Try environment-based auth first
        if let envAuthProvider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: remoteConfig.name) {
            logger.info("Using environment-based authentication for server: \(remoteConfig.name)")
            return envAuthProvider
        }
        
        // Try config-based auth
        guard let authType = remoteConfig.authType,
              var authConfig = remoteConfig.authConfig else {
            logger.info("No authentication configured for remote server: \(remoteConfig.name)")
            return nil
        }
        
        // For OAuth providers, automatically add the resource parameter as required by RFC 8707
        if authType.lowercased() == "oauth" {
            // Extract canonical resource URI from server URL
            if let serverURL = URL(string: remoteConfig.url) {
                // Extract canonical resource URI from server URL
                var uriString = serverURL.absoluteString
                // Remove trailing slash if present (unless it's the root path)
                if uriString.hasSuffix("/") && uriString != serverURL.scheme! + "://" + serverURL.host! + "/" {
                    uriString = String(uriString.dropLast())
                }
                let canonicalResourceURI = uriString
                
                // Add resource URI to auth config if not already present
                if case .object(var configDict) = authConfig {
                    if configDict["resourceURI"] == nil {
                        configDict["resourceURI"] = .string(canonicalResourceURI)
                        authConfig = .object(configDict)
                        logger.info("Added resource parameter for MCP server '\(remoteConfig.name)': \(canonicalResourceURI)")
                    }
                }
            }
        }
        
        logger.info("Creating authentication provider from config for server: \(remoteConfig.name)")
        return try AuthenticationFactory.createAuthProvider(authType: authType, config: authConfig)
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
            "description": description,
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
        func convertSendableToValue(value: Sendable) -> Value {
            if let boolValue = value as? Bool {
                return Value.bool(boolValue)
            } else if let intValue = value as? Int {
                return Value.int(intValue)
            } else if let doubleValue = value as? Double {
                return Value.double(doubleValue)
            } else if let stringValue = value as? String {
                return Value.string(stringValue)
            } else if let dataValue = value as? Data {
                return Value.data(mimeType: nil, dataValue)
            } else if let arrayValue = value as? [Sendable] {
                return Value.array(arrayValue.map(convertSendableToValue))
            } else if let objectValue = value as? [String: Sendable] {
                return Value.object(objectValue.mapValues(convertSendableToValue))
            } else {
                return Value.null
            }
        }
        return arguments.mapValues(convertSendableToValue)
    }
}
