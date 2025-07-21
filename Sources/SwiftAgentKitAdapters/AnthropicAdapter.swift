//
//  AnthropicAdapter.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import SwiftAgentKitA2A
import SwiftAgentKit
import Logging

/// Anthropic Claude API adapter for A2A protocol
public struct AnthropicAdapter: AgentAdapter {
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        public let apiKey: String
        public let model: String
        public let baseURL: URL
        public let maxTokens: Int?
        public let temperature: Double?
        
        public init(
            apiKey: String,
            model: String = "claude-3-5-sonnet-20241022",
            baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
            maxTokens: Int? = nil,
            temperature: Double? = nil
        ) {
            self.apiKey = apiKey
            self.model = model
            self.baseURL = baseURL
            self.maxTokens = maxTokens
            self.temperature = temperature
        }
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private let logger = Logger(label: "AnthropicAdapter")
    private let apiManager: RestAPIManager
    
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
                description: "Generates text responses using Anthropic's Claude models",
                tags: ["text", "generation", "ai", "anthropic", "claude"],
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
            ),
            .init(
                id: "reasoning",
                name: "Logical Reasoning",
                description: "Performs complex reasoning and problem-solving tasks",
                tags: ["reasoning", "logic", "problem-solving"],
                examples: ["Solve this mathematical problem step by step"],
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
        self.apiManager = RestAPIManager(baseURL: configuration.baseURL)
    }
    
    public init(apiKey: String, model: String = "claude-3-5-sonnet-20241022") {
        self.init(configuration: Configuration(apiKey: apiKey, model: model))
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
            
            // Call Anthropic API
            let response = try await callAnthropic(prompt: prompt)
            
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
            logger.error("Anthropic API call failed: \(error)")
            
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
            
            // Stream from Anthropic API
            let stream = try await streamFromAnthropic(prompt: prompt)
            
            var accumulatedText = ""
            
            for await chunk in stream {
                accumulatedText += chunk
                
                // Create artifact update event
                let artifact = Artifact(
                    artifactId: UUID().uuidString,
                    parts: [.text(text: accumulatedText)],
                    name: "anthropic-response",
                    description: "Streaming response from Anthropic Claude",
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
                name: "anthropic-response",
                description: "Complete response from Anthropic Claude",
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
            logger.error("Anthropic streaming failed: \(error)")
            
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
    
    private func callAnthropic(prompt: String) async throws -> String {
        let requestBody: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens ?? 1000,
            "temperature": config.temperature ?? 0.7,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        
        let headers = [
            "x-api-key": config.apiKey,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json"
        ]
        
        let response = try await apiManager.jsonRequest(
            "messages",
            method: .post,
            parameters: requestBody,
            headers: headers
        )
        
        guard let content = response["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw AnthropicAdapterError.invalidResponse
        }
        
        return text
    }
    
    private func streamFromAnthropic(prompt: String) async throws -> AsyncStream<String> {
        let requestBody: [String: Sendable] = [
            "model": config.model,
            "max_tokens": config.maxTokens ?? 1000,
            "temperature": config.temperature ?? 0.7,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "stream": true
        ]
        
        let headers = [
            "x-api-key": config.apiKey,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
            "Accept": "text/event-stream"
        ]
        
        return AsyncStream { continuation in
            Task {
                do {
                    let sseStream = await apiManager.sseRequest(
                        "messages",
                        method: .post,
                        parameters: requestBody,
                        headers: headers
                    )
                    
                    for await event in sseStream {
                        // Parse SSE event
                        if let type = event["type"] as? String {
                            switch type {
                            case "content_block_delta":
                                if let delta = event["delta"] as? [String: Any],
                                   let text = delta["text"] as? String {
                                    continuation.yield(text)
                                }
                            case "message_stop":
                                continuation.finish()
                                return
                            case "error":
                                if let error = event["error"] as? [String: Any],
                                   let message = error["message"] as? String {
                                    throw AnthropicAdapterError.streamingError(message)
                                }
                                throw AnthropicAdapterError.streamingError("Unknown streaming error occurred")
                            default:
                                // Ignore other event types
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    logger.error("Streaming error: \(error)")
                    continuation.finish()
                }
            }
        }
    }
}

// MARK: - Errors

enum AnthropicAdapterError: Error, LocalizedError {
    case invalidResponse
    case apiError(String)
    case streamingError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Anthropic API"
        case .apiError(let message):
            return "Anthropic API error: \(message)"
        case .streamingError(let message):
            return "Anthropic streaming error: \(message)"
        }
    }
} 