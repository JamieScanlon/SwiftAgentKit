//
//  A2AConfig.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 6/19/25.
//

import EasyJSON
import Foundation

public struct A2AConfig: Sendable {
    
    public struct A2AConfigServer: Sendable {
        var name: String
        var url: URL
        var token: String?
        var apiKey: String?
    }
    
    public struct ServerBootCall: Decodable, Sendable {
        public let name: String
        public let command: String
        public let arguments: [String]
        public let environment: JSON
        /// When `true`, runs through a shell (`cmd /c` on Windows, `zsh -c` on macOS). Default is direct `/usr/bin/env`-style launch on Unix.
        public let useShell: Bool

        public init(name: String, command: String, arguments: [String], environment: JSON, useShell: Bool = false) {
            self.name = name
            self.command = command
            self.arguments = arguments
            self.environment = environment
            self.useShell = useShell
        }

        enum CodingKeys: String, CodingKey {
            case name, command, arguments, environment, useShell
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            command = try c.decode(String.self, forKey: .command)
            arguments = try c.decode([String].self, forKey: .arguments)
            environment = try c.decode(JSON.self, forKey: .environment)
            useShell = try c.decodeIfPresent(Bool.self, forKey: .useShell) ?? false
        }
    }
    
    public var servers: [A2AConfigServer] = []
    public var serverBootCalls: [ServerBootCall] = []
    public var globalEnvironment: JSON = .object([:])
}

public struct A2AConfigHelper {
    
    public enum ConfigError: Error {
        case invalidA2AConfig
    }
    
    public static func parseA2AConfig(fileURL: URL) throws -> A2AConfig {
        let jsonData = try Data(contentsOf: fileURL)
        
        guard let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            throw ConfigError.invalidA2AConfig
        }
        
        var a2aConfig = A2AConfig()
        if let a2aServers = json["a2aServers"] as? [String: Any] {
            
            var serverBootCalls = [A2AConfig.ServerBootCall]()
            var servers = [A2AConfig.A2AConfigServer]()
            
            for (name, value) in a2aServers {
                guard let a2aServerConfig = value as? [String: Any] else {
                    continue
                }
                if let bootConfig = a2aServerConfig["boot"] as? [String: Any], let command = bootConfig["command"] as? String {
                    let arguments = bootConfig["args"] as? [String] ?? []
                    let environment = bootConfig["env"] as? [String: Any] ?? [:]
                    let envJson = (try? JSON(environment)) ?? .object([:])
                    let useShell = bootConfig["useShell"] as? Bool ?? false
                    serverBootCalls.append(A2AConfig.ServerBootCall(name: name, command: command, arguments: arguments, environment: envJson, useShell: useShell))
                }
                if let runConfig = a2aServerConfig["run"] as? [String: Any], let urlString = runConfig["url"] as? String, let url = URL(string: urlString)  {
                    let token = runConfig["token"] as? String
                    let apiKey = runConfig["api_key"] as? String
                    servers.append(.init(name: name, url: url, token: token, apiKey: apiKey))
                }
            }
            a2aConfig.servers = servers
            a2aConfig.serverBootCalls = serverBootCalls
        }
        
        if let globalEnvironment = json["globalEnv"] as? [String: Any] {
            a2aConfig.globalEnvironment = (try? JSON(globalEnvironment)) ?? .object([:])
        }
        
        return a2aConfig
    }
}
