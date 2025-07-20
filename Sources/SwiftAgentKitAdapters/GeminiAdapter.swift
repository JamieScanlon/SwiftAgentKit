//
//  GeminiAdapter.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import SwiftAgentKitA2A
import SwiftAgentKit
import Logging

/// Google Gemini API adapter for A2A protocol
public struct GeminiAdapter: AgentAdapter {
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        public let apiKey: String
        public let model: String
        public let baseURL: URL
        public let maxTokens: Int?
        public let temperature: Double?
        
        public init(
            apiKey: String,
            model: String = "gemini-1.5-flash",
            baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
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
    private let logger = Logger(label: "GeminiAdapter")
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
                description: "Generates text responses using Google's Gemini models",
                tags: ["text", "generation", "ai", "google", "gemini"],
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
                id: "multimodal",
                name: "Multimodal Processing",
                description: "Processes text and image inputs",
                tags: ["multimodal", "vision", "image"],
                examples: ["Describe what you see in this image"],
                inputModes: ["text/plain", "image/jpeg", "image/png"],
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
    
    public init(apiKey: String, model: String = "gemini-1.5-flash") {
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
            // Call Gemini API
            let response = try await callGemini(messageParts: params.message.parts)
            
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
            logger.error("Gemini API call failed: \(error)")
            
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
            // Stream from Gemini API
            let stream = try await streamFromGemini(messageParts: params.message.parts)
            
            var accumulatedText = ""
            
            for await chunk in stream {
                accumulatedText += chunk
                
                // Create artifact update event
                let artifact = Artifact(
                    artifactId: UUID().uuidString,
                    parts: [.text(text: accumulatedText)],
                    name: "gemini-response",
                    description: "Streaming response from Google Gemini",
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
                name: "gemini-response",
                description: "Complete response from Google Gemini",
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
            logger.error("Gemini streaming failed: \(error)")
            
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
    
    private func callGemini(messageParts: [A2AMessagePart]) async throws -> String {
        // For now, return a simple response
        // TODO: Implement proper Gemini API integration
        let prompt = extractTextFromParts(messageParts)
        return "Gemini response to: \(prompt)"
    }
    
    private func streamFromGemini(messageParts: [A2AMessagePart]) async throws -> AsyncStream<String> {
        // For now, return a simple stream that yields the full response
        // TODO: Implement proper streaming when SSE issues are resolved
        let response = try await callGemini(messageParts: messageParts)
        return AsyncStream { continuation in
            continuation.yield(response)
            continuation.finish()
        }
    }
    
    private func buildGeminiContents(from messageParts: [A2AMessagePart]) throws -> [[String: Any]] {
        var parts: [[String: Any]] = []
        
        for part in messageParts {
            switch part {
            case .text(let text):
                parts.append([
                    "text": text
                ])
            case .file(let data, let url):
                // For Gemini, we need to encode file data as base64
                if let imageData = data {
                    let base64Data = imageData.base64EncodedString()
                    parts.append([
                        "inlineData": [
                            "mimeType": "image/jpeg", // Default, could be made configurable
                            "data": base64Data
                        ]
                    ])
                }
            case .data(let imageData):
                // For Gemini, we need to encode data as base64
                let base64Data = imageData.base64EncodedString()
                parts.append([
                    "inlineData": [
                        "mimeType": "image/jpeg", // Default, could be made configurable
                        "data": base64Data
                    ]
                ])
            }
        }
        
        return [
            [
                "parts": parts
            ]
        ]
    }
}

// MARK: - Errors

enum GeminiAdapterError: Error, LocalizedError {
    case invalidResponse
    case apiError(String)
    case unsupportedContentType
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .apiError(let message):
            return "Gemini API error: \(message)"
        case .unsupportedContentType:
            return "Unsupported content type for Gemini API"
        }
    }
} 