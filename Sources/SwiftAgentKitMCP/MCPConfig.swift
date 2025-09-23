//
//  MCPConfig.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 4/12/25.
//

import EasyJSON
import Foundation
import SwiftAgentKit

public struct MCPConfig: Codable, Sendable {
    
    public struct ServerBootCall: Codable, Sendable {
        public let name: String
        public let command: String
        public let arguments: [String]
        public let environment: JSON
        
        public init(name: String, command: String, arguments: [String], environment: JSON) {
            self.name = name
            self.command = command
            self.arguments = arguments
            self.environment = environment
        }
    }
    
    /// Configuration for remote MCP servers
    public struct RemoteServerConfig: Codable, Sendable {
        public let name: String
        public let url: String
        public let authType: String?
        public let authConfig: JSON?
        public let connectionTimeout: TimeInterval?
        public let requestTimeout: TimeInterval?
        public let maxRetries: Int?
        public let clientID: String?
        
        public init(
            name: String,
            url: String,
            authType: String? = nil,
            authConfig: JSON? = nil,
            connectionTimeout: TimeInterval? = nil,
            requestTimeout: TimeInterval? = nil,
            maxRetries: Int? = nil,
            clientID: String? = nil
        ) {
            self.name = name
            self.url = url
            self.authType = authType
            self.authConfig = authConfig
            self.connectionTimeout = connectionTimeout
            self.requestTimeout = requestTimeout
            self.maxRetries = maxRetries
            self.clientID = clientID
        }
    }
    
    /// Configuration for PKCE OAuth authentication
    public struct PKCEOAuthConfig: Codable, Sendable {
        public let issuerURL: String
        public let clientId: String
        public let clientSecret: String?
        public let scope: String?
        public let redirectURI: String
        public let authorizationEndpoint: String?
        public let tokenEndpoint: String?
        public let useOpenIDConnectDiscovery: Bool
        /// Resource URI for RFC 8707 Resource Indicators (required for MCP clients)
        public let resourceURI: String?
        
        public init(
            issuerURL: String,
            clientId: String,
            clientSecret: String? = nil,
            scope: String? = nil,
            redirectURI: String,
            authorizationEndpoint: String? = nil,
            tokenEndpoint: String? = nil,
            useOpenIDConnectDiscovery: Bool = true,
            resourceURI: String? = nil
        ) {
            self.issuerURL = issuerURL
            self.clientId = clientId
            self.clientSecret = clientSecret
            self.scope = scope
            self.redirectURI = redirectURI
            self.authorizationEndpoint = authorizationEndpoint
            self.tokenEndpoint = tokenEndpoint
            self.useOpenIDConnectDiscovery = useOpenIDConnectDiscovery
            self.resourceURI = resourceURI
        }
    }
    
    /// Configuration for OAuth 2.0 Dynamic Client Registration
    public struct DynamicClientRegistrationConfig: Codable, Sendable {
        /// URL of the authorization server's registration endpoint
        public let registrationEndpoint: String
        
        /// Array of redirection URI strings for use in redirect-based flows
        public let redirectUris: [String]
        
        /// Name of the client to be presented to the end-user
        public let clientName: String?
        
        /// String containing a space-separated list of scope values
        public let scope: String?
        
        /// Initial access token for registration (if required by the server)
        public let initialAccessToken: String?
        
        /// Software statement for registration (if applicable)
        public let softwareStatement: String?
        
        /// Whether to use credential storage for persistence
        public let useCredentialStorage: Bool
        
        /// Timeout for registration requests
        public let requestTimeout: TimeInterval?
        
        /// Additional metadata fields
        public let additionalMetadata: [String: String]?
        
        public init(
            registrationEndpoint: String,
            redirectUris: [String],
            clientName: String? = nil,
            scope: String? = nil,
            initialAccessToken: String? = nil,
            softwareStatement: String? = nil,
            useCredentialStorage: Bool = true,
            requestTimeout: TimeInterval? = nil,
            additionalMetadata: [String: String]? = nil
        ) {
            self.registrationEndpoint = registrationEndpoint
            self.redirectUris = redirectUris
            self.clientName = clientName
            self.scope = scope
            self.initialAccessToken = initialAccessToken
            self.softwareStatement = softwareStatement
            self.useCredentialStorage = useCredentialStorage
            self.requestTimeout = requestTimeout
            self.additionalMetadata = additionalMetadata
        }
        
