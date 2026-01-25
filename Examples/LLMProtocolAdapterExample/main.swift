//
//  main.swift
//  LLMProtocolAdapterExample
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitAdapters
import Logging
import EasyJSON

private func configureLogging() {
    SwiftAgentKitLogging.bootstrap(
        logger: Logger(label: "com.example.swiftagentkit.llmprotocoladapter"),
        level: .info,
        metadata: SwiftAgentKitLogging.metadata(("example", .string("LLMProtocolAdapter")))
    )
}

// MARK: - Example LLM Implementation

/// A simple example LLM that implements LLMProtocol
/// This demonstrates how any LLMProtocol implementation can be wrapped
struct ExampleLLM: LLMProtocol {
    let model: String
    let logger: Logger
    
    init(model: String = "example-llm") {
        self.model = model
        configureLogging()
        self.logger = SwiftAgentKitLogging.logger(
            for: .examples("LLMProtocolAdapterExample.ExampleLLM"),
            metadata: SwiftAgentKitLogging.metadata(("model", .string(model)))
        )
    }
    
    func getModelName() -> String {
        return model
    }
    
    func getCapabilities() -> [LLMCapability] {
        return [.completion, .tools, .imageGeneration]
    }
    
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        logger.info("Processing \(messages.count) messages")
        
        // Extract the last user message
        let lastUserMessage = messages.last { $0.role == .user }?.content ?? "Hello"
        
        // Generate a simple response
        let response = "This is a response from the ExampleLLM. You said: '\(lastUserMessage)'. Model: \(model)"
        
