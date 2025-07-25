//
//  MCPConfig.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 4/12/25.
//

import EasyJSON
import Foundation

public struct MCPConfig: Decodable, Sendable {
    
    public struct ServerBootCall: Decodable, Sendable {
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
    
    public var serverBootCalls: [ServerBootCall] = []
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
        return mcpConfig
    }
}
