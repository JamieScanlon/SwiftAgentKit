//
//  LLMProtocolAdapterTests.swift
//  SwiftAgentKitAdaptersTests
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import Testing
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitAdapters
import Logging

// MARK: - Test LLM Implementation

/// A test LLM that implements LLMProtocol for testing purposes
struct TestLLM: LLMProtocol {
    let model: String
    let logger: Logger
    let shouldFail: Bool
    
    init(model: String = "test-llm", shouldFail: Bool = false) {
        self.model = model
        self.logger = Logger(label: "TestLLM")
        self.shouldFail = shouldFail
    }
    
    func getModelName() -> String {
        return model
    }
    
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        if shouldFail {
            throw LLMError.invalidRequest("Test failure")
        }
        
        logger.info("Processing \(messages.count) messages")
        
        // Extract the last user message
        let lastUserMessage = messages.last { $0.role == .user }?.content ?? "Hello"
        
        // Generate a response based on the input
        let response = "Test response to: '\(lastUserMessage)'"
        
        return LLMResponse(
            content: response,
            metadata: LLMMetadata(
                promptTokens: 5,
                completionTokens: response.count / 4,
                totalTokens: 5 + (response.count / 4),
                finishReason: "stop"
            )
        )
    }
    
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<LLMResponse, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await send(messages, config: config)
                    let words = response.content.components(separatedBy: " ")
                    
                    // Stream the response word by word
                    for (index, word) in words.enumerated() {
                        let isComplete = index == words.count - 1
                        let chunk = LLMResponse(
                            content: word + (isComplete ? "" : " "),
                            isComplete: isComplete
                        )
                        continuation.yield(chunk)
                        
                        if !isComplete {
                            try await Task.sleep(nanoseconds: 10_000_000) // 0.01 second delay for tests
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

// MARK: - Tests

@Suite struct LLMProtocolAdapterTests {
    
    @Test("LLMProtocolAdapter should be created with basic configuration")
    func testBasicConfiguration() throws {
        let testLLM = TestLLM(model: "test-model")
        let adapter = LLMProtocolAdapter(
            llm: testLLM,
            model: "test-model",
            maxTokens: 1000,
            temperature: 0.7
        )
        
        #expect(adapter.cardCapabilities.streaming == true)
        #expect(adapter.cardCapabilities.pushNotifications == false)
        #expect(adapter.cardCapabilities.stateTransitionHistory == true)
        #expect(adapter.skills.count == 2)
        #expect(adapter.defaultInputModes == ["text"])
        #expect(adapter.defaultOutputModes == ["text"])
    }
    
    @Test("LLMProtocolAdapter should handle basic message sending")
    func testHandleSend() async throws {
        let testLLM = TestLLM(model: "test-model")
        let adapter = LLMProtocolAdapter(
            llm: testLLM,
            model: "test-model",
            systemPrompt: "You are a test assistant."
        )
        
        let store = TaskStore()
        
        // Create a test message
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Hello, how are you?")],
            messageId: UUID().uuidString
        )
        
        let params = MessageSendParams(message: message)
        
        // Send the message
        let task = try await adapter.handleSend(params, store: store)
        
        #expect(task.status.state == .completed)
        #expect(task.history?.count == 2) // User message + assistant response
        #expect(task.history?[1].role == "assistant")
        if let history = task.history, history.count >= 2 {
            let response = history[1]
            if let firstPart = response.parts.first {
                switch firstPart {
                case .text(let text):
                    #expect(text.contains("Hello, how are you?"))
                default:
                    #expect(false, "Expected text part")
                }
            }
        }
    }
    
    @Test("LLMProtocolAdapter should handle streaming")
    func testHandleStream() async throws {
        let testLLM = TestLLM(model: "test-model")
        let adapter = LLMProtocolAdapter(
            llm: testLLM,
            model: "test-model"
        )
        
        let store = TaskStore()
        var receivedEvents: [Encodable] = []
        
        // Create a test message
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Stream this message")],
            messageId: UUID().uuidString
        )
        
        let params = MessageSendParams(message: message)
        
        // Stream the message
        try await adapter.handleStream(params, store: store) { event in
            receivedEvents.append(event)
        }
        
        #expect(receivedEvents.count > 0)
        
        // Check that the task was completed
        #expect(receivedEvents.count > 0)
    }
    
    @Test("LLMProtocolAdapter should handle conversation history")
    func testConversationHistory() async throws {
        let testLLM = TestLLM(model: "test-model")
        let adapter = LLMProtocolAdapter(
            llm: testLLM,
            model: "test-model"
        )
        
        let store = TaskStore()
        
        // First message
        let message1 = A2AMessage(
            role: "user",
            parts: [.text(text: "My name is Alice")],
            messageId: UUID().uuidString
        )
        
        let params1 = MessageSendParams(message: message1)
        let task1 = try await adapter.handleSend(params1, store: store)
        
        // Second message (should include history)
        let message2 = A2AMessage(
            role: "user",
            parts: [.text(text: "What's my name?")],
            messageId: UUID().uuidString
        )
        
        let params2 = MessageSendParams(message: message2)
        let task2 = try await adapter.handleSend(params2, store: store)
        
        #expect(task1.status.state == .completed)
        #expect(task2.status.state == .completed)
        #expect(task1.history?.count == 2)
        #expect(task2.history?.count == 2)
    }
    
    @Test("LLMProtocolAdapter should handle system prompts")
    func testSystemPrompt() async throws {
        let testLLM = TestLLM(model: "test-model")
        let adapter = LLMProtocolAdapter(
            llm: testLLM,
            model: "test-model",
            systemPrompt: "You are a helpful assistant that always responds with 'Hello from system prompt!'"
        )
        
        let store = TaskStore()
        
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Say hello")],
            messageId: UUID().uuidString
        )
        
        let params = MessageSendParams(message: message)
        let task = try await adapter.handleSend(params, store: store)
        
        #expect(task.status.state == .completed)
        // The TestLLM doesn't actually use the system prompt, so we just verify the task completed
        // In a real implementation, the LLM would use the system prompt
        if let history = task.history, history.count >= 2 {
            let response = history[1]
            if let firstPart = response.parts.first {
                switch firstPart {
                case .text(let text):
                    #expect(text.contains("Say hello")) // Verify it responded to the user message
                default:
                    #expect(false, "Expected text part")
                }
            }
        }
    }
    
    @Test("LLMProtocolAdapter should handle LLM errors gracefully")
    func testErrorHandling() async throws {
        let failingLLM = TestLLM(model: "test-model", shouldFail: true)
        let adapter = LLMProtocolAdapter(
            llm: failingLLM,
            model: "test-model"
        )
        
        let store = TaskStore()
        
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "This should fail")],
            messageId: UUID().uuidString
        )
        
        let params = MessageSendParams(message: message)
        let task = try await adapter.handleSend(params, store: store)
        
        #expect(task.status.state == .failed)
    }
    
    @Test("LLMProtocolAdapter should convert A2A roles correctly")
    func testRoleConversion() async throws {
        let testLLM = TestLLM(model: "test-model")
        let adapter = LLMProtocolAdapter(
            llm: testLLM,
            model: "test-model"
        )
        
        let store = TaskStore()
        
        // Test different roles
        let roles = ["user", "assistant", "system", "tool"]
        
        for role in roles {
            let message = A2AMessage(
                role: role,
                parts: [.text(text: "Test message")],
                messageId: UUID().uuidString
            )
            
            let params = MessageSendParams(message: message)
            let task = try await adapter.handleSend(params, store: store)
            
            #expect(task.status.state == .completed)
        }
    }
} 