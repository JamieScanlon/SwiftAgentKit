//
//  ACPToolProvider.swift
//  SwiftAgentKitAdapters
//

import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitACP

/// Direct ACP agent tool provider.
public struct ACPToolProvider: ToolProvider {
    private let clients: [ACPClient]
    private let logger: Logger

    public var name: String { "ACP Agents" }

    public init(clients: [ACPClient], logger: Logger? = nil) {
        self.clients = clients
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .adapters("ACPToolProvider"),
            metadata: SwiftAgentKitLogging.metadata(
                ("clientCount", .stringConvertible(clients.count))
            )
        )
    }

    public func availableTools() async -> [ToolDefinition] {
        var tools: [ToolDefinition] = []
        for client in clients {
            guard let info = await client.agentInfo else { continue }
            tools.append(ToolDefinition(
                name: info.name,
                description: info.title ?? "ACP agent \(info.name)",
                parameters: [
                    .init(name: "instructions", description: "Instructions for this ACP agent.", type: "string", required: true)
                ],
                type: .acpAgent
            ))
        }
        return tools
    }

    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        let outcome = try await executeToolOutcome(toolCall)
        switch outcome {
        case .completed(let result):
            return result
        case .pending(let handle):
            return ToolResult(
                success: true,
                content: "Accepted by ACP agent (handle: \(handle.handleID)).",
                metadata: .object([
                    "source": .string("acp_agent"),
                    "pendingHandleID": .string(handle.handleID),
                    "status": .string("pending")
                ]),
                toolCallId: toolCall.id
            )
        }
    }

    public func executeToolOutcome(_ toolCall: ToolCall) async throws -> ToolExecutionOutcome {
        for client in clients {
            guard let info = await client.agentInfo,
                  info.name == toolCall.name else { continue }

            guard case .object(let argsDict) = toolCall.arguments,
                  case .string(let instructions) = argsDict["instructions"] else {
                continue
            }

            do {
                let (response, updates) = try await client.prompt(instructions)
                var text = ""
                for await update in updates {
                    if case .agentMessageChunk(_, let content) = update,
                       case .text(let chunk) = content {
                        text += chunk
                    }
                }
                if text.isEmpty {
                    text = "ACP agent completed with stop reason: \(response.stopReason.rawValue)"
                }
                return .completed(ToolResult(
                    success: true,
                    content: text,
                    metadata: .object(["source": .string("acp_agent")]),
                    toolCallId: toolCall.id
                ))
            } catch {
                logger.warning(
                    "ACP client call failed",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("toolName", .string(toolCall.name)),
                        ("error", .string(String(describing: error)))
                    )
                )
                continue
            }
        }

        return .completed(ToolResult(
            success: false,
            content: "",
            toolCallId: toolCall.id,
            error: "ACP agent not found or failed"
        ))
    }

    public func effectClass(for definition: ToolDefinition) async -> ToolEffectClass {
        .mutating
    }

    public func executionParallelHint(for definition: ToolDefinition) async -> ToolExecutionParallelHint {
        .serialOnly
    }

    public func registrationSource(for definition: ToolDefinition) async -> ToolRegistrationSource {
        .acp
    }
}
