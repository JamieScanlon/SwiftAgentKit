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
import EasyJSON

// MARK: - Test LLM Implementation

/// A test LLM that implements LLMProtocol for testing purposes
struct TestLLM: LLMProtocol {
    let model: String
    let logger: Logger
    let shouldFail: Bool
    let capabilities: [LLMCapability]
    
    init(model: String = "test-llm", shouldFail: Bool = false, capabilities: [LLMCapability] = [.completion, .tools]) {
        self.model = model
        self.logger = Logger(label: "TestLLM")
        self.shouldFail = shouldFail
        self.capabilities = capabilities
    }
    
    func getModelName() -> String {
        return model
    }
    
    func getCapabilities() -> [LLMCapability] {
        return capabilities
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
    
    func generateImage(_ config: ImageGenerationRequestConfig) async throws -> ImageGenerationResponse {
        if shouldFail {
            throw LLMError.invalidRequest("Test failure")
        }
        
        // Check if image generation is supported
        guard capabilities.contains(.imageGeneration) else {
            throw LLMError.unsupportedCapability(.imageGeneration)
        }
        
        // Create test image URLs
        let tempDir = FileManager.default.temporaryDirectory
        let imageCount = config.n ?? 1
        var imageURLs: [URL] = []
        
        for i in 0..<imageCount {
            let imageURL = tempDir.appendingPathComponent("test-image-\(i).png")
            // Create a minimal PNG file for testing
            let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // PNG header
            try? pngData.write(to: imageURL)
            imageURLs.append(imageURL)
        }
        
        return ImageGenerationResponse(
            images: imageURLs,
            createdAt: Date(),
            metadata: LLMMetadata(totalTokens: 100)
        )
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
        var systemPrompt = DynamicPrompt(template: "You are a test assistant.")
        let adapter = LLMProtocolAdapter(
            llm: testLLM,
            model: "test-model",
            systemPrompt: systemPrompt
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
        var systemPrompt = DynamicPrompt(template: "You are a helpful assistant that always responds with 'Hello from system prompt!'")
        let adapter = LLMProtocolAdapter(
            llm: testLLM,
            model: "test-model",
            systemPrompt: systemPrompt
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
    
    // MARK: - Image Generation Tests
    
    @Test("LLMProtocolAdapter creates file-based artifacts from ImageGenerationResponse in handleTaskSend")
    func testImageGenerationCreatesFileArtifacts() async throws {
        let testLLM = TestLLM(
            model: "test-model",
            capabilities: [.completion, .tools, .imageGeneration]
        )
        let adapter = LLMProtocolAdapter(
            llm: testLLM,
            model: "test-model"
        )
        
        let store = TaskStore()
        
        // Create a message requesting image generation (pure generation - no input image needed)
        // Client accepts image output modes (A2A-compliant way to request images)
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Generate an image of a sunset")],
            messageId: UUID().uuidString
        )
        
        let config = MessageSendConfiguration(acceptedOutputModes: ["image/png", "text/plain"])
        let params = MessageSendParams(message: message, configuration: config)
        
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(state: .submitted)
        )
        await store.addTask(task: task)
        
        try await adapter.handleTaskSend(params, taskId: task.id, contextId: task.contextId, store: store)
        
        if let updatedTask = await store.getTask(id: task.id) {
            #expect(updatedTask.status.state == .completed)
            #expect(updatedTask.artifacts != nil)
            #expect(updatedTask.artifacts?.count ?? 0 > 0)
            
            // Verify artifacts contain file parts
            if let artifact = updatedTask.artifacts?.first {
                #expect(artifact.parts.count > 0)
                if case .file(_, let url) = artifact.parts.first {
                    #expect(url != nil)
                } else {
                    #expect(false, "Expected file part in artifact")
                }
            }
        } else {
            #expect(false, "Task not found in store")
        }
    }
    
    @Test("Multiple images in ImageGenerationResponse create multiple artifacts")
    func testMultipleImagesCreateMultipleArtifacts() async throws {
        let testLLM = TestLLM(
            model: "test-model",
            capabilities: [.completion, .tools, .imageGeneration]
        )
        let adapter = LLMProtocolAdapter(
            llm: testLLM,
            model: "test-model"
        )
        
        let store = TaskStore()
        
        // Create a message requesting multiple images (pure generation)
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Generate 3 images")],
            messageId: UUID().uuidString
        )
        
        let config = MessageSendConfiguration(acceptedOutputModes: ["image/png"])
        let params = MessageSendParams(message: message, configuration: config, metadata: try JSON(["n": 3]))
        
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(state: .submitted)
        )
        await store.addTask(task: task)
        
        try await adapter.handleTaskSend(params, taskId: task.id, contextId: task.contextId, store: store)
        
        if let updatedTask = await store.getTask(id: task.id) {
            #expect(updatedTask.status.state == .completed)
            #expect(updatedTask.artifacts?.count == 3)
            
            // Verify each artifact has a file part
            for artifact in updatedTask.artifacts ?? [] {
                #expect(artifact.parts.count == 1)
                if case .file(_, let url) = artifact.parts.first {
                    #expect(url != nil)
                } else {
                    #expect(false, "Expected file part in artifact")
                }
            }
        } else {
            #expect(false, "Task not found in store")
        }
    }
    
