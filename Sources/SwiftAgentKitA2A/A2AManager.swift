//
//  A2AManager.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 6/19/25.
//

import Foundation
import SwiftAgentKit

public actor A2AManager {
    public init() {}
    
    public enum State {
        case notReady
        case initialized
    }
    
    public var state: State = .notReady
    public var toolCallsJsonString: String?
    public var toolCallsJson: [[String: Any]] = []
    
    /// Initialize the A2AManager with a config file URL
    public func initialize(configFileURL: URL) async throws {
        do {
            try await loadA2AConfiguration(configFileURL: configFileURL)
        } catch {
            print("\(error)")
        }
    }
    
    public func agentCall(_ toolCall: ToolCall) async throws -> [Message]? {
        for client in clients {
            guard let instructions: String = toolCall.arguments["instructions"] as? String else { continue }
            let a2aMessage = A2AMessage(role: "assistant", parts: [.text(text: instructions)], messageId: UUID().uuidString)
            let params: MessageSendParams = .init(message: a2aMessage)
            let contents = try await client.streamMessage(params: params)
            var returnMessages: [Message] = []
            for await content in contents {
                switch content.result {
                case .message(let aMessage):
                    let text = aMessage.parts.compactMap({ if case .text(let text) = $0, !text.isEmpty { return text } else { return nil }}).joined(separator: " ")
                    returnMessages.append(Message(id: UUID(), role: .tool, content: text))
                default:
                    continue
                }
            }
            return returnMessages
        }
        return nil
    }
    
    // MARK: - Private
    
    private var clients: [A2AClient] = []
    
    private func loadA2AConfiguration(configFileURL: URL) async throws {
        do {
            let config = try A2AConfigHelper.parseA2AConfig(fileURL: configFileURL)
            try await createClients(config)
            state = .initialized
        } catch {
            print("Error loading A2A configuration: \(error)")
            state = .notReady
        }
    }
    
    private func createClients(_ config: A2AConfig) async throws {
        for server in config.servers {
            let bootCall = config.serverBootCalls.first(where: { $0.name == server.name })
            let client = A2AClient(server: server, bootCall: bootCall)
            try await client.initializeA2AClient(globalEnvironment: config.globalEnvironment)
            clients.append(client)
        }
        await buildToolsJson()
    }
    
    private func buildToolsJson() async {
        var json: [[String: Any]] = []
        for client in clients {
            guard let agentCard = await client.agentCard else { continue }
            json.append(agentCard.toolCallJson())
        }
        toolCallsJson = json
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            toolCallsJsonString = String(data: data, encoding: .utf8)
        }
    }
}

extension AgentCard.AgentSkill {
    func toJson() -> [String: Any] {
        var returnValue: [String: Any] = [
            "name": name,
            "description": description,
            "tags": tags,
        ]
        if let inputModes = inputModes {
            returnValue["input-modes"] = inputModes
        }
        if let outputModes = outputModes {
            returnValue["output-modes"] = outputModes
        }
        return returnValue
    }
}

extension AgentCard {
     func toolCallJson() -> [String: Any] {
         var returnValue: [String: Any] = [:]
         returnValue[name] = [
            "description": description,
            "skills": skills.map({$0.toJson()}),
         ]
         return returnValue
    }
}
