//
//  A2AToolProvider.swift
//  SwiftAgentKitAdapters
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitA2A

/// Direct A2A agent tool provider
public struct A2AToolProvider: ToolProvider {
    private let clients: [A2AClient]
    private let logger = Logger(label: "A2AToolProvider")
    
    public var name: String { "A2A Agents" }
    
    public func availableTools() async -> [ToolDefinition] {
        var tools: [ToolDefinition] = []
        for client in clients {
            if let agentCard = await client.agentCard {
                tools.append(ToolDefinition(
                    name: agentCard.name,
                    description: agentCard.description,
                    parameters: [
                        .init(name: "instructions", description: "Issue instructions for this agent to complete a task on your behalf.", type: "string", required: true)
                    ],
                    type: .a2aAgent
                ))
            }
        }
        return tools
    }
    
    public init(clients: [A2AClient]) {
        self.clients = clients
    }
    
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        for client in clients {
            // Check if this client has the requested agent
            guard let agentCard = await client.agentCard,
                  agentCard.name == toolCall.name else { continue }
            
            let a2aMessage = A2AMessage(
                role: "user",
                parts: [.text(text: toolCall.arguments["instructions"] as? String ?? "")],
                messageId: UUID().uuidString
            )
            let params = MessageSendParams(message: a2aMessage)
            
            do {
                let result = try await client.sendMessage(params: params)
                switch result {
                case .message(let message):
                    let content = message.parts.compactMap { part in
                        if case .text(let text) = part { return text } else { return nil }
                    }.joined(separator: " ")
                    return ToolResult(
                        success: true,
                        content: content,
                        metadata: .object(["source": .string("a2a_agent")])
                    )
                case .task(let task):
                    if let message = task.status.message {
                        let content = message.parts.compactMap { part in
                            if case .text(let text) = part { return text } else { return nil }
                        }.joined(separator: " ")
                        return ToolResult(
                            success: true,
                            content: content,
                            metadata: .object(["source": .string("a2a_agent")])
                        )
                    }
                default:
                    continue
                }
            } catch {
                logger.warning("A2A client call failed: \(error)")
                continue
            }
        }
        
        return ToolResult(
            success: false,
            content: "",
            error: "A2A agent not found or failed"
        )
    }
} 
