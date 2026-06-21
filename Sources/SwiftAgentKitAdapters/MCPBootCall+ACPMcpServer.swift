//
//  MCPBootCall+ACPMcpServer.swift
//  SwiftAgentKitAdapters
//

import EasyJSON
import SwiftAgentKitACP
import SwiftAgentKitMCP

public extension MCPConfig.ServerBootCall {
    /// Converts a local stdio MCP boot descriptor into an ACP `session/new` MCP server entry.
    func toACPMcpServer() -> ACPMcpServer {
        ACPMcpServer(
            name: name,
            command: command,
            arguments: arguments,
            environment: environment.acpEnvironment
        )
    }
}

/// Builds a provider that maps local MCP boot calls to ACP session MCP servers (ignores `cwd`).
public func acpSessionMcpServersProvider(
    fromLocalBootCalls calls: [MCPConfig.ServerBootCall]
) -> ACPSessionMcpServersProvider {
    { _ in calls.map { $0.toACPMcpServer() } }
}

private extension JSON {
    var acpEnvironment: [String: String] {
        guard case .object(let dict) = self else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in dict {
            if case .string(let str) = value {
                result[key] = str
            }
        }
        return result
    }
}
