//
//  OpenAIAdapter.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import SwiftAgentKitA2A
import SwiftAgentKit
import Logging
import OpenAI

/// OpenAI API adapter for A2A protocol
public struct OpenAIAdapter: ToolAwareAgentAdapter {
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        public let apiKey: String
        public let model: String
        public let baseURL: URL
        public let maxTokens: Int?
        public let temperature: Double?
        public let systemPrompt: String?
        public let topP: Double?
        public let frequencyPenalty: Double?
        public let presencePenalty: Double?
        public let stopSequences: [String]?
        public let user: String?
        
        // Additional OpenAI configuration options
        public let organizationIdentifier: String?
        public let timeoutInterval: TimeInterval
        public let customHeaders: [String: String]
        public let parsingOptions: ParsingOptions
        
        public init(
            apiKey: String,
            model: String = "gpt-4o",
            baseURL: URL = URL(string: "https://api.openai.com/v1")!,
            maxTokens: Int? = nil,
            temperature: Double? = nil,
            systemPrompt: String? = nil,
            topP: Double? = nil,
            frequencyPenalty: Double? = nil,
            presencePenalty: Double? = nil,
            stopSequences: [String]? = nil,
            user: String? = nil,
            organizationIdentifier: String? = nil,
            timeoutInterval: TimeInterval = 300.0,
            customHeaders: [String: String] = [:],
            parsingOptions: ParsingOptions = []
        ) {
            self.apiKey = apiKey
            self.model = model
            self.baseURL = baseURL
            self.maxTokens = maxTokens
            self.temperature = temperature
            self.systemPrompt = systemPrompt
            self.topP = topP
            self.frequencyPenalty = frequencyPenalty
            self.presencePenalty = presencePenalty
            self.stopSequences = stopSequences
            self.user = user
            self.organizationIdentifier = organizationIdentifier
            self.timeoutInterval = timeoutInterval
            self.customHeaders = customHeaders
            self.parsingOptions = parsingOptions
        }
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private let logger = Logger(label: "OpenAIAdapter")
    private let openAI: OpenAI
    
    // MARK: - AgentAdapter Implementation
    
    public var cardCapabilities: AgentCard.AgentCapabilities {
        .init(
            streaming: true,
            pushNotifications: false,
            stateTransitionHistory: true
        )
    }
    
    public var skills: [AgentCard.AgentSkill] {
        [
            .init(
                id: "text-generation",
                name: "Text Generation",
                description: "Generates text responses using OpenAI's language models",
                tags: ["text", "generation", "ai", "openai"],
                examples: ["Hello, how can I help you today?"],
                inputModes: ["text/plain"],
                outputModes: ["text/plain"]
            ),
            .init(
                id: "code-generation",
                name: "Code Generation",
                description: "Generates code in various programming languages",
                tags: ["code", "programming", "development"],
                examples: ["Write a Swift function to sort an array"],
                inputModes: ["text/plain"],
                outputModes: ["text/plain"]
            ),
            .init(
                id: "analysis",
                name: "Text Analysis",
                description: "Analyzes and processes text content",
                tags: ["analysis", "text", "processing"],
                examples: ["Analyze the sentiment of this text"],
                inputModes: ["text/plain"],
                outputModes: ["text/plain"]
            )
        ]
    }
    
    public var agentName: String {
        "OpenAI Agent"
    }
    
    public var agentDescription: String {
        "An A2A-compliant agent that provides text generation capabilities using OpenAI's language models."
    }
    
    public var defaultInputModes: [String] { ["text/plain"] }
    public var defaultOutputModes: [String] { ["text/plain"] }
    
    // MARK: - Initialization
    
