//
//  MCPConfig.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 4/12/25.
//

import EasyJSON
import Foundation

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
        
        public init(
            name: String,
            url: String,
            authType: String? = nil,
            authConfig: JSON? = nil,
            connectionTimeout: TimeInterval? = nil,
            requestTimeout: TimeInterval? = nil,
            maxRetries: Int? = nil
        ) {
            self.name = name
            self.url = url
            self.authType = authType
            self.authConfig = authConfig
            self.connectionTimeout = connectionTimeout
            self.requestTimeout = requestTimeout
            self.maxRetries = maxRetries
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
                
                let authConfigJson = authConfig != nil ? (try? JSON(authConfig!)) : nil
                
                remoteServerConfigs.append(MCPConfig.RemoteServerConfig(
                    name: name,
                    url: url,
                    authType: authType,
                    authConfig: authConfigJson,
                    connectionTimeout: connectionTimeout,
                    requestTimeout: requestTimeout,
                    maxRetries: maxRetries
                ))
            }
            mcpConfig.remoteServers = remoteServerConfigs
        }
        
        return mcpConfig
    }
}