        return LLMResponse(
            content: response,
            metadata: LLMMetadata(
                promptTokens: 10,
                completionTokens: response.count / 4,
                totalTokens: 10 + (response.count / 4),
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
                            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
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
        if let image = config.image {
            logger.info("Generating/editing image with prompt: '\(config.prompt)', input image: \(config.fileName ?? "unnamed")")
        } else {
            logger.info("Generating image (pure generation) with prompt: '\(config.prompt)'")
        }
        
        // Create temporary directory for generated images
        let tempDir = FileManager.default.temporaryDirectory
        let imageCount = config.n ?? 1
        
        var imageURLs: [URL] = []
        
        for i in 0..<imageCount {
            // Create a simple test image file (in real implementation, you'd generate actual images)
            let imageURL = tempDir.appendingPathComponent("generated-image-\(UUID().uuidString).png")
            
            // Create a minimal PNG file for demonstration
            // In a real implementation, you would generate actual images here
            let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // PNG signature
            try pngHeader.write(to: imageURL)
            
            imageURLs.append(imageURL)
            logger.info("Generated image \(i + 1)/\(imageCount) at: \(imageURL.path)")
        }
        
        return ImageGenerationResponse(
            images: imageURLs,
            createdAt: Date(),
            metadata: LLMMetadata(
                totalTokens: 100
            )
        )
    }
}

// MARK: - Test Function

func testLLMProtocolAdapter() async {
    print("Testing LLMProtocolAdapter...")
    
    // Create test LLM
    let exampleLLM = ExampleLLM(model: "example-llm-v1")
    
    // Create the LLMProtocolAdapter with configuration
    var systemPrompt = DynamicPrompt(template: "You are a helpful assistant powered by the ExampleLLM.")
    let adapter = LLMProtocolAdapter(
        llm: exampleLLM,
        model: "example-llm-v1",
        maxTokens: 1000,
        temperature: 0.7,
        systemPrompt: systemPrompt
    )
    
    // Test basic properties
    print("✓ Adapter created successfully")
    print("  - Agent name: \(adapter.agentName)")
    print("  - Agent description: \(adapter.agentDescription)")
    let capabilities = adapter.cardCapabilities
    print("  - Capabilities: streaming=\(capabilities.streaming == true), pushNotifications=\(capabilities.pushNotifications == true)")
    print("  - Skills: \(adapter.skills.count)")
    let inputModes = adapter.defaultInputModes.joined(separator: ", ")
    let outputModes = adapter.defaultOutputModes.joined(separator: ", ")
    print("  - Input modes: \(inputModes)")
    print("  - Output modes: \(outputModes)")
    
    // Test custom configuration
    print("\nTesting custom configuration...")
    var customPrompt = DynamicPrompt(template: "You are a specialized coding assistant.")
    let customAdapter = LLMProtocolAdapter(
        llm: exampleLLM,
        model: "example-llm-v1",
        maxTokens: 500,
        temperature: 0.3,
        systemPrompt: customPrompt,
        agentName: "Custom Coding Agent",
        agentDescription: "A specialized agent for coding tasks and technical questions",
        cardCapabilities: AgentCard.AgentCapabilities(
            streaming: false,
            pushNotifications: true,
            stateTransitionHistory: true
        ),
        skills: [
            AgentCard.AgentSkill(
                id: "code-generation",
                name: "Code Generation",
                description: "Generate code in various programming languages",
                tags: ["coding", "programming"],
                inputModes: ["text/plain", "application/json"],
                outputModes: ["text/plain", "application/json"]
            )
        ],
        defaultInputModes: ["text/plain", "application/json"],
        defaultOutputModes: ["text/plain", "application/json"]
    )
    
    print("✓ Custom adapter created successfully")
    print("  - Agent name: \(customAdapter.agentName)")
    print("  - Agent description: \(customAdapter.agentDescription)")
    let customCapabilities = customAdapter.cardCapabilities
    print("  - Capabilities: streaming=\(customCapabilities.streaming == true), pushNotifications=\(customCapabilities.pushNotifications == true)")
    print("  - Skills: \(customAdapter.skills.count)")
    let customInputModes = customAdapter.defaultInputModes.joined(separator: ", ")
    let customOutputModes = customAdapter.defaultOutputModes.joined(separator: ", ")
    print("  - Input modes: \(customInputModes)")
    print("  - Output modes: \(customOutputModes)")
    
    // Test message handling
    let store = TaskStore()
    
    let message = A2AMessage(
        role: "user",
        parts: [.text(text: "Hello, how are you?")],
        messageId: UUID().uuidString
    )
    
    let params = MessageSendParams(message: message)
    let task = A2ATask(
        id: UUID().uuidString,
        contextId: UUID().uuidString,
        status: TaskStatus(
            state: .submitted,
            timestamp: ISO8601DateFormatter().string(from: .init())
        ),
        history: [params.message]
    )
    await store.addTask(task: task)
    
    do {
        try await adapter.handleTaskSend(params, taskId: task.id, contextId: task.contextId, store: store)
        
        if let updatedTask = await store.getTask(id: task.id) {
            print("✓ Message handling successful")
            print("  - Task state: \(updatedTask.status.state)")
            print("  - History count: \(updatedTask.history?.count ?? 0)")
            
            if let history = updatedTask.history, history.count >= 2 {
                let response = history[1]
                print("  - Response role: \(response.role)")
                if case .text(let text) = response.parts.first {
                    print("  - Response content: \(text)")
                }
            }
        }
    } catch {
        print("✗ Message handling failed: \(error)")
    }
    
    // Test streaming
    print("\nTesting streaming...")
    var receivedEvents = 0
    
    do {
        try await adapter.handleStream(params, taskId: task.id, contextId: task.contextId, store: store) { event in
            receivedEvents += 1
            print("  - Received streaming event \(receivedEvents)")
        }
        print("✓ Streaming successful")
        print("  - Received \(receivedEvents) events")
    } catch {
        print("✗ Streaming failed: \(error)")
    }
    
    print("\nAll tests completed!")
}

// MARK: - Image Generation Example

func testImageGeneration() async {
    print("\nTesting Image Generation...")
    
    // Create LLM with image generation support
    let imageLLM = ExampleLLM(model: "image-generating-llm")
    let adapter = LLMProtocolAdapter(
        llm: imageLLM,
        model: "image-generating-llm",
        maxTokens: 1000,
        temperature: 0.7
    )
    
    let store = TaskStore()
    
    // Create a message requesting image generation (pure generation - no input image needed)
    // The key is specifying image output modes in acceptedOutputModes
    let message = A2AMessage(
        role: "user",
        parts: [
            .text(text: "Generate a beautiful sunset over mountains")
        ],
        messageId: UUID().uuidString
    )
    
    // Client accepts image output - this triggers image generation
    let config = MessageSendConfiguration(
        acceptedOutputModes: ["image/png", "text/plain"]
    )
    
    let params = MessageSendParams(
        message: message,
        configuration: config,
        metadata: try? JSON(["n": 2])  // Optional: request 2 images
    )
    
    let task = A2ATask(
        id: UUID().uuidString,
        contextId: UUID().uuidString,
        status: TaskStatus(
            state: .submitted,
            timestamp: ISO8601DateFormatter().string(from: .init())
        )
    )
    await store.addTask(task: task)
    
    do {
        try await adapter.handleTaskSend(params, taskId: task.id, contextId: task.contextId, store: store)
        
        if let updatedTask = await store.getTask(id: task.id) {
            print("✓ Image generation successful")
            print("  - Task state: \(updatedTask.status.state)")
            print("  - Artifacts count: \(updatedTask.artifacts?.count ?? 0)")
            
            if let artifacts = updatedTask.artifacts {
                for (index, artifact) in artifacts.enumerated() {
                    print("  - Artifact \(index + 1):")
                    print("    - Name: \(artifact.name ?? "unnamed")")
                    print("    - Parts: \(artifact.parts.count)")
                    
                    for part in artifact.parts {
                        if case .file(_, let url) = part {
                            print("    - Image URL: \(url?.path ?? "nil")")
                        }
                    }
                    
                    // Check metadata for MIME type
                    if let metadata = artifact.metadata?.literalValue as? [String: Any],
                       let mimeType = metadata["mimeType"] as? String {
                        print("    - MIME Type: \(mimeType)")
                    }
                }
            }
        }
    } catch {
        print("✗ Image generation failed: \(error)")
    }
    
    // Test streaming image generation
    print("\nTesting streaming image generation...")
    var receivedEvents = 0
    
    let streamTask = A2ATask(
        id: UUID().uuidString,
        contextId: UUID().uuidString,
        status: TaskStatus(
            state: .submitted,
            timestamp: ISO8601DateFormatter().string(from: .init())
        )
    )
    await store.addTask(task: streamTask)
    
    do {
        try await adapter.handleStream(
            params,
            taskId: streamTask.id,
            contextId: streamTask.contextId,
            store: store
        ) { event in
            receivedEvents += 1
            print("  - Received streaming event \(receivedEvents)")
        }
        
        print("✓ Streaming image generation successful")
        print("  - Received \(receivedEvents) events")
        
        if let updatedTask = await store.getTask(id: streamTask.id) {
            print("  - Final artifacts: \(updatedTask.artifacts?.count ?? 0)")
        }
    } catch {
        print("✗ Streaming image generation failed: \(error)")
    }
    
    print("\nImage generation tests completed!")
}

// MARK: - Main Example

struct LLMProtocolAdapterExample {
    static func main() async throws {
        configureLogging()
        let logger = SwiftAgentKitLogging.logger(for: .examples("LLMProtocolAdapterExample"))
        logger.info("Starting LLMProtocolAdapter example...")
        
        // Run the tests
        await testLLMProtocolAdapter()
        await testImageGeneration()
        
        // Create an example LLM
        let exampleLLM = ExampleLLM(model: "example-llm-v1")
        
        // Create the LLMProtocolAdapter with configuration
        var mainPrompt = DynamicPrompt(template: "You are a helpful assistant powered by the ExampleLLM.")
        let adapter = LLMProtocolAdapter(
            llm: exampleLLM,
            model: "example-llm-v1",
            maxTokens: 1000,
            temperature: 0.7,
            systemPrompt: mainPrompt,
            agentName: "Example LLM Agent",
            agentDescription: "A demonstration agent using the ExampleLLM implementation"
        )
        
        logger.info("Created LLMProtocolAdapter:")
        logger.info("  - Agent name: \(adapter.agentName)")
        logger.info("  - Agent description: \(adapter.agentDescription)")
        logger.info("  - Skills: \(adapter.skills.count)")
        logger.info("  - Capabilities: streaming=\(adapter.cardCapabilities.streaming == true)")
        
        // Create an A2A server with the adapter
        let server = A2AServer(port: 4245, adapter: adapter)
        
        logger.info("Starting A2A server on port 4245...")
        try await server.start()
        
        logger.info("Server started successfully!")
        logger.info("You can now send requests to http://localhost:4245")
        logger.info("Press Ctrl+C to stop the server")
        
        // Keep the server running
        try await Task.sleep(nanoseconds: UInt64.max)
    }
} 