    public init(configuration: Configuration) {
        self.config = configuration
        
        // Extract host, port, and scheme from baseURL
        let host = configuration.baseURL.host ?? "api.openai.com"
        let port = configuration.baseURL.port ?? (configuration.baseURL.scheme == "https" ? 443 : 80)
        let scheme = configuration.baseURL.scheme ?? "https"
        let basePath = configuration.baseURL.path.isEmpty ? "/v1" : configuration.baseURL.path
        
        // Create OpenAI Configuration
        let openAIConfig = OpenAI.Configuration(
            token: configuration.apiKey,
            organizationIdentifier: configuration.organizationIdentifier,
            host: host,
            port: port,
            scheme: scheme,
            basePath: basePath,
            timeoutInterval: configuration.timeoutInterval,
            customHeaders: configuration.customHeaders,
            parsingOptions: configuration.parsingOptions
        )
        
        self.openAI = OpenAI(configuration: openAIConfig)
    }
    
    public init(
        apiKey: String, 
        model: String = "gpt-4o", 
        systemPrompt: String? = nil,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        organizationIdentifier: String? = nil,
        timeoutInterval: TimeInterval = 300.0,
        customHeaders: [String: String] = [:],
        parsingOptions: ParsingOptions = []
    ) {
        self.init(configuration: Configuration(
            apiKey: apiKey, 
            model: model, 
            baseURL: baseURL,
            systemPrompt: systemPrompt,
            organizationIdentifier: organizationIdentifier,
            timeoutInterval: timeoutInterval,
            customHeaders: customHeaders,
            parsingOptions: parsingOptions
        ))
    }
    
    // MARK: - AgentAdapter Methods
    
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
            // Extract text from message parts
            let prompt = extractTextFromParts(params.message.parts)
            
            // Build conversation history if available
            let conversationHistory = buildConversationHistory(from: params.message.parts, taskHistory: task.history)
            
            // Call OpenAI API with conversation context
            let response = try await callOpenAI(prompt: prompt, conversationHistory: conversationHistory)
            
