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
public struct OpenAIAdapter: AgentAdapter {
    
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
            timeoutInterval: TimeInterval = 60.0,
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
        timeoutInterval: TimeInterval = 60.0,
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
            history: [params.message]
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
            // Extract text from message parts
            let prompt = extractTextFromParts(params.message.parts)
            
            // Build conversation history if available
            let conversationHistory = buildConversationHistory(from: params.message.parts, taskHistory: task.history)
            
            // Call OpenAI API with conversation context
            let response = try await callOpenAI(prompt: prompt, conversationHistory: conversationHistory)
            
            // Create response message
            let responseMessage = A2AMessage(
                role: "assistant",
                parts: [.text(text: response)],
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
            
            // Get final task state
            task = await store.getTask(id: taskId) ?? task
            
        } catch {
            logger.error("OpenAI API call failed: \(error)")
            
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
        
        let message = A2AMessage(
            role: params.message.role,
            parts: params.message.parts,
            messageId: UUID().uuidString,
            taskId: taskId,
            contextId: contextId
        )
        
        let baseTask = A2ATask(
            id: taskId,
            contextId: contextId,
            status: TaskStatus(
                state: .submitted,
                message: message,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            history: [params.message]
        )
        
        await store.addTask(task: baseTask)
        
        // Emit submitted status
        let submitted = TaskStatusUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            kind: "status-update",
            status: TaskStatus(
                state: .submitted,
                message: message,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            final: false
        )
        let submittedResponse = SendStreamingMessageSuccessResponse(
            jsonrpc: "2.0",
            id: 1,
            result: submitted
        )
        eventSink(submittedResponse)
        
        // Update to working state
        _ = await store.updateTask(
            id: taskId,
            status: TaskStatus(
                state: .working,
                message: message,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
        )
        
        let working = TaskStatusUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            kind: "status-update",
            status: TaskStatus(
                state: .working,
                message: message,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            final: false
        )
        let workingResponse = SendStreamingMessageSuccessResponse(
            jsonrpc: "2.0",
            id: 1,
            result: working
        )
        eventSink(workingResponse)
        
        do {
            // Extract text from message parts
            let prompt = extractTextFromParts(params.message.parts)
            
            // Build conversation history if available
            let conversationHistory = buildConversationHistory(from: params.message.parts, taskHistory: baseTask.history)
            
            // Stream from OpenAI API
            let stream = try await streamFromOpenAI(prompt: prompt, conversationHistory: conversationHistory)
            
            var accumulatedText = ""
            
            for try await chunk in stream {
                accumulatedText += chunk
                
                // Create artifact update event
                let artifact = Artifact(
                    artifactId: UUID().uuidString,
                    parts: [.text(text: accumulatedText)],
                    name: "openai-response",
                    description: "Streaming response from OpenAI",
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
                
                let artifactResponse = SendStreamingMessageSuccessResponse(
                    jsonrpc: "2.0",
                    id: 1,
                    result: artifactEvent
                )
                eventSink(artifactResponse)
            }
            
            // Final artifact with complete response
            let finalArtifact = Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: accumulatedText)],
                name: "openai-response",
                description: "Complete response from OpenAI",
                metadata: nil,
                extensions: []
            )
            
            let finalArtifactEvent = TaskArtifactUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                kind: "artifact-update",
                artifact: finalArtifact,
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
            let responseMessage = A2AMessage(
                role: "assistant",
                parts: [.text(text: accumulatedText)],
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
            
            // Emit final status update
            let completed = TaskStatusUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                kind: "status-update",
                status: TaskStatus(
                    state: .completed,
                    message: responseMessage,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                ),
                final: true
            )
            let completedResponse = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: 1,
                result: completed
            )
            eventSink(completedResponse)
            
        } catch {
            logger.error("OpenAI streaming failed: \(error)")
            
            // Update task with failed status
            _ = await store.updateTask(
                id: taskId,
                status: TaskStatus(
                    state: .failed,
                    message: message,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
            // Emit failed status
            let failed = TaskStatusUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                kind: "status-update",
                status: TaskStatus(
                    state: .failed,
                    message: message,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                ),
                final: true
            )
            let failedResponse = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: 1,
                result: failed
            )
            eventSink(failedResponse)
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
        
        // Add conversation history (filtering out any system messages to avoid duplication)
        let filteredHistory = conversationHistory.filter { $0.role != .system }
        messages.append(contentsOf: filteredHistory)
        
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
        
        // Add conversation history (filtering out any system messages to avoid duplication)
        let filteredHistory = conversationHistory.filter { $0.role != .system }
        messages.append(contentsOf: filteredHistory)
        
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