        /// Creates a Dynamic Client Registration configuration optimized for MCP clients
        /// - Parameters:
        ///   - registrationEndpoint: URL of the authorization server's registration endpoint
        ///   - redirectUris: Array of redirection URI strings
        ///   - clientName: Optional client name (defaults to "MCP Client")
        ///   - scope: Optional scope (defaults to "mcp")
        ///   - additionalMetadata: Optional additional metadata
        /// - Returns: Configuration optimized for MCP clients
        public static func mcpClientConfig(
            registrationEndpoint: String,
            redirectUris: [String],
            clientName: String? = nil,
            scope: String? = nil,
            additionalMetadata: [String: String]? = nil
        ) -> DynamicClientRegistrationConfig {
            var metadata = additionalMetadata ?? [:]
            metadata["mcp_client"] = "true"
            metadata["client_type"] = "native"
            
            return DynamicClientRegistrationConfig(
                registrationEndpoint: registrationEndpoint,
                redirectUris: redirectUris,
                clientName: clientName ?? "MCP Client",
                scope: scope ?? "mcp",
                additionalMetadata: metadata
            )
        }
    }
    
    public var serverBootCalls: [ServerBootCall] = []
    public var remoteServers: [RemoteServerConfig] = []
    public var globalEnvironment: JSON = .object([:])
    
    public init() {}
}

public struct MCPConfigHelper {
    
    public enum ConfigError: Error {
        case invalidMCPConfig
    }
    
    public static func parseMCPConfig(fileURL: URL) throws -> MCPConfig {
        let jsonData = try Data(contentsOf: fileURL)
        
        guard let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            throw ConfigError.invalidMCPConfig
        }
        
        var mcpConfig = MCPConfig()
        if let mcpServers = json["mcpServers"] as? [String: Any] {
            
            var serverBootCalls = [MCPConfig.ServerBootCall]()
            for (name, value) in mcpServers {
                guard let mcpServerConfig = value as? [String: Any] else {
                    continue
                }
                guard let command = mcpServerConfig["command"] as? String else {
                    continue
                }
                let arguments = mcpServerConfig["args"] as? [String] ?? []
                let environment = mcpServerConfig["env"] as? [String: Any] ?? [:]
                let envJson = (try? JSON(environment)) ?? .object([:])
                serverBootCalls.append(MCPConfig.ServerBootCall(name: name, command: command, arguments: arguments, environment: envJson))
            }
            mcpConfig.serverBootCalls = serverBootCalls
        }
        
        if let globalEnvironment = json["globalEnv"] as? [String: Any] {
            mcpConfig.globalEnvironment = (try? JSON(globalEnvironment)) ?? .object([:])
        }
        
        // Parse remote servers configuration
        if let remoteServers = json["remoteServers"] as? [String: Any] {
            var remoteServerConfigs = [MCPConfig.RemoteServerConfig]()
            for (name, value) in remoteServers {
                guard let remoteServerConfig = value as? [String: Any] else {
                    continue
                }
                guard let url = remoteServerConfig["url"] as? String else {
                    continue
                }
                
                let authType = remoteServerConfig["authType"] as? String
                let authConfig = remoteServerConfig["authConfig"] as? [String: Any]
                let connectionTimeout = remoteServerConfig["connectionTimeout"] as? TimeInterval
                let requestTimeout = remoteServerConfig["requestTimeout"] as? TimeInterval
                let maxRetries = remoteServerConfig["maxRetries"] as? Int
                let clientID = remoteServerConfig["clientID"] as? String
                
                let authConfigJson = authConfig != nil ? (try? JSON(authConfig!)) : nil
                
                remoteServerConfigs.append(MCPConfig.RemoteServerConfig(
                    name: name,
                    url: url,
                    authType: authType,
                    authConfig: authConfigJson,
                    connectionTimeout: connectionTimeout,
                    requestTimeout: requestTimeout,
                    maxRetries: maxRetries,
                    clientID: clientID
                ))
            }
            mcpConfig.remoteServers = remoteServerConfigs
        }
        
