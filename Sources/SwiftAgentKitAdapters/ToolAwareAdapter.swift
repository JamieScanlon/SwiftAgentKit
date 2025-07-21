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
        
        // Create enhanced message with tool context
        let enhancedParams = await enhanceMessageWithToolContext(params, availableTools: availableTools)
        
        // Process with base adapter
        var task = try await baseAdapter.handleSend(enhancedParams, store: store)
        
        // Check if the response contains tool calls
        if let responseMessage = task.status.message {
            let (processedMessage, toolCalls) = await processResponseForToolCalls(responseMessage)
            
            if !toolCalls.isEmpty {
                logger.info("Detected \(toolCalls.count) tool calls in response")
                
                // Execute tool calls and get results
                let toolResults = await executeToolCalls(toolCalls, toolManager: toolManager)
                
                // Create follow-up message with tool results
                let followUpParams = createFollowUpMessage(params, toolResults: toolResults)
                
                // Get final response from LLM with tool results
                let finalTask = try await baseAdapter.handleSend(followUpParams, store: store)
                
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
        
        // Create enhanced message with tool context
        let enhancedParams = await enhanceMessageWithToolContext(params, availableTools: availableTools)
        
        // For streaming, we need to collect the response and check for tool calls
        var accumulatedResponse = ""
        var hasProcessedToolCalls = false
        
        try await baseAdapter.handleStream(enhancedParams, store: store) { event in
            // Check if this is a message event with content
            if let messageEvent = event as? TaskStatusUpdateEvent,
               let message = messageEvent.status.message {
                let text = message.parts.compactMap { part in
                    if case .text(let text) = part { return text } else { return nil }
                }.joined(separator: " ")
                accumulatedResponse += text
                
                // Check for tool calls in accumulated response
                if !hasProcessedToolCalls {
                    let (_, toolCall) = ToolCall.processModelResponse(content: accumulatedResponse)
                    if let toolCall = toolCall {
                        hasProcessedToolCalls = true
                        logger.info("Detected tool calls in streaming response")
                        
                        // For now, we'll handle tool calls synchronously to avoid concurrency issues
                        // In a production environment, you might want to implement a more sophisticated
                        // approach for handling streaming tool calls
                        logger.info("Tool calls detected in streaming mode, but async execution is disabled for concurrency safety")
                    }
                }
            }
            
            // Forward the event
            eventSink(event)
        }
    }
    
    // MARK: - Internal Helper Methods (for testing)
    
    internal func enhanceMessageWithToolContext(_ params: MessageSendParams, availableTools: [ToolDefinition]) async -> MessageSendParams {
        guard !availableTools.isEmpty else { return params }
        
        // Create tool context message
        let toolDescriptions = availableTools.map { tool in
            "- \(tool.name): \(tool.description)"
        }.joined(separator: "\n")
        
        let toolContext = """
        Available tools:
        \(toolDescriptions)
        
        You can use these tools by including tool calls in your response. Format tool calls as:
        <|python_tag|>
        tool_name(arguments)
        <|eom_id|>
        
        For example:
        <|python_tag|>
        weather_tool(location="New York")
        <|eom_id|>
        """
        
        // Add tool context to the message
        var enhancedParts = params.message.parts
        enhancedParts.insert(.text(text: toolContext), at: 0)
        
        let enhancedMessage = A2AMessage(
            role: params.message.role,
            parts: enhancedParts,
            messageId: params.message.messageId,
            taskId: params.message.taskId,
            contextId: params.message.contextId
        )
        
        return MessageSendParams(message: enhancedMessage)
    }
    
    internal func processResponseForToolCalls(_ message: A2AMessage) async -> (A2AMessage, [String]) {
        let text = message.parts.compactMap { part in
            if case .text(let text) = part { return text } else { return nil }
        }.joined(separator: " ")
        
        let (processedText, toolCall) = ToolCall.processModelResponse(content: text)
        
        var processedParts = message.parts
        if let firstPart = processedParts.first,
           case .text = firstPart {
            processedParts[0] = .text(text: processedText)
        } else {
            processedParts.insert(.text(text: processedText), at: 0)
        }
        
        let processedMessage = A2AMessage(
            role: message.role,
            parts: processedParts,
            messageId: message.messageId,
            taskId: message.taskId,
            contextId: message.contextId
        )
        
        let toolCalls = toolCall != nil ? [toolCall!] : []
        return (processedMessage, toolCalls)
    }
    
    internal func executeToolCalls(_ toolCalls: [String], toolManager: ToolManager) async -> [ToolResult] {
        var results: [ToolResult] = []
        
        for toolCallString in toolCalls {
            do {
                // Parse tool call string to extract name and arguments
                let (name, arguments) = parseToolCall(toolCallString)
                let toolCall = ToolCall(name: name, arguments: arguments)
                
                logger.info("Executing tool: \(name) with arguments: \(arguments)")
                let result = try await toolManager.executeTool(toolCall)
                results.append(result)
                
                if result.success {
                    logger.info("Tool \(name) executed successfully")
                } else {
                    logger.warning("Tool \(name) failed: \(result.error ?? "Unknown error")")
                }
            } catch {
                logger.error("Error executing tool call '\(toolCallString)': \(error)")
                results.append(ToolResult(
                    success: false,
                    content: "",
                    error: "Execution error: \(error.localizedDescription)"
                ))
            }
        }
        
        return results
    }
    
    internal func parseToolCall(_ toolCallString: String) -> (String, [String: Sendable]) {
        // Simple parsing for tool calls like "tool_name(arg1=value1, arg2=value2)"
        let trimmed = toolCallString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let openParenIndex = trimmed.firstIndex(of: "("),
              let closeParenIndex = trimmed.lastIndex(of: ")") else {
            return (trimmed, [:])
        }
        
        let name = String(trimmed[..<openParenIndex]).trimmingCharacters(in: .whitespaces)
        let argsString = String(trimmed[trimmed.index(after: openParenIndex)..<closeParenIndex])
        
        var arguments: [String: Sendable] = [:]
        
        // Parse arguments
        let args = argsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for arg in args {
            let parts = arg.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                let key = parts[0]
                let value = parts[1].trimmingCharacters(in: .init(charactersIn: "\"'"))
                arguments[key] = value
            }
        }
        
        return (name, arguments)
    }
    
    internal func createFollowUpMessage(_ originalParams: MessageSendParams, toolResults: [ToolResult]) -> MessageSendParams {
        let toolResultsText = toolResults.enumerated().map { index, result in
            if result.success {
                return "Tool result \(index + 1): \(result.content)"
            } else {
                return "Tool result \(index + 1): Error - \(result.error ?? "Unknown error")"
            }
        }.joined(separator: "\n\n")
        
        let followUpText = """
        Tool execution completed. Here are the results:
        
        \(toolResultsText)
        
        Please continue with your response based on these tool results.
        """
        
        let followUpMessage = A2AMessage(
            role: "user",
            parts: [.text(text: followUpText)],
            messageId: UUID().uuidString,
            taskId: originalParams.message.taskId,
            contextId: originalParams.message.contextId
        )
        
        return MessageSendParams(message: followUpMessage)
    }
    
    internal func handleStreamingToolCalls(_ toolCalls: [String], toolManager: ToolManager, originalParams: MessageSendParams, eventSink: @escaping (Encodable) -> Void) async {
        logger.info("Handling streaming tool calls: \(toolCalls)")
        
        // Execute tool calls
        let toolResults = await executeToolCalls(toolCalls, toolManager: toolManager)
        
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