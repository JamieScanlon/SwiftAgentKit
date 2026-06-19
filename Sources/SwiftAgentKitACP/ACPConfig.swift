//
//  ACPConfig.swift
//  SwiftAgentKitACP
//

import EasyJSON
import Foundation

public struct ACPConfig: Sendable {
    public enum RemoteTransport: String, Decodable, Sendable {
        case websocket
        case streamableHTTP = "streamable_http"
    }

    public struct RemoteAuth: Decodable, Sendable {
        public let bearerToken: String?

        public init(bearerToken: String? = nil) {
            self.bearerToken = bearerToken
        }
    }

    public struct ServerBootCall: Decodable, Sendable {
        public let name: String
        public let command: String?
        public let arguments: [String]
        public let environment: JSON
        public let useShell: Bool
        public let toolCallTimeout: TimeInterval?
        /// When true, the booted client advertises `clientCapabilities.terminal` during `initialize`.
        public let advertiseTerminal: Bool
        /// Remote agent URL (mutually exclusive with `command` for stdio boot).
        public let url: String?
        /// Remote transport profile when `url` is set (defaults to `websocket`).
        public let transport: RemoteTransport?
        public let auth: RemoteAuth?

        public init(
            name: String,
            command: String? = nil,
            arguments: [String] = [],
            environment: JSON = .object([:]),
            useShell: Bool = false,
            toolCallTimeout: TimeInterval? = nil,
            advertiseTerminal: Bool = false,
            url: String? = nil,
            transport: RemoteTransport? = nil,
            auth: RemoteAuth? = nil
        ) {
            self.name = name
            self.command = command
            self.arguments = arguments
            self.environment = environment
            self.useShell = useShell
            self.toolCallTimeout = toolCallTimeout
            self.advertiseTerminal = advertiseTerminal
            self.url = url
            self.transport = transport
            self.auth = auth
        }

        enum CodingKeys: String, CodingKey {
            case name, command, arguments, environment, useShell, toolCallTimeout, advertiseTerminal
            case url, transport, auth
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            command = try c.decodeIfPresent(String.self, forKey: .command)
            arguments = try c.decodeIfPresent([String].self, forKey: .arguments) ?? []
            environment = try c.decodeIfPresent(JSON.self, forKey: .environment) ?? .object([:])
            useShell = try c.decodeIfPresent(Bool.self, forKey: .useShell) ?? false
            toolCallTimeout = try c.decodeIfPresent(TimeInterval.self, forKey: .toolCallTimeout)
            advertiseTerminal = try c.decodeIfPresent(Bool.self, forKey: .advertiseTerminal) ?? false
            url = try c.decodeIfPresent(String.self, forKey: .url)
            transport = try c.decodeIfPresent(RemoteTransport.self, forKey: .transport)
            auth = try c.decodeIfPresent(RemoteAuth.self, forKey: .auth)
        }
    }

    public var agentBootCalls: [ServerBootCall] = []
    public var globalEnvironment: JSON = .object([:])
    public var toolCallTimeout: TimeInterval? = nil
    /// MCP server descriptors forwarded to ACP agents at `session/new` when clients are booted from config.
    public var mcpBootServers: [ACPMcpServer] = []
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

        if let mcpBootServers = json["mcpBootServers"] as? [[String: Any]] {
            let mcpData = try JSONSerialization.data(withJSONObject: mcpBootServers)
            config.mcpBootServers = try JSONDecoder().decode([ACPMcpServer].self, from: mcpData)
        }

        return config
    }
}
