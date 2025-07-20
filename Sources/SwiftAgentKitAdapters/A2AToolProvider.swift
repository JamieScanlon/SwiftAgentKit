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
    
    public var availableTools: [ToolDefinition] {
        clients.compactMap { client in
            // TODO: We need to make agentCard accessible from A2AClient
            // For now, this is a placeholder implementation
            guard let agentCard = await client.agentCard else { return nil }
            return ToolDefinition(
                name: agentCard.name,
                description: agentCard.description,
                type: .a2aAgent
            )
        }
    }
    
    public init(clients: [A2AClient]) {
        self.clients = clients
    }
    
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        for client in clients {
            // TODO: We need to make agentCard accessible from A2AClient
            guard let agentCard = await client.agentCard,
                  agentCard.name == toolCall.name else { continue }
            
            let a2aMessage = A2AMessage(
                role: "user",
                parts: [.text(text: toolCall.arguments["input"] as? String ?? "")],
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