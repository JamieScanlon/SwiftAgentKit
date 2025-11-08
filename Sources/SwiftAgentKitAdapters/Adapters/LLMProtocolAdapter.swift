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
public struct LLMProtocolAdapter: ToolAwareAdapter {
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        public let model: String
        public let maxTokens: Int?
        public let temperature: Double?
        public let topP: Double?
        public let systemPrompt: String?
        public let additionalParameters: JSON?
        
        // MARK: - Agentic Loop Configuration
        public let maxAgenticIterations: Int
        
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
            maxAgenticIterations: Int = 10,
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
            self.maxAgenticIterations = maxAgenticIterations
            
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
        configuration: Configuration,
        logger: Logger? = nil
    ) {
        self.llm = llm
        self.config = configuration
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .adapters("LLMProtocolAdapter"),
            metadata: SwiftAgentKitLogging.metadata(
                ("model", .string(configuration.model))
            )
        )
    }
    
    public init(
        llm: LLMProtocol,
        model: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        systemPrompt: String? = nil,
        additionalParameters: JSON? = nil,
        maxAgenticIterations: Int = 10,
        agentName: String? = nil,
        agentDescription: String? = nil,
        cardCapabilities: AgentCard.AgentCapabilities? = nil,
        skills: [AgentCard.AgentSkill]? = nil,
        defaultInputModes: [String]? = nil,
        defaultOutputModes: [String]? = nil,
        logger: Logger? = nil
    ) {
        let config = Configuration(
            model: model ?? llm.getModelName(),
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            systemPrompt: systemPrompt,
            additionalParameters: additionalParameters,
            maxAgenticIterations: maxAgenticIterations,
            agentName: agentName,
            agentDescription: agentDescription,
            cardCapabilities: cardCapabilities,
            skills: skills,
            defaultInputModes: defaultInputModes,
            defaultOutputModes: defaultOutputModes
        )
        self.init(llm: llm, configuration: config, logger: logger)
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
    
    public func responseType(for params: MessageSendParams) -> AdapterResponseType {
        return .task  // LLMProtocolAdapter always uses task tracking
    }
    
    public func handleMessageSend(_ params: MessageSendParams) async throws -> A2AMessage {
        // Not used - LLMProtocolAdapter always returns tasks
        fatalError("LLMProtocolAdapter always returns tasks")
    }
    
    public func handleTaskSend(_ params: MessageSendParams, taskId: String, contextId: String, store: TaskStore) async throws {
        
        // Update to working state
        await store.updateTaskStatus(
            id: taskId,
            status: TaskStatus(
                state: .working,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
        )
        
        do {
            // Get task history from store
            let task = await store.getTask(id: taskId)
            
            // Convert A2A message to SwiftAgentKit Message
            let messages = try convertA2AMessageToMessages(params.message, metadata: params.metadata, taskHistory: task?.history)
            
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
                id: taskId,
                artifacts: [responseArtifact]
            )
            
            // Update task with completed status
            await store.updateTaskStatus(
                id: taskId,
                status: TaskStatus(
                    state: .completed,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
        } catch {
            logger.error(
                "LLM call failed",
                metadata: SwiftAgentKitLogging.metadata(
                    ("taskId", .string(taskId)),
                    ("contextId", .string(contextId)),
                    ("error", .string(String(describing: error)))
                )
            )
            
            // Update task with failed status
            await store.updateTaskStatus(
                id: taskId,
                status: TaskStatus(
                    state: .failed,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
            throw error
        }
    }
    
    public func handleStream(_ params: MessageSendParams, taskId: String?, contextId: String?, store: TaskStore?, eventSink: @escaping (Encodable) -> Void) async throws {
        // LLMProtocol adapter always uses task tracking for streaming
        guard let taskId = taskId, let contextId = contextId, let store = store else {
            throw NSError(domain: "LLMProtocolAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "LLMProtocol adapter requires task tracking for streaming"])
        }
        
        let requestId = (params.metadata?.literalValue as? [String: Any])?["requestId"] as? Int ?? 1
        
        // Update to working state
        let workingStatus = TaskStatus(
            state: .working,
            timestamp: ISO8601DateFormatter().string(from: .init())
        )
        await store.updateTaskStatus(
            id: taskId,
            status: workingStatus
        )
        
        let workingEvent = TaskStatusUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            kind: "status-update",
            status: workingStatus,
            final: false
        )
        
        let workingResponse = SendStreamingMessageSuccessResponse(
            jsonrpc: "2.0",
            id: requestId,
            result: workingEvent
        )
        eventSink(workingResponse)
        
        do {
            // Get task history from store
            let task = await store.getTask(id: taskId)
            
            // Convert A2A message to SwiftAgentKit Message
            let messages = try convertA2AMessageToMessages(params.message, metadata: params.metadata, taskHistory: task?.history)
            
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
                    await store.updateTaskArtifacts(id: taskId, artifacts: partialArtifacts)
                    
                    let artifactEvent = TaskArtifactUpdateEvent(
                        taskId: taskId,
                        contextId: contextId,
                        kind: "artifact-update",
                        artifact: artifact,
                        append: true,
                        lastChunk: false,
                        metadata: nil
                    )
                    
                    let streamingEvent = SendStreamingMessageSuccessResponse(
                        jsonrpc: "2.0",
                        id: requestId,
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
                    
                    await store.updateTaskArtifacts(id: taskId, artifacts: [artifact])
                    
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
                        id: requestId,
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
                id: taskId,
                status: completedStatus
            )
            
            let completedEvent = TaskStatusUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                kind: "status-update",
                status: completedStatus,
                final: true
            )
            
            let completedResponse = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: requestId,
                result: completedEvent
            )
            
            eventSink(completedResponse)
            
        } catch {
            logger.error(
                "LLM streaming failed",
                metadata: SwiftAgentKitLogging.metadata(
                    ("taskId", .string(taskId)),
                    ("contextId", .string(contextId)),
                    ("error", .string(String(describing: error)))
                )
            )
            
            // Update task with failed status
            let failedStatus = TaskStatus(
                state: .failed,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
            await store.updateTaskStatus(
                id: taskId,
                status: failedStatus
            )
            
            let failedEvent = TaskStatusUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                kind: "status-update",
                status: failedStatus,
                final: true
            )
            
            let failedResponse = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: requestId,
                result: failedEvent
            )
            
            eventSink(failedResponse)
            
            throw error
        }
    }
    
    // MARK: - ToolAwareAgentAdapter Methods
    
    public func handleTaskSendWithTools(_ params: MessageSendParams, taskId: String, contextId: String, toolProviders: [ToolProvider], store: TaskStore) async throws {
        
        // Update to working state
        await store.updateTaskStatus(
            id: taskId,
            status: TaskStatus(
                state: .working,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
        )
        
        do {
            // Get task history from store
            let task = await store.getTask(id: taskId)
            
            // Convert A2A message to SwiftAgentKit Message
            var messages = try convertA2AMessageToMessages(params.message, metadata: params.metadata, taskHistory: task?.history)
            let availableToolCalls: [ToolDefinition] = await {
                var returnValue = [ToolDefinition]()
                for provider in toolProviders {
                    let tools = await provider.availableTools()
                    returnValue.append(contentsOf: tools)
                }
                return returnValue
            }()
            
            // Create LLM request configuration WITH tools
            let llmConfig = LLMRequestConfig(
                maxTokens: config.maxTokens,
                temperature: config.temperature,
                topP: config.topP,
                stream: false,
                availableTools: availableToolCalls,
                additionalParameters: config.additionalParameters
            )
            
            // Agentic loop: continue calling LLM until we get a response without tool calls
            var iteration = 0
            var finalResponse: String = ""
            
            while iteration < config.maxAgenticIterations {
                iteration += 1
                logger.debug(
                    "Agentic iteration started",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("taskId", .string(taskId)),
                        ("contextId", .string(contextId)),
                        ("iteration", .stringConvertible(iteration)),
                        ("maxIterations", .stringConvertible(config.maxAgenticIterations))
                    )
                )
                
                // Call the LLM
                let response = try await llm.send(messages, config: llmConfig)
                
                // Look at the text response for any tool calls not parsed automatically
                var llmResponse = LLMResponse.llmResponse(from: response.content, availableTools: availableToolCalls)
                // Add the Tool calls the LLM identified automatically
                llmResponse = llmResponse.appending(toolCalls: response.toolCalls)
                
                // Add assistant's response to conversation
                messages.append(Message(
                    id: UUID(),
                    role: .assistant,
                    content: llmResponse.content,
                    timestamp: Date(),
                    toolCalls: llmResponse.toolCalls,
                    toolCallId: nil
                ))
                
                // If no tool calls, we have the final answer
                if llmResponse.toolCalls.isEmpty {
                    finalResponse = llmResponse.content
                    logger.info(
                        "Final response received without tool calls",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("taskId", .string(taskId)),
                            ("contextId", .string(contextId)),
                            ("iteration", .stringConvertible(iteration))
                        )
                    )
                    break
                }
                
                // Execute tool calls and add results to conversation
                logger.info(
                    "Executing tool calls",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("taskId", .string(taskId)),
                        ("contextId", .string(contextId)),
                        ("toolCallCount", .stringConvertible(llmResponse.toolCalls.count)),
                        ("toolCalls", .array(llmResponse.toolCalls.map { .string($0.name) }))
                    )
                )
                var toolResults: [String] = []
                
                for toolCall in llmResponse.toolCalls {
                    for provider in toolProviders {
                        let result = try await provider.executeTool(toolCall)
                        if result.success {
                            let toolResultText = "Successfully Executed Tool: \(toolCall.name)\n-- Start Tool Result ---\n\(result.content)\n-- End Tool Result ---\n\nYou can now continue with the next step in the conversation."
                            toolResults.append(toolResultText)
                            
                            // Add tool result as a tool message
                            messages.append(Message(
                                id: UUID(),
                                role: .tool,
                                content: toolResultText,
                                timestamp: Date(),
                                toolCalls: [],
                                toolCallId: toolCall.id
                            ))
                        } else {
                            let errorMessage = "Error Executing Tool: \(toolCall.name)\nError: \(result.content)"
                            toolResults.append(errorMessage)
                            messages.append(Message(
                                id: UUID(),
                                role: .tool,
                                content: errorMessage,
                                timestamp: Date(),
                                toolCalls: [],
                                toolCallId: toolCall.id
                            ))
                        }
                    }
                }
            }
            
            // Check if we hit max iterations
            if iteration >= config.maxAgenticIterations && finalResponse.isEmpty {
                logger.warning(
                    "Max agentic iterations reached without final response",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("taskId", .string(taskId)),
                        ("contextId", .string(contextId)),
                        ("maxIterations", .stringConvertible(config.maxAgenticIterations))
                    )
                )
                // Use the last message as the final response
                if let lastMessage = messages.last, lastMessage.role == .assistant {
                    finalResponse = lastMessage.content
                } else {
                    finalResponse = "Maximum iterations reached. Unable to complete the task."
                }
            }
            
            // Create response Artifact with final answer
            let responseArtifact = Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: finalResponse)]
            )
            
            // Update the task artifacts
            await store.updateTaskArtifacts(
                id: taskId,
                artifacts: [responseArtifact]
            )
            
            // Update task with completed status
            await store.updateTaskStatus(
                id: taskId,
                status: TaskStatus(
                    state: .completed,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
        } catch {
            logger.error(
                "LLM call with tools failed",
                metadata: SwiftAgentKitLogging.metadata(
                    ("taskId", .string(taskId)),
                    ("contextId", .string(contextId)),
                    ("error", .string(String(describing: error)))
                )
            )
            
            // Update task with failed status
            await store.updateTaskStatus(
                id: taskId,
                status: TaskStatus(
                    state: .failed,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
            throw error
        }
    }
    
    public func handleStreamWithTools(_ params: MessageSendParams, taskId: String?, contextId: String?, toolProviders: [ToolProvider], store: TaskStore?, eventSink: @escaping (Encodable) -> Void) async throws {
        // LLMProtocol adapter always uses task tracking for streaming with tools
        guard let taskId = taskId, let contextId = contextId, let store = store else {
            throw NSError(domain: "LLMProtocolAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "LLMProtocol adapter requires task tracking for streaming with tools"])
        }
        
        let requestId = (params.metadata?.literalValue as? [String: Any])?["requestId"] as? Int ?? 1
        let availableToolCalls: [ToolDefinition] = await {
            var returnValue = [ToolDefinition]()
            for provider in toolProviders {
                let tools = await provider.availableTools()
                returnValue.append(contentsOf: tools)
            }
            return returnValue
        }()
        
        // Update to working state
        let workingStatus = TaskStatus(
            state: .working,
            timestamp: ISO8601DateFormatter().string(from: .init())
        )
        await store.updateTaskStatus(
            id: taskId,
            status: workingStatus
        )
        
        let workingEvent = TaskStatusUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            kind: "status-update",
            status: workingStatus,
            final: false
        )
        
        let workingResponse = SendStreamingMessageSuccessResponse(
            jsonrpc: "2.0",
            id: requestId,
            result: workingEvent
        )
        eventSink(workingResponse)
        
        do {
            // Get task history from store
            let task = await store.getTask(id: taskId)
            
            // Convert A2A message to SwiftAgentKit Message
            var messages = try convertA2AMessageToMessages(params.message, metadata: params.metadata, taskHistory: task?.history)
            
            // Create LLM request configuration for streaming WITH tools
            let llmConfig = LLMRequestConfig(
                maxTokens: config.maxTokens,
                temperature: config.temperature,
                topP: config.topP,
                stream: true,
                availableTools: availableToolCalls,
                additionalParameters: config.additionalParameters
            )
            
            // Agentic loop: continue calling LLM until we get a response without tool calls
            var iteration = 0
            var finalResponse: String = ""
            
            while iteration < config.maxAgenticIterations {
                iteration += 1
                logger.debug(
                    "Agentic iteration (streaming) started",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("taskId", .string(taskId)),
                        ("contextId", .string(contextId)),
                        ("iteration", .stringConvertible(iteration)),
                        ("maxIterations", .stringConvertible(config.maxAgenticIterations))
                    )
                )
                
                // Stream from the LLM
                let stream = llm.stream(messages, config: llmConfig)
                var fullContent = ""
                var streamedToolCalls: [ToolCall] = []
                
                for try await result in stream {
                    switch result {
                    case .stream(let response):
                        fullContent += response.content
                        
                        // Stream partial content to client
                        let artifact = Artifact(
                            artifactId: UUID().uuidString,
                            parts: [.text(text: response.content)],
                            name: "partial-llm-response",
                            description: "Partial streaming response from LLM",
                            metadata: nil,
                            extensions: []
                        )
                        
                        let artifactEvent = TaskArtifactUpdateEvent(
                            taskId: taskId,
                            contextId: contextId,
                            kind: "artifact-update",
                            artifact: artifact,
                            append: true,
                            lastChunk: false,
                            metadata: nil
                        )
                        
                        let streamingEvent = SendStreamingMessageSuccessResponse(
                            jsonrpc: "2.0",
                            id: requestId,
                            result: artifactEvent
                        )
                        
                        eventSink(streamingEvent)
                        
                    case .complete(let response):
                        // The response.content should contain the full response
                        fullContent = response.content
                        streamedToolCalls = response.toolCalls
                    }
                }
                
                // Look at the text response for any tool calls not parsed automatically
                var llmResponse = LLMResponse.llmResponse(from: fullContent, availableTools: availableToolCalls)
                // Add the Tool calls the LLM identified automatically
                llmResponse = llmResponse.appending(toolCalls: streamedToolCalls)
                
                // Add assistant's response to conversation
                messages.append(Message(
                    id: UUID(),
                    role: .assistant,
                    content: llmResponse.content,
                    timestamp: Date(),
                    toolCalls: llmResponse.toolCalls,
                    toolCallId: nil
                ))
                
                // If no tool calls, we have the final answer
                if llmResponse.toolCalls.isEmpty {
                    finalResponse = llmResponse.content
                    logger.info(
                        "Final streaming response received without tool calls",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("taskId", .string(taskId)),
                            ("contextId", .string(contextId)),
                            ("iteration", .stringConvertible(iteration))
                        )
                    )
                    break
                }
                
                // Execute tool calls and add results to conversation
                logger.info(
                    "Executing tool calls during streaming",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("taskId", .string(taskId)),
                        ("contextId", .string(contextId)),
                        ("toolCallCount", .stringConvertible(llmResponse.toolCalls.count)),
                        ("toolCalls", .array(llmResponse.toolCalls.map { .string($0.name) }))
                    )
                )
                
                // Stream tool execution status
                let toolStatusArtifact = Artifact(
                    artifactId: UUID().uuidString,
                    parts: [.text(text: "\n\n[Executing \(llmResponse.toolCalls.count) tool(s)...]\n\n")],
                    name: "tool-status",
                    description: "Tool execution status",
                    metadata: nil,
                    extensions: []
                )
                
                let toolStatusEvent = TaskArtifactUpdateEvent(
                    taskId: taskId,
                    contextId: contextId,
                    kind: "artifact-update",
                    artifact: toolStatusArtifact,
                    append: true,
                    lastChunk: false,
                    metadata: nil
                )
                
                let toolStatusResponse = SendStreamingMessageSuccessResponse(
                    jsonrpc: "2.0",
                    id: requestId,
                    result: toolStatusEvent
                )
                
                eventSink(toolStatusResponse)
                
                for toolCall in llmResponse.toolCalls {
                    for provider in toolProviders {
                        let result = try await provider.executeTool(toolCall)
                        if result.success {
                            // Add tool result as a tool message
                            messages.append(Message(
                                id: UUID(),
                                role: .tool,
                                content: "Successfully Executed Tool: \(toolCall.name)\n-- Start Tool Result ---\n\(result.content)\n-- End Tool Result ---\n\nYou can now continue with the next step in the conversation.",
                                timestamp: Date(),
                                toolCalls: [],
                                toolCallId: toolCall.id
                            ))
                        } else {
                            let errorMessage = "Error Executing Tool: \(toolCall.name)\nError: \(result.content)"
                            messages.append(Message(
                                id: UUID(),
                                role: .tool,
                                content: errorMessage,
                                timestamp: Date(),
                                toolCalls: [],
                                toolCallId: toolCall.id
                            ))
                        }
                    }
                }
            }
            
            // Check if we hit max iterations
            if iteration >= config.maxAgenticIterations && finalResponse.isEmpty {
                logger.warning(
                    "Max agentic iterations reached without final streaming response",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("taskId", .string(taskId)),
                        ("contextId", .string(contextId)),
                        ("maxIterations", .stringConvertible(config.maxAgenticIterations))
                    )
                )
                // Use the last message as the final response
                if let lastMessage = messages.last, lastMessage.role == .assistant {
                    finalResponse = lastMessage.content
                } else {
                    finalResponse = "Maximum iterations reached. Unable to complete the task."
                }
            }
            
            // Create artifact update event for final response
            let finalArtifact = Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: finalResponse)],
                name: "final-llm-response",
                description: "Final streaming response from LLM",
                metadata: nil,
                extensions: []
            )
            
            await store.updateTaskArtifacts(id: taskId, artifacts: [finalArtifact])
            
            let artifactEvent = TaskArtifactUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                kind: "artifact-update",
                artifact: finalArtifact,
                append: false,
                lastChunk: true,
                metadata: nil
            )
            
            let streamingEvent = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: requestId,
                result: artifactEvent
            )
            
            eventSink(streamingEvent)
            
            // Update task with completed status
            let completedStatus = TaskStatus(
                state: .completed,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
            await store.updateTaskStatus(
                id: taskId,
                status: completedStatus
            )
            
            let completedEvent = TaskStatusUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                kind: "status-update",
                status: completedStatus,
                final: true
            )
            
            let completedResponse = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: requestId,
                result: completedEvent
            )
            
            eventSink(completedResponse)
            
        } catch {
            logger.error(
                "LLM streaming with tools failed",
                metadata: SwiftAgentKitLogging.metadata(
                    ("taskId", .string(taskId)),
                    ("contextId", .string(contextId)),
                    ("error", .string(String(describing: error)))
                )
            )
            
            // Update task with failed status
            
            let failedStatus = TaskStatus(
                state: .failed,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
            await store.updateTaskStatus(
                id: taskId,
                status: failedStatus
            )
            
            let failedEvent = TaskStatusUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                kind: "status-update",
                status: failedStatus,
                final: true
            )
            
            let failedResponse = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: requestId,
                result: failedEvent
            )
            
            eventSink(failedResponse)
            
            throw error
        }
    }
    
    // MARK: - Helper Methods
    
    private func convertA2AMessageToMessages(_ a2aMessage: A2AMessage, metadata: JSON?, taskHistory: [A2AMessage]?) throws -> [Message] {
        var messages: [Message] = []
        
        // Add system prompt if configured
        if let systemPrompt = config.systemPrompt {
            messages.append(Message(
                id: UUID(),
                role: .system,
                content: systemPrompt,
                timestamp: Date(),
                toolCalls: [],
                toolCallId: nil
            ))
        }
        
        // Add conversation history
        if let history = taskHistory {
            for historyMessage in history {
                let role = convertA2ARoleToMessageRole(historyMessage.role)
                let content = extractTextFromParts(historyMessage.parts)
                let toolCallId = (historyMessage.metadata?.literalValue as? [String: Any])?["toolCallId"] as? String
                messages.append(Message(
                    id: UUID(),
                    role: role,
                    content: content,
                    toolCallId: toolCallId
                ))
            }
        }
        
        // Add current message
        let role = convertA2ARoleToMessageRole(a2aMessage.role)
        let content = extractTextFromParts(a2aMessage.parts)
        let toolCallId = (metadata?.literalValue as? [String: Any])?["toolCallId"] as? String
        messages.append(Message(
            id: UUID(),
            role: role,
            content: content,
            timestamp: Date(),
            toolCalls: [],
            toolCallId: toolCallId
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
