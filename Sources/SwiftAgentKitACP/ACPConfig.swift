//
//  ACPConfig.swift
//  SwiftAgentKitACP
//

import EasyJSON
import Foundation

public struct ACPConfig: Sendable {
    public struct ServerBootCall: Decodable, Sendable {
        public let name: String
        public let command: String
        public let arguments: [String]
        public let environment: JSON
        public let useShell: Bool
        public let toolCallTimeout: TimeInterval?

        public init(
            name: String,
            command: String,
            arguments: [String],
            environment: JSON,
            useShell: Bool = false,
            toolCallTimeout: TimeInterval? = nil
        ) {
            self.name = name
            self.command = command
            self.arguments = arguments
            self.environment = environment
            self.useShell = useShell
            self.toolCallTimeout = toolCallTimeout
        }

        enum CodingKeys: String, CodingKey {
            case name, command, arguments, environment, useShell, toolCallTimeout
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            command = try c.decode(String.self, forKey: .command)
            arguments = try c.decode([String].self, forKey: .arguments)
            environment = try c.decode(JSON.self, forKey: .environment)
            useShell = try c.decodeIfPresent(Bool.self, forKey: .useShell) ?? false
            toolCallTimeout = try c.decodeIfPresent(TimeInterval.self, forKey: .toolCallTimeout)
        }
    }

    public var agentBootCalls: [ServerBootCall] = []
    public var globalEnvironment: JSON = .object([:])
    public var toolCallTimeout: TimeInterval? = nil
}

public struct ACPConfigHelper {
    public enum ConfigError: Error {
        case invalidACPConfig
    }

    public static func parseACPConfig(fileURL: URL) throws -> ACPConfig {
        let jsonData = try Data(contentsOf: fileURL)
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ConfigError.invalidACPConfig
        }

        var config = ACPConfig()

        if let timeout = json["toolCallTimeout"] as? TimeInterval {
            config.toolCallTimeout = timeout
        } else if let timeout = json["toolCallTimeout"] as? Int {
            config.toolCallTimeout = TimeInterval(timeout)
        }

        if let globalEnv = json["globalEnvironment"] as? [String: Any] {
            config.globalEnvironment = try JSON(globalEnv)
        }

        if let bootCalls = json["agentBootCalls"] as? [[String: Any]] {
            let bootData = try JSONSerialization.data(withJSONObject: bootCalls)
            config.agentBootCalls = try JSONDecoder().decode([ACPConfig.ServerBootCall].self, from: bootData)
        }

        return config
    }
}
