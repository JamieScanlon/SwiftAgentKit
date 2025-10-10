//
//  ToolAwareAdapter.swift
//  SwiftAgentKitAdapters
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitA2A

/// Enhanced adapter that can use tools while keeping the base adapter unchanged
public struct ToolProxyAdapter: AgentAdapter {
    private let baseAdapter: AgentAdapter
    private let toolManager: ToolManager?
    private let logger = Logger(label: "ToolAwareAdapter")
    
    public init(
        baseAdapter: AgentAdapter,
        toolManager: ToolManager? = nil
    ) {
        self.baseAdapter = baseAdapter
        self.toolManager = toolManager
    }
    
    // MARK: - AgentAdapter Implementation
    
    public var cardCapabilities: AgentCard.AgentCapabilities {
        baseAdapter.cardCapabilities
    }
    
    public var skills: [AgentCard.AgentSkill] {
        baseAdapter.skills
    }
    
    public var agentName: String {
        baseAdapter.agentName
    }
    
    public var agentDescription: String {
        baseAdapter.agentDescription
    }
    
    public var defaultInputModes: [String] { baseAdapter.defaultInputModes }
    public var defaultOutputModes: [String] { baseAdapter.defaultOutputModes }
    
    public func responseType(for params: MessageSendParams) -> AdapterResponseType {
        return baseAdapter.responseType(for: params)
    }
    
    public func handleMessageSend(_ params: MessageSendParams) async throws -> A2AMessage {
        guard let toolManager = toolManager else {
            // No tools available, use base adapter
            return try await baseAdapter.handleMessageSend(params)
        }
        
        // For now, delegate to base adapter
        // TODO: Add tool support for message responses
        return try await baseAdapter.handleMessageSend(params)
    }
    
    public func handleTaskSend(_ params: MessageSendParams, taskId: String, contextId: String, store: TaskStore) async throws {
        
        guard let toolManager = toolManager else {
            // No tools available, use base adapter
            return try await baseAdapter.handleTaskSend(params, taskId: taskId, contextId: contextId, store: store)
        }
        
        logger.info("Processing message with tool support")
        
        // Check if base adapter supports tool-aware methods
        if let toolAwareAdapter = baseAdapter as? ToolAwareAdapter {
            
            // Get available tools for context
            let availableTools = await toolManager.allToolsAsync()
            logger.info("Available tools: \(availableTools.map(\.name))")
            
            // Process with base adapter using tool-aware method
            try await toolAwareAdapter.handleTaskSendWithTools(params, taskId: taskId, contextId: contextId, toolProviders: toolManager.providers, store: store)
            
        } else {
            // Non-tool-aware adapter, just use the plain message without tool functionality
            logger.info("Base adapter does not support tool-aware methods, using plain message")
            return try await baseAdapter.handleTaskSend(params, taskId: taskId, contextId: contextId, store: store)
        }
    }
    
    public func handleStream(_ params: MessageSendParams, taskId: String?, contextId: String?, store: TaskStore?, eventSink: @escaping (Encodable) -> Void) async throws {
        guard let toolManager = toolManager else {
            // No tools available, use base adapter
            try await baseAdapter.handleStream(params, taskId: taskId, contextId: contextId, store: store, eventSink: eventSink)
            return
        }
        
        logger.info("Processing streaming message with tool support")
        
        // Get available tools for context
        let availableTools = await toolManager.allToolsAsync()
        logger.info("Available tools: \(availableTools.map(\.name))")
        
        // Check if base adapter supports tool-aware methods
        if let toolAwareAdapter = baseAdapter as? ToolAwareAdapter {
            // Tool-aware streaming requires task tracking
            guard let taskId = taskId, let contextId = contextId, let store = store else {
                throw NSError(domain: "ToolProxyAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tool-aware streaming requires task tracking"])
            }
            
            // Use the tool-aware streaming method
            try await toolAwareAdapter.handleStreamWithTools(params, taskId: taskId, contextId: contextId, toolProviders: toolManager.providers, store: store, eventSink: eventSink)
        } else {
            // Non-tool-aware adapter, just use the plain message without tool functionality
            logger.info("Base adapter does not support tool-aware methods, using plain message")
            try await baseAdapter.handleStream(params, taskId: taskId, contextId: contextId, store: store, eventSink: eventSink)
        }
    }
}

extension ToolCall {
    
    public static func processResponseForToolCalls(_ messageParts: [A2AMessagePart], availableTools: [String] = []) async -> ([A2AMessagePart], [ToolCall]) {
        var toolCalls: [ToolCall] = []
        var processedParts: [A2AMessagePart] = []

        // Process each part to extract tool calls and build processed parts
        for part in messageParts {
            switch part {
            case .text(let text):
                // Process text parts for embedded tool calls (legacy format)
                let (processedText, toolCallString) = ToolCall.parseToolCallFromString(content: text, availableTools: availableTools)

                // Add processed text if not empty
                if !processedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    processedParts.append(.text(text: processedText))
                }

                // Parse any tool calls found in text
                if let toolCallString = toolCallString,
                   let toolCall = ToolCall.parse(toolCallString) {
                    toolCalls.append(toolCall)
                }

            case .data(let data):
                // Process data parts for tool calls (new format)
                if let toolCall = ToolCall.parseToolCallFromData(data) {
                    toolCalls.append(toolCall)
                } else {
                    // If it's not a tool call, preserve the data part
                    processedParts.append(part)
                }

            case .file:
                // Preserve file parts as-is
                processedParts.append(part)
            }
        }

        // Ensure we have at least one text part if we have tool calls but no text
        if toolCalls.count > 0 && !processedParts.contains(where: { if case .text = $0 { return true } else { return false } }) {
            processedParts.insert(.text(text: ""), at: 0)
        }

        return (processedParts, toolCalls)
    }
}

extension LLMResponse {
    
    /// A helper method for extracting a `ToolCall` from message content.
    /// This method uses `ToolCall.parseToolCallFromString()` to look for tool calls within a message string.
    /// - Parameters:
    ///   - from: Raw message content from the LLM response.
    ///   - availableTools: An array of available tools. This should be the same list of available tools used in the `LLMRequestConfig` when the originalt message was sent to the LLM
    /// - Returns: An `LLMResponse`
    public static func llmResponse(from content: String, availableTools: [ToolDefinition]) -> LLMResponse {
        var toolCalls: [ToolCall] = []
        let (processedText, toolCallString) = ToolCall.parseToolCallFromString(content: content, availableTools: availableTools.map({$0.name}))
        
        // Parse any tool calls found in text
        if let toolCallString, let toolCall = ToolCall.parse(toolCallString) {
            toolCalls.append(toolCall)
        }
        
        let response = LLMResponse(content: processedText, toolCalls: toolCalls)
        return response
    }
}
