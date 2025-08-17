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
    
    public func handleSend(_ params: MessageSendParams, task: A2ATask, store: TaskStore) async throws {
        
        // Update to working state
        await store.updateTaskStatus(
            id: task.id,
            status: TaskStatus(
                state: .working,
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
            
            // Create response Artifact
            let responseArtifact = Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: response.content)]
            )
            
            // Update the task store with the artifact
            await store.updateTaskArtifacts(
                id: task.id,
                artifacts: [responseArtifact]
            )
            
            // Update task with completed status and add messages to history
            await store.updateTaskStatus(
                id: task.id,
                status: TaskStatus(
                    state: .completed,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
        } catch {
            logger.error("LLM call failed: \(error)")
            
            // Update task with failed status
            await store.updateTaskStatus(
                id: task.id,
                status: TaskStatus(
                    state: .failed,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
            throw error
        }
    }
    
    public func handleStream(_ params: MessageSendParams, task: A2ATask, store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws {
        
        // Update to working state
        let workingStatus = TaskStatus(
            state: .working,
            timestamp: ISO8601DateFormatter().string(from: .init())
        )
        await store.updateTaskStatus(
            id: task.id,
            status: workingStatus
        )
        
        let workingEvent = TaskStatusUpdateEvent(
            taskId: task.id,
            contextId: task.contextId,
            kind: "status-update",
            status: workingStatus,
            final: false
        )
        
        let workingResponse = SendStreamingMessageSuccessResponse(
            jsonrpc: "2.0",
            id: 1,
            result: workingEvent
        )
        eventSink(workingResponse)
        
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
            var partialArtifacts: [Artifact] = []
            var finalArtifact: Artifact?
            
            for try await result in stream {
                switch result {
                case .stream(let response):
                    fullContent += response.content
                    
                    // Create artifact update event for streaming
                    let artifact = Artifact(
                        artifactId: UUID().uuidString,
                        parts: [.text(text: response.content)],
                        name: "partial-llm-response",
                        description: "Partial S=streaming response from LLM",
                        metadata: nil,
                        extensions: []
                    )
                    
                    partialArtifacts.append(artifact)
                    await store.updateTaskArtifacts(id: task.id, artifacts: partialArtifacts)
                    
                    let artifactEvent = TaskArtifactUpdateEvent(
                        taskId: task.id,
                        contextId: task.contextId,
                        kind: "artifact-update",
                        artifact: artifact,
                        append: true,
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

                    // the response.content sould contain the full response
                    fullContent = response.content
                    
                    // Create artifact update event for final response
                    let artifact = Artifact(
                        artifactId: UUID().uuidString,
                        parts: [.text(text: response.content)],
                        name: "final-llm-response",
                        description: "Final streaming response from LLM",
                        metadata: nil,
                        extensions: []
                    )
                    
                    finalArtifact = artifact
                    await store.updateTaskArtifacts(id: task.id, artifacts: [artifact])
                    
                    let artifactEvent = TaskArtifactUpdateEvent(
                        taskId: task.id,
                        contextId: task.contextId,
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
            
            // Update task with completed status
            let completedStatus = TaskStatus(
                state: .completed,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
            await store.updateTaskStatus(
                id: task.id,
                status: completedStatus
            )
            
            let completedEvent = TaskStatusUpdateEvent(
                taskId: task.id,
                contextId: task.contextId,
                kind: "status-update",
                status: completedStatus,
                final: true
            )
            
            let completedResponse = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: 1,
                result: completedEvent
            )
            
            eventSink(completedResponse)
            
        } catch {
            logger.error("LLM streaming failed: \(error)")
            
            // Update task with failed status
            let failedStatus = TaskStatus(
                state: .failed,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
            await store.updateTaskStatus(
                id: task.id,
                status: failedStatus
            )
            
            let failedEvent = TaskStatusUpdateEvent(
                taskId: task.id,
                contextId: task.contextId,
                kind: "status-update",
                status: failedStatus,
                final: true
            )
            
            let failedResponse = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: 1,
                result: failedEvent
            )
            
            eventSink(failedResponse)
            
            throw error
        }
    }
    
    // MARK: - ToolAwareAgentAdapter Methods
    
    public func handleSendWithTools(_ params: MessageSendParams, task: A2ATask, availableToolCalls: [ToolDefinition], store: TaskStore) async throws {
        
        // Update to working state
        await store.updateTaskStatus(
            id: task.id,
            status: TaskStatus(
                state: .working,
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
            
            // Create response Artifact
            let responseArtifact = Artifact(
                artifactId: UUID().uuidString,
                parts: responseParts
            )
            
            // Update the task artifacts
            await store.updateTaskArtifacts(
                id: task.id,
                artifacts: [responseArtifact]
            )
            
            // Update task with completed status and add messages to history
            await store.updateTaskStatus(
                id: task.id,
                status: TaskStatus(
                    state: .completed,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
        } catch {
            logger.error("LLM call (tools) failed: \(error)")
            
            // Update task with failed status
            await store.updateTaskStatus(
                id: task.id,
                status: TaskStatus(
                    state: .failed,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
            throw error
        }
    }
    
    public func handleStreamWithTools(_ params: MessageSendParams, task: A2ATask, availableToolCalls: [ToolDefinition], store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws {
        
        // Update to working state
        let workingStatus = TaskStatus(
            state: .working,
            timestamp: ISO8601DateFormatter().string(from: .init())
        )
        await store.updateTaskStatus(
            id: task.id,
            status: workingStatus
        )
        
        let workingEvent = TaskStatusUpdateEvent(
            taskId: task.id,
            contextId: task.contextId,
            kind: "status-update",
            status: workingStatus,
            final: false
        )
        
        let workingResponse = SendStreamingMessageSuccessResponse(
            jsonrpc: "2.0",
            id: 1,
            result: workingEvent
        )
        eventSink(workingResponse)
        
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
            var partialArtifacts: [Artifact] = []
            var finalArtifact: Artifact?
            
            for try await result in stream {
                switch result {
                case .stream(let response):
                    fullContent += response.content
                    
                    let artifact = Artifact(
                        artifactId: UUID().uuidString,
                        parts: [.text(text: response.content)],
                        name: "partial-llm-response",
                        description: "Parial streaming response from LLM",
                        metadata: nil,
                        extensions: []
                    )
                    
                    partialArtifacts.append(artifact)
                    await store.updateTaskArtifacts(id: task.id, artifacts: partialArtifacts)
                    
                    let artifactEvent = TaskArtifactUpdateEvent(
                        taskId: task.id,
                        contextId: task.contextId,
                        kind: "artifact-update",
                        artifact: artifact,
                        append: true,
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
                    // the response.content sould contain the full response
                    fullContent = response.content
                    
                    // Create artifact update event for final response
                    let artifact = Artifact(
                        artifactId: UUID().uuidString,
                        parts: [.text(text: response.content)],
                        name: "final-llm-response",
                        description: "Final streaming response from LLM",
                        metadata: nil,
                        extensions: []
                    )
                    
                    finalArtifact = artifact
                    await store.updateTaskArtifacts(id: task.id, artifacts: [artifact])
                    
                    let artifactEvent = TaskArtifactUpdateEvent(
                        taskId: task.id,
                        contextId: task.contextId,
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
            
            // TODO: Make tool calls
            
            // Update task with completed status
            let completedStatus = TaskStatus(
                state: .completed,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
            await store.updateTaskStatus(
                id: task.id,
                status: completedStatus
            )
            
            let completedEvent = TaskStatusUpdateEvent(
                taskId: task.id,
                contextId: task.contextId,
                kind: "status-update",
                status: completedStatus,
                final: true
            )
            
            let completedResponse = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: 1,
                result: completedEvent
            )
            
            eventSink(completedResponse)
            
        } catch {
            logger.error("LLM streaming (tools) failed: \(error)")
            
            // Update task with failed status
            
            let failedStatus = TaskStatus(
                state: .failed,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
            await store.updateTaskStatus(
                id: task.id,
                status: failedStatus
            )
            
            let failedEvent = TaskStatusUpdateEvent(
                taskId: task.id,
                contextId: task.contextId,
                kind: "status-update",
                status: failedStatus,
                final: true
            )
            
            let failedResponse = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: 1,
                result: failedEvent
            )
            
            eventSink(failedResponse)
            
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
