//
//  LLMProtocolAdapter.swift
//  SwiftAgentKitAdapters
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitA2A
import EasyJSON

/// A generic AgentAdapter that wraps any LLMProtocol implementation
/// This adapter provides a bridge between the A2A protocol and any LLM
/// that implements the LLMProtocol interface.
public struct LLMProtocolAdapter: ToolAwareAgentAdapter {
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        public let model: String
        public let maxTokens: Int?
        public let temperature: Double?
        public let topP: Double?
        public let systemPrompt: String?
        public let additionalParameters: JSON?
        
        // MARK: - Agent Configuration
        public let agentName: String
        public let agentDescription: String
        public let cardCapabilities: AgentCard.AgentCapabilities
        public let skills: [AgentCard.AgentSkill]
        public let defaultInputModes: [String]
        public let defaultOutputModes: [String]
        
        public init(
            model: String,
            maxTokens: Int? = nil,
            temperature: Double? = nil,
            topP: Double? = nil,
            systemPrompt: String? = nil,
            additionalParameters: JSON? = nil,
            agentName: String? = nil,
            agentDescription: String? = nil,
            cardCapabilities: AgentCard.AgentCapabilities? = nil,
            skills: [AgentCard.AgentSkill]? = nil,
            defaultInputModes: [String]? = nil,
            defaultOutputModes: [String]? = nil
        ) {
            self.model = model
            self.maxTokens = maxTokens
            self.temperature = temperature
            self.topP = topP
            self.systemPrompt = systemPrompt
            self.additionalParameters = additionalParameters
            
            // Set agent properties with defaults if not provided
            self.agentName = agentName ?? "LLM Protocol Agent"
            self.agentDescription = agentDescription ?? "An A2A-compliant agent that provides text generation and conversation capabilities using any LLM that implements the LLMProtocol interface."
            self.cardCapabilities = cardCapabilities ?? .init(
                streaming: true,
                pushNotifications: false,
                stateTransitionHistory: true
            )
            self.skills = skills ?? [
                .init(
                    id: "text-generation",
                    name: "text-generation",
                    description: "Generate text responses using the underlying LLM",
                    tags: ["llm", "text"],
                    inputModes: ["text/plain"],
                    outputModes: ["text/plain"]
                ),
                .init(
                    id: "conversation",
                    name: "conversation",
                    description: "Engage in conversational interactions",
                    tags: ["llm", "conversation"],
                    inputModes: ["text/plain"],
                    outputModes: ["text/plain"]
                )
            ]
            self.defaultInputModes = defaultInputModes ?? ["text/plain"]
            self.defaultOutputModes = defaultOutputModes ?? ["text/plain"]
        }
    }
    
    // MARK: - Properties
    
    private let llm: LLMProtocol
    private let config: Configuration
    private let logger: Logger
    
    // MARK: - Initialization
    
    public init(
        llm: LLMProtocol,
        configuration: Configuration
    ) {
        self.llm = llm
        self.config = configuration
        self.logger = Logger(label: "LLMProtocolAdapter")
    }
    
    public init(
        llm: LLMProtocol,
        model: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        systemPrompt: String? = nil,
        additionalParameters: JSON? = nil,
        agentName: String? = nil,
        agentDescription: String? = nil,
        cardCapabilities: AgentCard.AgentCapabilities? = nil,
        skills: [AgentCard.AgentSkill]? = nil,
        defaultInputModes: [String]? = nil,
        defaultOutputModes: [String]? = nil
    ) {
        let config = Configuration(
            model: model ?? llm.getModelName(),
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            systemPrompt: systemPrompt,
            additionalParameters: additionalParameters,
            agentName: agentName,
            agentDescription: agentDescription,
            cardCapabilities: cardCapabilities,
            skills: skills,
            defaultInputModes: defaultInputModes,
            defaultOutputModes: defaultOutputModes
        )
        self.init(llm: llm, configuration: config)
    }
    
    // MARK: - AgentAdapter Implementation
    
    public var agentName: String {
        config.agentName
    }
    
    public var agentDescription: String {
        config.agentDescription
    }
    
    public var cardCapabilities: AgentCard.AgentCapabilities {
        config.cardCapabilities
    }
    
    public var skills: [AgentCard.AgentSkill] {
        config.skills
    }
    
    public var defaultInputModes: [String] {
        config.defaultInputModes
    }
    
    public var defaultOutputModes: [String] {
        config.defaultOutputModes
    }
    
    // MARK: - Message Handling
    
    public func handleSend(_ params: MessageSendParams, store: TaskStore) async throws -> A2ATask {
        let taskId = UUID().uuidString
        let contextId = UUID().uuidString
        
        // Create initial task
        let message = A2AMessage(
            role: params.message.role,
            parts: params.message.parts,
            messageId: UUID().uuidString,
            taskId: taskId,
            contextId: contextId
        )
        
        var task = A2ATask(
            id: taskId,
            contextId: contextId,
            status: TaskStatus(
                state: .submitted,
                message: message,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            history: []
        )
        
        await store.addTask(task: task)
        
        // Update to working state
        _ = await store.updateTask(
            id: taskId,
            status: TaskStatus(
                state: .working,
                message: message,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
        )
        
        do {
            // Convert A2A message to SwiftAgentKit Message
            let messages = try convertA2AMessageToMessages(params.message, taskHistory: task.history)
            
            // Create LLM request configuration
            let llmConfig = LLMRequestConfig(
                maxTokens: config.maxTokens,
                temperature: config.temperature,
                topP: config.topP,
                stream: false,
                availableTools: [],
                additionalParameters: config.additionalParameters
            )
            
            // Call the LLM
            let response = try await llm.send(messages, config: llmConfig)
            
            // Create response message
            let responseMessage = A2AMessage(
                role: "assistant",
                parts: [.text(text: response.content)],
                messageId: UUID().uuidString,
                taskId: taskId,
                contextId: contextId
            )
            
            // Update task with completed status and add messages to history
            _ = await store.updateTask(
                id: taskId,
                status: TaskStatus(
                    state: .completed,
                    message: responseMessage,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
            // Add both the user message and assistant response to task history
            var updatedTask = await store.getTask(id: taskId) ?? task
            updatedTask.history = [message, responseMessage]
            await store.addTask(task: updatedTask)
            
            // Get final task state
            task = await store.getTask(id: taskId) ?? task
            
        } catch {
            logger.error("LLM call failed: \(error)")
            
            // Update task with failed status
            _ = await store.updateTask(
                id: taskId,
                status: TaskStatus(
                    state: .failed,
                    message: message,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
            task = await store.getTask(id: taskId) ?? task
        }
        
        return task
    }
    
    public func handleStream(_ params: MessageSendParams, store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws {
        let taskId = UUID().uuidString
        let contextId = UUID().uuidString
        
        // Create initial task
        let message = A2AMessage(
            role: params.message.role,
            parts: params.message.parts,
            messageId: UUID().uuidString,
            taskId: taskId,
            contextId: contextId
        )
        
        var task = A2ATask(
            id: taskId,
            contextId: contextId,
            status: TaskStatus(
                state: .submitted,
                message: message,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            history: []
        )
        
        await store.addTask(task: task)
        
        // Update to working state
        _ = await store.updateTask(
            id: taskId,
            status: TaskStatus(
                state: .working,
                message: message,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
        )
        
        do {
            // Convert A2A message to SwiftAgentKit Message
            let messages = try convertA2AMessageToMessages(params.message, taskHistory: task.history)
            
            // Create LLM request configuration for streaming
            let llmConfig = LLMRequestConfig(
                maxTokens: config.maxTokens,
                temperature: config.temperature,
                topP: config.topP,
                stream: true,
                availableTools: [],
                additionalParameters: config.additionalParameters
            )
            
            // Stream from the LLM
            let stream = llm.stream(messages, config: llmConfig)
            var fullContent = ""
            
            for try await result in stream {
                switch result {
                case .stream(let response):
                    fullContent += response.content
                    
                    // Create artifact update event for streaming
                    let artifact = Artifact(
                        artifactId: UUID().uuidString,
                        parts: [.text(text: fullContent)],
                        name: "llm-response",
                        description: "Streaming response from LLM",
                        metadata: nil,
                        extensions: []
                    )
                    
                    let artifactEvent = TaskArtifactUpdateEvent(
                        taskId: taskId,
                        contextId: contextId,
                        kind: "artifact-update",
                        artifact: artifact,
                        append: false,
                        lastChunk: false,
                        metadata: nil
                    )
                    
                    let streamingEvent = SendStreamingMessageSuccessResponse(
                        jsonrpc: "2.0",
                        id: 1,
                        result: artifactEvent
                    )
                    
                    eventSink(streamingEvent)
                    
                case .complete(let response):
                    fullContent += response.content
                    
                    // Create artifact update event for final response
                    let artifact = Artifact(
                        artifactId: UUID().uuidString,
                        parts: [.text(text: fullContent)],
                        name: "llm-response",
                        description: "Streaming response from LLM",
                        metadata: nil,
                        extensions: []
                    )
                    
                    let artifactEvent = TaskArtifactUpdateEvent(
                        taskId: taskId,
                        contextId: contextId,
                        kind: "artifact-update",
                        artifact: artifact,
                        append: false,
                        lastChunk: true,
                        metadata: nil
                    )
                    
                    let streamingEvent = SendStreamingMessageSuccessResponse(
                        jsonrpc: "2.0",
                        id: 1,
                        result: artifactEvent
                    )
                    
                    eventSink(streamingEvent)
                }
            }
            
            // Create final response message
            let responseMessage = A2AMessage(
                role: "assistant",
                parts: [.text(text: fullContent)],
                messageId: UUID().uuidString,
                taskId: taskId,
                contextId: contextId
            )
            
            // Update task with completed status
            _ = await store.updateTask(
                id: taskId,
                status: TaskStatus(
                    state: .completed,
                    message: responseMessage,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
            // Add both the user message and assistant response to task history
            var updatedTask = await store.getTask(id: taskId) ?? task
            updatedTask.history = [message, responseMessage]
            await store.addTask(task: updatedTask)
            
        } catch {
            logger.error("LLM streaming failed: \(error)")
            
            // Update task with failed status
            _ = await store.updateTask(
                id: taskId,
                status: TaskStatus(
                    state: .failed,
                    message: message,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
            throw error
        }
    }
    
    // MARK: - ToolAwareAgentAdapter Methods
    
    public func handleSendWithTools(_ params: MessageSendParams, availableToolCalls: [ToolDefinition], store: TaskStore) async throws -> A2ATask {
        let taskId = UUID().uuidString
        let contextId = UUID().uuidString
        
        // Create initial task
        let message = A2AMessage(
            role: params.message.role,
            parts: params.message.parts,
            messageId: UUID().uuidString,
            taskId: taskId,
            contextId: contextId
        )
        
        var task = A2ATask(
            id: taskId,
            contextId: contextId,
            status: TaskStatus(
                state: .submitted,
                message: message,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            history: []
        )
        
        await store.addTask(task: task)
        
        // Update to working state
        _ = await store.updateTask(
            id: taskId,
            status: TaskStatus(
                state: .working,
                message: message,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
        )
        
        do {
            // Convert A2A message to SwiftAgentKit Message
            let messages = try convertA2AMessageToMessages(params.message, taskHistory: task.history)
            
            // Create LLM request configuration WITH tools
            let llmConfig = LLMRequestConfig(
                maxTokens: config.maxTokens,
                temperature: config.temperature,
                topP: config.topP,
                stream: false,
                availableTools: availableToolCalls,
                additionalParameters: config.additionalParameters
            )
            
            // Call the LLM
            let response = try await llm.send(messages, config: llmConfig)
            
            // Build message parts from response content and tool calls
            var responseParts: [A2AMessagePart] = []
            if !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                responseParts.append(.text(text: response.content))
            }
            for toolCall in response.toolCalls {
                if let data = toolCallToOpenAIStyleData(toolCall) {
                    responseParts.append(.data(data: data))
                }
            }
            
            // Create response message
            let responseMessage = A2AMessage(
                role: "assistant",
                parts: responseParts,
                messageId: UUID().uuidString,
                taskId: taskId,
                contextId: contextId
            )
            
            // Update task with completed status and add messages to history
            _ = await store.updateTask(
                id: taskId,
                status: TaskStatus(
                    state: .completed,
                    message: responseMessage,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
            // Add both the user message and assistant response to task history
            var updatedTask = await store.getTask(id: taskId) ?? task
            updatedTask.history = [message, responseMessage]
            await store.addTask(task: updatedTask)
            
            // Get final task state
            task = await store.getTask(id: taskId) ?? task
            
        } catch {
            logger.error("LLM call (tools) failed: \(error)")
            
            // Update task with failed status
            _ = await store.updateTask(
                id: taskId,
                status: TaskStatus(
                    state: .failed,
                    message: message,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
            task = await store.getTask(id: taskId) ?? task
        }
        
        return task
    }
    
    public func handleStreamWithTools(_ params: MessageSendParams, availableToolCalls: [ToolDefinition], store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws {
        let taskId = UUID().uuidString
        let contextId = UUID().uuidString
        
        // Create initial task
        let message = A2AMessage(
            role: params.message.role,
            parts: params.message.parts,
            messageId: UUID().uuidString,
            taskId: taskId,
            contextId: contextId
        )
        
        var task = A2ATask(
            id: taskId,
            contextId: contextId,
            status: TaskStatus(
                state: .submitted,
                message: message,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            history: []
        )
        
        await store.addTask(task: task)
        
        // Update to working state
        _ = await store.updateTask(
            id: taskId,
            status: TaskStatus(
                state: .working,
                message: message,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
        )
        
        do {
            // Convert A2A message to SwiftAgentKit Message
            let messages = try convertA2AMessageToMessages(params.message, taskHistory: task.history)
            
            // Create LLM request configuration for streaming WITH tools
            let llmConfig = LLMRequestConfig(
                maxTokens: config.maxTokens,
                temperature: config.temperature,
                topP: config.topP,
                stream: true,
                availableTools: availableToolCalls,
                additionalParameters: config.additionalParameters
            )
            
            // Stream from the LLM
            let stream = llm.stream(messages, config: llmConfig)
            var fullContent = ""
            
            for try await result in stream {
                switch result {
                case .stream(let response):
                    fullContent += response.content
                    
                    let artifact = Artifact(
                        artifactId: UUID().uuidString,
                        parts: [.text(text: fullContent)],
                        name: "llm-response",
                        description: "Streaming response from LLM",
                        metadata: nil,
                        extensions: []
                    )
                    
                    let artifactEvent = TaskArtifactUpdateEvent(
                        taskId: taskId,
                        contextId: contextId,
                        kind: "artifact-update",
                        artifact: artifact,
                        append: false,
                        lastChunk: false,
                        metadata: nil
                    )
                    
                    let streamingEvent = SendStreamingMessageSuccessResponse(
                        jsonrpc: "2.0",
                        id: 1,
                        result: artifactEvent
                    )
                    
                    eventSink(streamingEvent)
                    
                case .complete(let response):
                    fullContent += response.content
                    
                    let artifact = Artifact(
                        artifactId: UUID().uuidString,
                        parts: [.text(text: fullContent)],
                        name: "llm-response",
                        description: "Streaming response from LLM",
                        metadata: nil,
                        extensions: []
                    )
                    
                    let artifactEvent = TaskArtifactUpdateEvent(
                        taskId: taskId,
                        contextId: contextId,
                        kind: "artifact-update",
                        artifact: artifact,
                        append: false,
                        lastChunk: true,
                        metadata: nil
                    )
                    
                    let streamingEvent = SendStreamingMessageSuccessResponse(
                        jsonrpc: "2.0",
                        id: 1,
                        result: artifactEvent
                    )
                    
                    eventSink(streamingEvent)
                }
            }
            
            // Create final response message (text only for streaming)
            let responseMessage = A2AMessage(
                role: "assistant",
                parts: [.text(text: fullContent)],
                messageId: UUID().uuidString,
                taskId: taskId,
                contextId: contextId
            )
            
            // Update task with completed status
            _ = await store.updateTask(
                id: taskId,
                status: TaskStatus(
                    state: .completed,
                    message: responseMessage,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
            // Add both the user message and assistant response to task history
            var updatedTask = await store.getTask(id: taskId) ?? task
            updatedTask.history = [message, responseMessage]
            await store.addTask(task: updatedTask)
            
        } catch {
            logger.error("LLM streaming (tools) failed: \(error)")
            
            // Update task with failed status
            _ = await store.updateTask(
                id: taskId,
                status: TaskStatus(
                    state: .failed,
                    message: message,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
            throw error
        }
    }
    
    // MARK: - Tool Conversion Helpers
    
    private func toolCallToOpenAIStyleData(_ toolCall: ToolCall) -> Data? {
        let argsString: String
        if let jsonString = serializeArgumentsToJSONString(toolCall.arguments) {
            argsString = jsonString
        } else {
            argsString = "{}"
        }
        let dict: [String: Any] = [
            "id": UUID().uuidString,
            "type": "function",
            "function": [
                "name": toolCall.name,
                "arguments": argsString
            ]
        ]
        return try? JSONSerialization.data(withJSONObject: dict)
    }
    
    private func serializeArgumentsToJSONString(_ arguments: [String: Sendable]) -> String? {
        var encodableDict: [String: Any] = [:]
        for (key, value) in arguments {
            if let v = value as? String {
                encodableDict[key] = v
            } else if let v = value as? Int {
                encodableDict[key] = v
            } else if let v = value as? Double {
                encodableDict[key] = v
            } else if let v = value as? Bool {
                encodableDict[key] = v
            } else if let v = value as? NSNumber {
                encodableDict[key] = v
            } else if let v = value as? [String] {
                encodableDict[key] = v
            } else if let v = value as? [String: String] {
                encodableDict[key] = v
            } else {
                encodableDict[key] = String(describing: value)
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: encodableDict) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    // MARK: - Helper Methods
    
    private func convertA2AMessageToMessages(_ a2aMessage: A2AMessage, taskHistory: [A2AMessage]?) throws -> [Message] {
        var messages: [Message] = []
        
        // Add system prompt if configured
        if let systemPrompt = config.systemPrompt {
            messages.append(Message(
                id: UUID(),
                role: .system,
                content: systemPrompt
            ))
        }
        
        // Add conversation history
        if let history = taskHistory {
            for historyMessage in history {
                let role = convertA2ARoleToMessageRole(historyMessage.role)
                let content = extractTextFromParts(historyMessage.parts)
                messages.append(Message(
                    id: UUID(),
                    role: role,
                    content: content
                ))
            }
        }
        
        // Add current message
        let role = convertA2ARoleToMessageRole(a2aMessage.role)
        let content = extractTextFromParts(a2aMessage.parts)
        messages.append(Message(
            id: UUID(),
            role: role,
            content: content
        ))
        
        return messages
    }
    
    private func convertA2ARoleToMessageRole(_ a2aRole: String) -> MessageRole {
        switch a2aRole.lowercased() {
        case "user":
            return .user
        case "assistant":
            return .assistant
        case "system":
            return .system
        case "tool":
            return .tool
        default:
            return .user
        }
    }
    
    private func extractTextFromParts(_ parts: [A2AMessagePart]) -> String {
        return parts.compactMap { part in
            switch part {
            case .text(let text):
                return text
            case .file, .data:
                // For now, we'll skip non-text parts
                // In the future, this could be enhanced to handle files and data
                return nil
            }
        }.joined(separator: "\n")
    }
} 