        return mcpConfig
    }
    
    /// Creates a remote server configuration with Dynamic Client Registration authentication
    /// - Parameters:
    ///   - name: Name of the remote server
    ///   - url: URL of the remote MCP server
    ///   - registrationEndpoint: URL of the authorization server's registration endpoint
    ///   - redirectUris: Array of redirection URI strings
    ///   - clientName: Optional client name (defaults to "MCP Client")
    ///   - scope: Optional scope (defaults to "mcp")
    ///   - initialAccessToken: Optional initial access token for registration
    ///   - softwareStatement: Optional software statement for registration
    ///   - useCredentialStorage: Whether to use credential storage for persistence (defaults to true)
    ///   - connectionTimeout: Optional connection timeout
    ///   - requestTimeout: Optional request timeout
    ///   - maxRetries: Optional maximum number of retries
    ///   - clientID: Optional client ID for OAuth discovery (defaults to "swiftagentkit-mcp-client")
    /// - Returns: Remote server configuration with Dynamic Client Registration
    public static func createRemoteServerWithDynamicClientRegistration(
        name: String,
        url: String,
        registrationEndpoint: String,
        redirectUris: [String],
        clientName: String? = nil,
        scope: String? = nil,
        initialAccessToken: String? = nil,
        softwareStatement: String? = nil,
        useCredentialStorage: Bool = true,
        connectionTimeout: TimeInterval? = nil,
        requestTimeout: TimeInterval? = nil,
        maxRetries: Int? = nil,
        clientID: String? = nil
    ) -> MCPConfig.RemoteServerConfig {
        
        let dynamicClientRegConfig = MCPConfig.DynamicClientRegistrationConfig.mcpClientConfig(
            registrationEndpoint: registrationEndpoint,
            redirectUris: redirectUris,
            clientName: clientName,
            scope: scope
        )
        
        // Convert to JSON for auth config
        let authConfigDict: [String: Any] = [
            "useDynamicClientRegistration": true,
            "registrationEndpoint": dynamicClientRegConfig.registrationEndpoint,
            "redirectUris": dynamicClientRegConfig.redirectUris,
            "clientName": dynamicClientRegConfig.clientName ?? "MCP Client",
            "scope": dynamicClientRegConfig.scope ?? "mcp",
            "initialAccessToken": initialAccessToken ?? "",
            "softwareStatement": softwareStatement ?? "",
            "useCredentialStorage": useCredentialStorage,
            "requestTimeout": requestTimeout ?? 30.0
        ]
        
        let authConfig = try? JSON(authConfigDict)
        
        return MCPConfig.RemoteServerConfig(
            name: name,
            url: url,
            authType: "OAuth",
            authConfig: authConfig,
            connectionTimeout: connectionTimeout,
            requestTimeout: requestTimeout,
            maxRetries: maxRetries,
            clientID: clientID
        )
    }
    
    /// Creates a remote server configuration with Dynamic Client Registration from OAuth server metadata
    /// - Parameters:
    ///   - name: Name of the remote server
    ///   - url: URL of the remote MCP server
    ///   - serverMetadata: OAuth server metadata containing registration endpoint
    ///   - redirectUris: Array of redirection URI strings
    ///   - clientName: Optional client name (defaults to "MCP Client")
    ///   - scope: Optional scope (defaults to "mcp")
    ///   - initialAccessToken: Optional initial access token for registration
    ///   - useCredentialStorage: Whether to use credential storage for persistence (defaults to true)
    ///   - connectionTimeout: Optional connection timeout
    ///   - requestTimeout: Optional request timeout
    ///   - maxRetries: Optional maximum number of retries
    ///   - clientID: Optional client ID for OAuth discovery (defaults to "swiftagentkit-mcp-client")
    /// - Returns: Remote server configuration with Dynamic Client Registration, or nil if registration endpoint not available
    public static func createRemoteServerWithDynamicClientRegistrationFromMetadata(
        name: String,
        url: String,
        serverMetadata: OAuthServerMetadata,
        redirectUris: [String],
        clientName: String? = nil,
        scope: String? = nil,
        initialAccessToken: String? = nil,
        useCredentialStorage: Bool = true,
        connectionTimeout: TimeInterval? = nil,
        requestTimeout: TimeInterval? = nil,
        maxRetries: Int? = nil,
        clientID: String? = nil
    ) -> MCPConfig.RemoteServerConfig? {
        
        guard let registrationEndpoint = serverMetadata.registrationEndpoint else {
            return nil
        }
        
        return createRemoteServerWithDynamicClientRegistration(
            name: name,
            url: url,
            registrationEndpoint: registrationEndpoint,
            redirectUris: redirectUris,
            clientName: clientName,
            scope: scope,
            initialAccessToken: initialAccessToken,
            useCredentialStorage: useCredentialStorage,
            connectionTimeout: connectionTimeout,
            requestTimeout: requestTimeout,
            maxRetries: maxRetries,
            clientID: clientID
        )
    }
}
