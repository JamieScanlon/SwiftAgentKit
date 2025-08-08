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
    
    public init() {}
    
    public enum State {
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
        // Use MCPServerManager to boot servers
        let serverManager = MCPServerManager()
        let serverPipes = try await serverManager.bootServers(config: config)
        
        // Create clients for each server
        for (serverName, pipes) in serverPipes {
            let client = MCPClient(name: serverName, version: "0.1.3")
            try await client.connect(inPipe: pipes.inPipe, outPipe: pipes.outPipe)
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
