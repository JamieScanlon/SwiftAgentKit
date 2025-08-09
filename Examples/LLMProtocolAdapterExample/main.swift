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

// MARK: - Example LLM Implementation

/// A simple example LLM that implements LLMProtocol
/// This demonstrates how any LLMProtocol implementation can be wrapped
struct ExampleLLM: LLMProtocol {
    let model: String
    let logger: Logger
    
    init(model: String = "example-llm") {
        self.model = model
        self.logger = Logger(label: "ExampleLLM")
    }
    
    func getModelName() -> String {
        return model
    }
    
    func getCapabilities() -> [LLMCapability] {
        return [.completion, .tools]
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
}

// MARK: - Test Function

func testLLMProtocolAdapter() async {
    print("Testing LLMProtocolAdapter...")
    
    // Create test LLM
    let exampleLLM = ExampleLLM(model: "example-llm-v1")
    
    // Create the LLMProtocolAdapter with configuration
    let adapter = LLMProtocolAdapter(
        llm: exampleLLM,
        model: "example-llm-v1",
        maxTokens: 1000,
        temperature: 0.7,
        systemPrompt: "You are a helpful assistant powered by the ExampleLLM."
    )
    
    // Test basic properties
    print("✓ Adapter created successfully")
    print("  - Capabilities: streaming=\(adapter.cardCapabilities.streaming), pushNotifications=\(adapter.cardCapabilities.pushNotifications)")
    print("  - Skills: \(adapter.skills.count)")
    print("  - Input modes: \(adapter.defaultInputModes)")
    print("  - Output modes: \(adapter.defaultOutputModes)")
    
    // Test message handling
    let store = TaskStore()
    
    let message = A2AMessage(
        role: "user",
        parts: [.text(text: "Hello, how are you?")],
        messageId: UUID().uuidString
    )
    
    let params = MessageSendParams(message: message)
    
    do {
        let task = try await adapter.handleSend(params, store: store)
        print("✓ Message handling successful")
        print("  - Task state: \(task.status.state)")
        print("  - History count: \(task.history?.count ?? 0)")
        
        if let history = task.history, history.count >= 2 {
            let response = history[1]
            print("  - Response role: \(response.role)")
            if let textPart = response.parts.first?.text {
                print("  - Response content: \(textPart)")
            }
        }
    } catch {
        print("✗ Message handling failed: \(error)")
    }
    
    // Test streaming
    print("\nTesting streaming...")
    var receivedEvents = 0
    
    do {
        try await adapter.handleStream(params, store: store) { event in
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

// MARK: - Main Example

@main
struct LLMProtocolAdapterExample {
    static func main() async throws {
        // Set up logging
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .info
            return handler
        }
        
        let logger = Logger(label: "LLMProtocolAdapterExample")
        logger.info("Starting LLMProtocolAdapter example...")
        
        // Run the test
        await testLLMProtocolAdapter()
        
        // Create an example LLM
        let exampleLLM = ExampleLLM(model: "example-llm-v1")
        
        // Create the LLMProtocolAdapter with configuration
        let adapter = LLMProtocolAdapter(
            llm: exampleLLM,
            model: "example-llm-v1",
            maxTokens: 1000,
            temperature: 0.7,
            systemPrompt: "You are a helpful assistant powered by the ExampleLLM."
        )
        
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