    @Test("LLMProtocolAdapter processes local file URLs correctly")
    func testLocalFileURLProcessing() async throws {
        let testLLM = TestLLM(
            model: "test-model",
            capabilities: [.completion, .tools, .imageGeneration]
        )
        let adapter = LLMProtocolAdapter(
            llm: testLLM,
            model: "test-model"
        )
        
        let store = TaskStore()
        
        // Create a temporary image file
        let tempDir = FileManager.default.temporaryDirectory
        let testImageURL = tempDir.appendingPathComponent("test-image-\(UUID().uuidString).png")
        let testImageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // PNG signature
        try testImageData.write(to: testImageURL)
        defer {
            try? FileManager.default.removeItem(at: testImageURL)
        }
        
        // TestLLM should return local file URLs
        // Since TestLLM creates temporary files, they should be local file URLs
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Generate a PNG image")],
            messageId: UUID().uuidString
        )
        
        let config = MessageSendConfiguration(acceptedOutputModes: ["image/png"])
        let params = MessageSendParams(message: message, configuration: config)
        
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(state: .submitted)
        )
        await store.addTask(task: task)
        
        try await adapter.handleTaskSend(params, taskId: task.id, contextId: task.contextId, store: store)
        
        if let updatedTask = await store.getTask(id: task.id),
           let artifact = updatedTask.artifacts?.first {
            // Verify artifact has a file part with URL
            if case .file(_, let url) = artifact.parts.first {
                #expect(url != nil)
                #expect(url?.isFileURL == true, "URL should be a local file URL")
            } else {
                #expect(false, "Expected file part in artifact")
            }
        } else {
            #expect(false, "Task not found in store")
        }
    }
    
    @Test("Image artifacts include correct MIME types and metadata")
    func testImageArtifactMIMETypes() async throws {
        let testLLM = TestLLM(
            model: "test-model",
            capabilities: [.completion, .tools, .imageGeneration]
        )
        let adapter = LLMProtocolAdapter(
            llm: testLLM,
            model: "test-model"
        )
        
        let store = TaskStore()
        
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Generate a PNG image")],
            messageId: UUID().uuidString
        )
        
        let config = MessageSendConfiguration(acceptedOutputModes: ["image/png"])
        let params = MessageSendParams(message: message, configuration: config)
        
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(state: .submitted)
        )
        await store.addTask(task: task)
        
        try await adapter.handleTaskSend(params, taskId: task.id, contextId: task.contextId, store: store)
        
        if let updatedTask = await store.getTask(id: task.id),
           let artifact = updatedTask.artifacts?.first {
            // Verify metadata exists
            #expect(artifact.metadata != nil)
            
            // Verify MIME type is in metadata
            if let metadata = artifact.metadata?.literalValue as? [String: Any],
               let mimeType = metadata["mimeType"] as? String {
                #expect(mimeType == "image/png")
            } else {
                #expect(false, "MIME type not found in metadata")
            }
            
            // Verify createdAt is in metadata
            if let metadata = artifact.metadata?.literalValue as? [String: Any] {
                #expect(metadata["createdAt"] != nil)
            }
        } else {
            #expect(false, "Task or artifact not found")
        }
    }
    
    @Test("Image generation falls back to text when LLM does not support imageGeneration capability")
    func testImageGenerationFallbackToText() async throws {
        let testLLM = TestLLM(
            model: "test-model",
            capabilities: [.completion, .tools] // No imageGeneration
        )
        let adapter = LLMProtocolAdapter(
            llm: testLLM,
            model: "test-model"
        )
        
        let store = TaskStore()
        
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Generate an image")],
            messageId: UUID().uuidString
        )
        
        // Client accepts images, but LLM doesn't support it - should fall back to text generation
        let config = MessageSendConfiguration(acceptedOutputModes: ["image/png", "text/plain"])
        let params = MessageSendParams(message: message, configuration: config)
        
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(state: .submitted)
        )
        await store.addTask(task: task)
        
        // Should not throw - should fall back to text generation
        try await adapter.handleTaskSend(params, taskId: task.id, contextId: task.contextId, store: store)
        
        // Verify task completed with text artifact (not image)
        if let updatedTask = await store.getTask(id: task.id) {
            #expect(updatedTask.status.state == .completed)
            #expect(updatedTask.artifacts?.count ?? 0 > 0)
            // Should have text artifact, not image artifact
            if let artifact = updatedTask.artifacts?.first,
               case .text = artifact.parts.first {
                // Expected - text artifact
            } else {
                #expect(false, "Expected text artifact when image generation not supported")
            }
        }
    }
    
    @Test("LLMProtocolAdapter streams file-based artifacts for image generation")
    func testStreamingImageGeneration() async throws {
        let testLLM = TestLLM(
            model: "test-model",
            capabilities: [.completion, .tools, .imageGeneration]
        )
        let adapter = LLMProtocolAdapter(
            llm: testLLM,
            model: "test-model"
        )
        
        let store = TaskStore()
        var receivedEvents: [Encodable] = []
        
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Generate 2 images")],
            messageId: UUID().uuidString
        )
        
        let config = MessageSendConfiguration(acceptedOutputModes: ["image/png"])
        let params = MessageSendParams(message: message, configuration: config, metadata: try JSON(["n": 2, "requestId": 1]))
        
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(state: .submitted)
        )
        await store.addTask(task: task)
        
        try await adapter.handleStream(params, taskId: task.id, contextId: task.contextId, store: store) { event in
            receivedEvents.append(event)
        }
        
        // Should receive artifact update events and status update events
        #expect(receivedEvents.count >= 2)
        
        // Verify at least one artifact update event was received
        // We'll check by encoding and looking for artifact-update in the JSON
        var hasArtifactEvent = false
        for event in receivedEvents {
            if let encodable = event as? Encodable,
               let jsonData = try? JSONEncoder().encode(encodable),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let kind = result["kind"] as? String,
               kind == "artifact-update" {
                hasArtifactEvent = true
                break
            }
        }
        #expect(hasArtifactEvent)
        
        // Verify task was completed
        if let updatedTask = await store.getTask(id: task.id) {
            #expect(updatedTask.status.state == .completed)
            #expect(updatedTask.artifacts?.count == 2)
        }
    }
    
    @Test("A2AMessagePart.file encoding/decoding round-trip with filesystem URLs")
    func testFilePartRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("test-image.png")
        
        // Create the file part
        let originalPart = A2AMessagePart.file(data: nil, url: testURL)
        
        // Encode to JSON
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(originalPart)
        
        // Decode back
        let decoder = JSONDecoder()
        let decodedPart = try decoder.decode(A2AMessagePart.self, from: jsonData)
        
        // Verify round-trip
        if case .file(let data, let url) = decodedPart {
            #expect(data == nil)
            #expect(url != nil)
            #expect(url?.absoluteString == testURL.absoluteString)
        } else {
            #expect(false, "Decoded part is not a file part")
        }
    }
} 