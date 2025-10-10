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
    
    func getCapabilities() -> [LLMCapability] {
        return [.completion, .tools]
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
    
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
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
                        
                        if isComplete {
                            continuation.yield(.complete(chunk))
                        } else {
                            continuation.yield(.stream(chunk))
                        }
                        
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
        #expect(adapter.defaultInputModes == ["text/plain"])
        #expect(adapter.defaultOutputModes == ["text/plain"])
    }
    
    @Test("LLMProtocolAdapter should support custom agent configuration")
    func testCustomAgentConfiguration() throws {
        let testLLM = TestLLM(model: "test-model")
        
        let customSkills = [
            AgentCard.AgentSkill(
                id: "custom-skill",
                name: "Custom Skill",
                description: "A custom skill for testing",
                tags: ["custom", "test"],
                inputModes: ["text/plain", "application/json"],
                outputModes: ["text/plain", "application/json"]
            )
        ]
        
        let customCapabilities = AgentCard.AgentCapabilities(
            streaming: false,
            pushNotifications: true,
            stateTransitionHistory: false
        )
        
        let adapter = LLMProtocolAdapter(
            llm: testLLM,
            model: "test-model",
            agentName: "Custom Test Agent",
            agentDescription: "A custom test agent with specific configuration",
            cardCapabilities: customCapabilities,
            skills: customSkills,
            defaultInputModes: ["text/plain", "application/json"],
            defaultOutputModes: ["text/plain", "application/json"]
        )
        
        #expect(adapter.agentName == "Custom Test Agent")
        #expect(adapter.agentDescription == "A custom test agent with specific configuration")
        #expect(adapter.cardCapabilities.streaming == false)
        #expect(adapter.cardCapabilities.pushNotifications == true)
        #expect(adapter.cardCapabilities.stateTransitionHistory == false)
        #expect(adapter.skills.count == 1)
        #expect(adapter.skills.first?.id == "custom-skill")
        #expect(adapter.defaultInputModes == ["text/plain", "application/json"])
        #expect(adapter.defaultOutputModes == ["text/plain", "application/json"])
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
        
        // Create and register a task
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(state: .submitted)
        )
        await store.addTask(task: task)
        
        // Send the message
        try await adapter.handleTaskSend(params, taskId: task.id, contextId: task.contextId, store: store)
        
        // Verify task state and artifacts
        if let updatedTask = await store.getTask(id: task.id) {
            #expect(updatedTask.status.state == .completed)
            #expect((updatedTask.artifacts?.count ?? 0) == 1)
            if let artifact = updatedTask.artifacts?.first,
               let firstPart = artifact.parts.first,
               case .text(let text) = firstPart {
                #expect(text.contains("Hello, how are you?"))
            } else {
                #expect(false, "Expected text artifact part")
            }
        } else {
            #expect(false, "Task not found in store")
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
        
        // Create and register a task
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(state: .submitted)
        )
        await store.addTask(task: task)
        
        // Stream the message
        try await adapter.handleStream(params, taskId: task.id, contextId: task.contextId, store: store) { event in
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
        // Create task1 and register
        let task1 = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(state: .submitted)
        )
        await store.addTask(task: task1)
        try await adapter.handleTaskSend(params1, taskId: task1.id, contextId: task1.contextId, store: store)
        
        // Second message (should include history)
        let message2 = A2AMessage(
            role: "user",
            parts: [.text(text: "What's my name?")],
            messageId: UUID().uuidString
        )
        
        let params2 = MessageSendParams(message: message2)
        // Create task2 with prior history and register
        let task2 = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(state: .submitted),
            history: [message1]
        )
        await store.addTask(task: task2)
        try await adapter.handleTaskSend(params2, taskId: task2.id, contextId: task2.contextId, store: store)
        
        let updatedTask1 = await store.getTask(id: task1.id)
        let updatedTask2 = await store.getTask(id: task2.id)
        #expect(updatedTask1?.status.state == .completed)
        #expect(updatedTask2?.status.state == .completed)
        #expect((updatedTask1?.artifacts?.count ?? 0) == 1)
        #expect((updatedTask2?.artifacts?.count ?? 0) == 1)
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
        // Create and register a task
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(state: .submitted)
        )
        await store.addTask(task: task)
        
        let _ = try await adapter.handleTaskSend(params, taskId: task.id, contextId: task.contextId, store: store)
        
        if let updatedTask = await store.getTask(id: task.id) {
            #expect(updatedTask.status.state == .completed)
            if let artifact = updatedTask.artifacts?.first,
               let firstPart = artifact.parts.first,
               case .text(let text) = firstPart {
                #expect(text.contains("Say hello"))
            } else {
                #expect(false, "Expected text artifact part")
            }
        } else {
            #expect(false, "Task not found in store")
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
        // Create and register a task
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(state: .submitted)
        )
        await store.addTask(task: task)
        
        do {
            try await adapter.handleTaskSend(params, taskId: task.id, contextId: task.contextId, store: store)
            #expect(false, "Expected handleSend to throw")
        } catch {
            // Expected
        }
        
        if let updatedTask = await store.getTask(id: task.id) {
            #expect(updatedTask.status.state == .failed)
        } else {
            #expect(false, "Task not found in store")
        }
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
            let task = A2ATask(
                id: UUID().uuidString,
                contextId: UUID().uuidString,
                status: TaskStatus(state: .submitted)
            )
            await store.addTask(task: task)
            try await adapter.handleTaskSend(params, taskId: task.id, contextId: task.contextId, store: store)
            let updatedTask = await store.getTask(id: task.id)
            #expect(updatedTask?.status.state == .completed)
        }
    }
} 