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

/// Enhanced protocol that extends AgentAdapter with tool-aware methods
/// This protocol allows adapters to natively support tool calling without
/// requiring the ToolAwareAdapter wrapper.
public protocol ToolAwareAgentAdapter: AgentAdapter {
    /// Handle a message with available tools
    /// - Parameters:
    ///   - params: The message parameters
    ///   - availableToolCalls: Array of tool calls to be made
    ///   - store: The task store
    /// - Returns: An A2A task representing the response
    func handleSendWithTools(_ params: MessageSendParams, availableToolCalls: [ToolDefinition], store: TaskStore) async throws -> A2ATask
    
    /// Handle streaming with available tools
    /// - Parameters:
    ///   - params: The message parameters
    ///   - availableToolCalls: Array of tool calls to be made
    ///   - store: The task store
    ///   - eventSink: Callback for streaming events
    func handleStreamWithTools(_ params: MessageSendParams, availableToolCalls: [ToolDefinition], store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws
}

/// Enhanced adapter that can use tools while keeping the base adapter unchanged
public struct ToolAwareAdapter: AgentAdapter {
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
    
    public var defaultInputModes: [String] { baseAdapter.defaultInputModes }
    public var defaultOutputModes: [String] { baseAdapter.defaultOutputModes }
    
    public func handleSend(_ params: MessageSendParams, store: TaskStore) async throws -> A2ATask {
        guard let toolManager = toolManager else {
            // No tools available, use base adapter
            return try await baseAdapter.handleSend(params, store: store)
        }
        
        logger.info("Processing message with tool support")
        
        // Get available tools for context
        let availableTools = await toolManager.allToolsAsync()
        logger.info("Available tools: \(availableTools.map(\.name))")
        
        // Check if base adapter supports tool-aware methods
        if let toolAwareAdapter = baseAdapter as? ToolAwareAgentAdapter {
            
            // Process with base adapter using tool-aware method
            var task = try await toolAwareAdapter.handleSendWithTools(params, availableToolCalls: availableTools, store: store)
            
            // Check if the response contains tool calls
            if let responseMessage = task.status.message {
                let availableToolNames = availableTools.map { $0.name }
                let (processedMessage, toolCalls) = await processResponseForToolCalls(responseMessage, availableTools: availableToolNames)
                
                if !toolCalls.isEmpty {
                    logger.info("Detected \(toolCalls.count) tool calls in response")
                    
                    // Execute tool calls and get results
                    let toolResults = await executeToolCalls(toolCalls, toolManager: toolManager)
                    
                    // Create follow-up message with tool results
                    let followUpParams = createFollowUpMessage(params, toolResults: toolResults)
                    
                    // Get final response from LLM with tool results
                    let finalTask = try await toolAwareAdapter.handleSendWithTools(followUpParams, availableToolCalls: availableTools, store: store)
                    
                    // Combine the original task with the final response
                    task = finalTask
                } else {
                    // No tool calls, update task with processed message
                    var updatedTask = task
                    updatedTask.status.message = processedMessage
                    task = updatedTask
                }
            }
            
            return task
        } else {
            // Non-tool-aware adapter, just use the plain message without tool functionality
            logger.info("Base adapter does not support tool-aware methods, using plain message")
            return try await baseAdapter.handleSend(params, store: store)
        }
    }
    