            // Create response Artifact
            let responseArtifact = Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: response)]
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
            logger.error("OpenAI API call failed: \(error)")
            
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
            // Extract text from message parts
            let prompt = extractTextFromParts(params.message.parts)
            
            // Build conversation history if available
            let conversationHistory = buildConversationHistory(from: params.message.parts, taskHistory: task.history)
            
            // Stream from OpenAI API
            let stream = try await streamFromOpenAI(prompt: prompt, conversationHistory: conversationHistory)
            
            var accumulatedText = ""
            var partialArtifacts: [Artifact] = []
            var finalArtifact: Artifact?
            
            for try await chunk in stream {
                accumulatedText += chunk
                
                // Create artifact update event
                let artifact = Artifact(
                    artifactId: UUID().uuidString,
                    parts: [.text(text: chunk)],
                    name: "openai-response",
                    description: "Streaming response from OpenAI",
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
                
                let artifactResponse = SendStreamingMessageSuccessResponse(
                    jsonrpc: "2.0",
                    id: 1,
                    result: artifactEvent
                )
                eventSink(artifactResponse)
            }
            
            // Final artifact with complete response
            let artifact = Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: accumulatedText)],
                name: "openai-response",
                description: "Complete response from OpenAI",
                metadata: nil,
                extensions: []
            )
            
            finalArtifact = artifact
            await store.updateTaskArtifacts(id: task.id, artifacts: [artifact])
            
            let finalArtifactEvent = TaskArtifactUpdateEvent(
                taskId: task.id,
                contextId: task.contextId,
                kind: "artifact-update",
                artifact: artifact,
                append: false,
                lastChunk: true,
                metadata: nil
            )
            
            let finalArtifactResponse = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: 1,
                result: finalArtifactEvent
            )
            eventSink(finalArtifactResponse)
            
            // Create final response message
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
            logger.error("OpenAI streaming failed: \(error)")
            
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
    

    
    // MARK: - Private Methods
    

    
    private func extractTextFromParts(_ parts: [A2AMessagePart]) -> String {
        return parts.compactMap { part in
            if case .text(let text) = part {
                return text
            }
            return nil
        }.joined(separator: " ")
    }
    
    private func buildConversationHistory(from messageParts: [A2AMessagePart], taskHistory: [A2AMessage]?) -> [ChatQuery.ChatCompletionMessageParam] {
        var history: [ChatQuery.ChatCompletionMessageParam] = []
        
        // Add conversation history from previous messages
        if let taskHistory = taskHistory {
            for message in taskHistory {
                let content = extractTextFromParts(message.parts)
                let role: ChatQuery.ChatCompletionMessageParam.Role = message.role == "user" ? .user : .assistant
                if let messageParam = ChatQuery.ChatCompletionMessageParam(role: role, content: content) {
                    history.append(messageParam)
                }
            }
        }
        
        return history
    }
    
    private func callOpenAI(prompt: String, conversationHistory: [ChatQuery.ChatCompletionMessageParam] = []) async throws -> String {
        // Build messages array
        var messages: [ChatQuery.ChatCompletionMessageParam] = []
        
        // Add system message if configured
        if let systemPrompt = config.systemPrompt {
            if let systemMessage = ChatQuery.ChatCompletionMessageParam(role: .system, content: systemPrompt) {
                messages.append(systemMessage)
            }
        }
        
        // Add conversation history
        messages.append(contentsOf: conversationHistory)
        
        // Add current user message
        if let userMessage = ChatQuery.ChatCompletionMessageParam(role: .user, content: prompt) {
            messages.append(userMessage)
        }
        
        let query = ChatQuery(
            messages: messages,
            model: .init(stringLiteral: config.model),
            frequencyPenalty: config.frequencyPenalty,
            presencePenalty: config.presencePenalty,
            stop: config.stopSequences.map { .init(stringList: $0) },
            temperature: config.temperature,
            topP: config.topP,
            user: config.user
        )
        
        let response = try await openAI.chats(query: query)
        
        guard let firstChoice = response.choices.first else {
            throw OpenAIAdapterError.invalidResponse
        }
        
        return firstChoice.message.content ?? ""
    }
    

    
    private func streamFromOpenAI(prompt: String, conversationHistory: [ChatQuery.ChatCompletionMessageParam] = []) async throws -> AsyncThrowingStream<String, Error> {
        // Build messages array
        var messages: [ChatQuery.ChatCompletionMessageParam] = []
        
        // Add system message if configured
        if let systemPrompt = config.systemPrompt {
            if let systemMessage = ChatQuery.ChatCompletionMessageParam(role: .system, content: systemPrompt) {
                messages.append(systemMessage)
            }
        }
        
        // Add conversation history
        messages.append(contentsOf: conversationHistory)
        
        // Add current user message
        if let userMessage = ChatQuery.ChatCompletionMessageParam(role: .user, content: prompt) {
            messages.append(userMessage)
        }
        
        let query = ChatQuery(
            messages: messages,
            model: .init(stringLiteral: config.model),
            frequencyPenalty: config.frequencyPenalty,
            presencePenalty: config.presencePenalty,
            stop: config.stopSequences.map { .init(stringList: $0) },
            temperature: config.temperature,
            topP: config.topP,
            user: config.user
        )
        
        return AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    for try await result in openAI.chatsStream(query: query) {
                        if let content = result.choices.first?.delta.content {
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
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
            // Extract text from message parts
            let prompt = extractTextFromParts(params.message.parts)
            
            // Build conversation history if available
            let conversationHistory = buildConversationHistory(from: params.message.parts, taskHistory: task.history)
            
            // Convert tool calls to OpenAI tool format
            let tools = availableToolCalls.map { tool in
                ChatQuery.ChatCompletionToolParam(
                    function: tool.toOpenAIFunction()
                )
            }
            
            // Call OpenAI API with tools
            let response = try await callOpenAIWithTools(prompt: prompt, conversationHistory: conversationHistory, tools: tools)
            
            // Convert response to message parts (handles text content and tool calls)
            let messageParts = convertOpenAIResponseToMessageParts(response)
            
            // Create response Artifact
            let responseArtifact = Artifact(
                artifactId: UUID().uuidString,
                parts: messageParts
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
            logger.error("OpenAI API call with tools failed: \(error)")
            
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
            // Extract text from message parts
            let prompt = extractTextFromParts(params.message.parts)
            
            // Build conversation history if available
            let conversationHistory = buildConversationHistory(from: params.message.parts, taskHistory: task.history)
            
            // Convert tool calls to OpenAI tool format
            let tools = availableToolCalls.map { tool in
                ChatQuery.ChatCompletionToolParam(
                    function: tool.toOpenAIFunction()
                )
            }
            
            // Stream from OpenAI API with tools
            let stream = try await streamFromOpenAIWithTools(prompt: prompt, conversationHistory: conversationHistory, tools: tools)
            
            var accumulatedText = ""
            var partialArtifacts: [Artifact] = []
            var finalArtifact: Artifact?
            
            for try await chunk in stream {
                accumulatedText += chunk
                
                // Create artifact update event
                let artifact = Artifact(
                    artifactId: UUID().uuidString,
                    parts: [.text(text: chunk)],
                    name: "openai-response",
                    description: "Streaming response from OpenAI with tools",
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
                
                let artifactResponse = SendStreamingMessageSuccessResponse(
                    jsonrpc: "2.0",
                    id: 1,
                    result: artifactEvent
                )
                
                eventSink(artifactResponse)
            }
            
            // Create artifact update event for final response
            let artifact = Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: accumulatedText)],
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
            logger.error("OpenAI streaming with tools failed: \(error)")
            
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
    
    // MARK: - Private Helper Methods for Tools
    
    private func callOpenAIWithTools(prompt: String, conversationHistory: [ChatQuery.ChatCompletionMessageParam] = [], tools: [ChatQuery.ChatCompletionToolParam]) async throws -> ChatResult.Choice {
        // Build messages array
        var messages: [ChatQuery.ChatCompletionMessageParam] = []
        
        // Add system message if configured
        if let systemPrompt = config.systemPrompt {
            if let systemMessage = ChatQuery.ChatCompletionMessageParam(role: .system, content: systemPrompt) {
                messages.append(systemMessage)
            }
        }
        
        // Add conversation history
        messages.append(contentsOf: conversationHistory)
        
        // Add current user message
        if let userMessage = ChatQuery.ChatCompletionMessageParam(role: .user, content: prompt) {
            messages.append(userMessage)
        }
        
        let query = ChatQuery(
            messages: messages,
            model: .init(stringLiteral: config.model),
            frequencyPenalty: config.frequencyPenalty,
            presencePenalty: config.presencePenalty,
            stop: config.stopSequences.map { .init(stringList: $0) },
            temperature: config.temperature,
            tools: tools,
            topP: config.topP,
            user: config.user
        )
        
        let response = try await openAI.chats(query: query)
        
        guard let firstChoice = response.choices.first else {
            throw OpenAIAdapterError.invalidResponse
        }
        
        return firstChoice
    }
    
    // MARK: - Helper Methods for Response Processing
    
    /// Converts an OpenAI response choice into A2A message parts
    /// Handles text content and tool calls as separate message parts
    private func convertOpenAIResponseToMessageParts(_ choice: ChatResult.Choice) -> [A2AMessagePart] {
        var parts: [A2AMessagePart] = []
        
        // Add text content if present
        if let content = choice.message.content, !content.isEmpty {
            parts.append(.text(text: content))
        }
        
        // Add tool calls if present
        if let toolCalls = choice.message.toolCalls {
            for toolCall in toolCalls {
                // Convert tool call to JSON data for storage
                let toolCallData = createToolCallData(toolCall)
                parts.append(.data(data: toolCallData))
            }
        }
        
        return parts
    }
    
    /// Creates JSON data representation of a tool call
    private func createToolCallData(_ toolCall: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam) -> Data {
        let toolCallDict: [String: Any] = [
            "id": toolCall.id,
            "type": "function",
            "function": [
                "name": toolCall.function.name,
                "arguments": toolCall.function.arguments
            ]
        ]
        
        return try! JSONSerialization.data(withJSONObject: toolCallDict)
    }
    
    /// Extracts tool calls from message parts
    private func extractToolCallsFromParts(_ parts: [A2AMessagePart]) -> [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam] {
        var toolCalls: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam] = []
        
        for part in parts {
            if case .data(let data) = part {
                if let toolCall = parseToolCallFromData(data) {
                    toolCalls.append(toolCall)
                }
            }
        }
        
        return toolCalls
    }
    
    /// Parses tool call data back to OpenAI tool call format
    private func parseToolCallFromData(_ data: Data) -> ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam? {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = dict["id"] as? String,
              let functionDict = dict["function"] as? [String: Any],
              let name = functionDict["name"] as? String,
              let arguments = functionDict["arguments"] as? String else {
            return nil
        }
        
        let function = ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall(
            arguments: arguments,
            name: name
        )
        
        return ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam(
            id: id,
            function: function
        )
    }
    
    private func streamFromOpenAIWithTools(prompt: String, conversationHistory: [ChatQuery.ChatCompletionMessageParam] = [], tools: [ChatQuery.ChatCompletionToolParam]) async throws -> AsyncThrowingStream<String, Error> {
        // Build messages array
        var messages: [ChatQuery.ChatCompletionMessageParam] = []
        
        // Add system message if configured
        if let systemPrompt = config.systemPrompt {
            if let systemMessage = ChatQuery.ChatCompletionMessageParam(role: .system, content: systemPrompt) {
                messages.append(systemMessage)
            }
        }
        
        // Add conversation history
        messages.append(contentsOf: conversationHistory)
        
        // Add current user message
        if let userMessage = ChatQuery.ChatCompletionMessageParam(role: .user, content: prompt) {
            messages.append(userMessage)
        }
        
        let query = ChatQuery(
            messages: messages,
            model: .init(stringLiteral: config.model),
            frequencyPenalty: config.frequencyPenalty,
            presencePenalty: config.presencePenalty,
            stop: config.stopSequences.map { .init(stringList: $0) },
            temperature: config.temperature,
            tools: tools,
            topP: config.topP,
            user: config.user
        )
        
        return AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    for try await result in openAI.chatsStream(query: query) {
                        if let content = result.choices.first?.delta.content {
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    

}

// MARK: - Errors

enum OpenAIAdapterError: Error, LocalizedError {
    case invalidResponse
    case apiError(String)
    case rateLimitExceeded
    case quotaExceeded
    case modelNotFound
    case invalidApiKey
    case contextLengthExceeded
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .apiError(let message):
            return "OpenAI API error: \(message)"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .quotaExceeded:
            return "API quota exceeded. Please check your OpenAI account."
        case .modelNotFound:
            return "Model not found. Please check the model name."
        case .invalidApiKey:
            return "Invalid API key. Please check your OpenAI API key."
        case .contextLengthExceeded:
            return "Context length exceeded. Please shorten your message or conversation history."
        }
    }
}

// MARK: Format ToolDefinition for OpenAI

extension ToolDefinition {
    
    func toOpenAIFunction() -> ChatQuery.ChatCompletionToolParam.FunctionDefinition {
        var params: JSONSchema?
        if parameters.isEmpty == false {
            var props: Dictionary<String, AnyJSONDocument> = Dictionary<String, AnyJSONDocument>()
            for p in parameters {
                props[p.name] = .init(["type": p.type])
            }
            let required: [String] = parameters.compactMap({
                if $0.required {
                    return $0.name
                } else {
                    return nil
                }
            })
            
            let dict: [String: AnyJSONDocument] = [
                "type": .init("object"),
                "properties": .init(props),
                "required": .init(required)
            ]
            params = .object(dict)
        }
        return .init(
            name: name,
            description: description,
            parameters: params,
            strict: false
        )
    }
}

