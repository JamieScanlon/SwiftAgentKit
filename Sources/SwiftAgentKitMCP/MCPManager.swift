//
//  MCPManager.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 4/12/25.
//

import Foundation
import MCP
import SwiftAgentKit

/// Manages tool calling via MCP
/// Loads a configuration of available MCP servers
/// Creates a MCPClient for every available server
/// Dispatches tool calls to clients
public actor MCPManager {
    public init() {}
    
    public enum State {
        case notReady
        case initialized
    }
    
    public var state: State = .notReady
    public var toolCallsJsonString: String?
    public var toolCallsJson: [[String: Any]] = []
    
    /// Initialize the MCPManager with a config file URL
    public func initialize(configFileURL: URL) async throws {
        do {
            try await loadMCPConfiguration(configFileURL: configFileURL)
        } catch {
            print("\(error)")
        }
    }
    
    public func toolCall(_ toolCall: ToolCall) async throws -> [SwiftAgentKit.Message]? {
        for client in clients {
            if let contents = try await client.callTool(toolCall.name, arguments: toolCall.argumentsToValue()) {
                var returnMessages: [SwiftAgentKit.Message] = []
                for content in contents {
                    switch content {
                    case .text(let text):
                        returnMessages.append(Message(id: UUID(), role: .tool, content: text))
                    default:
                        continue
                    }
                }
                return returnMessages
            }
        }
        return nil
    }
    
    // MARK: - Private
    
    private var clients: [MCPClient] = []
    
    private func loadMCPConfiguration(configFileURL: URL) async throws {
        do {
            let config = try MCPConfigHelper.parseMCPConfig(fileURL: configFileURL)
            try await createClients(config)
            state = .initialized
        } catch {
            print("Error loading MCP configuration: \(error)")
            state = .notReady
        }
    }
    
    private func createClients(_ config: MCPConfig) async throws {
        for server in config.serverBootCalls {
            let client = MCPClient(bootCall: server, version: "0.1.3")
            try await client.initializeMCPClient(config: config)
            try await client.getTools()
            clients.append(client)
        }
        await buildToolsJson()
    }
    
    private func buildToolsJson() async {
        var json: [[String: Any]] = []
        for client in clients {
            for tool in await client.tools {
                json.append(tool.toolCallJson())
            }
        }
        toolCallsJson = json
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            toolCallsJsonString = String(data: data, encoding: .utf8)
        }
    }
    
}

extension Tool {
    
    func toolCallJson() -> [String: Any] {
        var returnValue: [String: Any] = ["type": "function"]
        var properties: [String: Any] = [:]
        var required: [String] = []
        if let paramsObject: [String: Value] = inputSchema?.objectValue {
            if let propertiesObject = paramsObject["properties"]?.objectValue as? [String: Value] {
                for (key, value) in propertiesObject {
                    properties[key] = ["type": value.objectValue?["type"]?.stringValue ?? "string", "description": value.objectValue?["description"]?.stringValue ?? ""]
                    required.append(key)
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
    func argumentsToValue() -> [String: Value] {
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