    public func handleStream(_ params: MessageSendParams, store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws {
        guard let toolManager = toolManager else {
            // No tools available, use base adapter
            try await baseAdapter.handleStream(params, store: store, eventSink: eventSink)
            return
        }
        
        logger.info("Processing streaming message with tool support")
        
        // Get available tools for context
        let availableTools = await toolManager.allToolsAsync()
        logger.info("Available tools: \(availableTools.map(\.name))")
        
        // Check if base adapter supports tool-aware methods
        if let toolAwareAdapter = baseAdapter as? ToolAwareAgentAdapter {
            
            // Use the tool-aware streaming method
            try await toolAwareAdapter.handleStreamWithTools(params, availableToolCalls: availableTools, store: store, eventSink: eventSink)
        } else {
            // Non-tool-aware adapter, just use the plain message without tool functionality
            logger.info("Base adapter does not support tool-aware methods, using plain message")
            try await baseAdapter.handleStream(params, store: store, eventSink: eventSink)
        }
    }
    
    // MARK: - Internal Helper Methods
    
    public func processResponseForToolCalls(_ message: A2AMessage, availableTools: [String] = []) async -> (A2AMessage, [ToolCall]) {
        var toolCalls: [ToolCall] = []
        var processedParts: [A2AMessagePart] = []
        
        // Process each part to extract tool calls and build processed parts
        for part in message.parts {
            switch part {
            case .text(let text):
                // Process text parts for embedded tool calls (legacy format)
                let (processedText, toolCallString) = ToolCall.processModelResponse(content: text, availableTools: availableTools)
                
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
                if let toolCall = parseToolCallFromData(data) {
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
        
        let processedMessage = A2AMessage(
            role: message.role,
            parts: processedParts,
            messageId: message.messageId,
            taskId: message.taskId,
            contextId: message.contextId
        )
        
        return (processedMessage, toolCalls)
    }
    
    /// Parses tool call data from JSON format to ToolCall object
    private func parseToolCallFromData(_ data: Data) -> ToolCall? {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let _ = dict["id"] as? String,
              let type = dict["type"] as? String,
              type == "function",
              let functionDict = dict["function"] as? [String: Any],
              let name = functionDict["name"] as? String,
              let argumentsString = functionDict["arguments"] as? String else {
            return nil
        }
        
        // Parse the arguments JSON string into a dictionary
        guard let argumentsData = argumentsString.data(using: .utf8),
              let argumentsDict = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] else {
            return nil
        }
        
        // Convert the arguments to the expected format
        var toolCallArguments: [String: Sendable] = [:]
        for (key, value) in argumentsDict {
            if let stringValue = value as? String {
                toolCallArguments[key] = stringValue
            } else if let numberValue = value as? NSNumber {
                toolCallArguments[key] = numberValue
            } else if let boolValue = value as? Bool {
                toolCallArguments[key] = boolValue
            } else if let arrayValue = value as? [String] {
                toolCallArguments[key] = arrayValue
            } else if let dictValue = value as? [String: String] {
                toolCallArguments[key] = dictValue
            } else if let intValue = value as? Int {
                toolCallArguments[key] = intValue
            } else if let doubleValue = value as? Double {
                toolCallArguments[key] = doubleValue
            }
        }
        
        return ToolCall(name: name, arguments: toolCallArguments)
    }
    
    internal func executeToolCalls(_ toolCalls: [ToolCall], toolManager: ToolManager) async -> [ToolResult] {
        var results: [ToolResult] = []
        
        for toolCall in toolCalls {
            do {
                logger.info("Executing tool: \(toolCall.name) with arguments: \(toolCall.arguments)")
                let result = try await toolManager.executeTool(toolCall)
                results.append(result)
                
                if result.success {
                    logger.info("Tool \(toolCall.name) executed successfully")
                } else {
                    logger.warning("Tool \(toolCall.name) failed: \(result.error ?? "Unknown error")")
                }
            } catch {
                logger.error("Error executing tool call '\(toolCall.name)': \(error)")
                results.append(ToolResult(
                    success: false,
                    content: "",
                    error: "Execution error: \(error.localizedDescription)"
                ))
            }
        }
        
        return results
    }
    
    internal func createFollowUpMessage(_ originalParams: MessageSendParams, toolResults: [ToolResult]) -> MessageSendParams {
        let toolResultsText = toolResults.enumerated().map { index, result in
            if result.success {
                return result.content
            } else {
                return "\(result.error ?? "Unknown error")"
            }
        }.joined(separator: "\n\n")
        
        let followUpMessage = A2AMessage(
            role: "user",
            parts: [.text(text: toolResultsText)],
            messageId: UUID().uuidString,
            taskId: originalParams.message.taskId,
            contextId: originalParams.message.contextId
        )
        
        return MessageSendParams(message: followUpMessage)
    }
    
    internal func handleStreamingToolCalls(_ toolCalls: [String], toolManager: ToolManager, originalParams: MessageSendParams, eventSink: @escaping (Encodable) -> Void) async {
        logger.info("Handling streaming tool calls: \(toolCalls)")
        
        // Convert string tool calls to ToolCall objects
        let parsedToolCalls = toolCalls.compactMap { toolCallString in
            ToolCall.parse(toolCallString)
        }
        
        // Execute tool calls
        let toolResults = await executeToolCalls(parsedToolCalls, toolManager: toolManager)
        
        // Create follow-up message with tool results
        let followUpParams = createFollowUpMessage(originalParams, toolResults: toolResults)
        
        // Stream the follow-up response
        do {
            try await baseAdapter.handleStream(followUpParams, store: TaskStore(), eventSink: eventSink)
        } catch {
            logger.error("Error in streaming follow-up: \(error)")
        }
    }
} 
