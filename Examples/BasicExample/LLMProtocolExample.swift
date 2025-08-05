import Foundation
import SwiftAgentKit
import Logging
import EasyJSON

// Example implementation of LLMProtocol for demonstration
struct MockLLM: LLMProtocol {
    let model: String
    let logger: Logger
    
    init(model: String = "mock-gpt-4", logger: Logger) {
        self.model = model
        self.logger = logger
    }
    
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        logger.info("MockLLM: Processing \(messages.count) messages with model \(model)")
        
        // Simulate processing time
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Create a mock response
        let responseContent = "This is a mock response from \(model). I received \(messages.count) messages."
        
        return LLMResponse.complete(content: responseContent)
    }
    
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<LLMResponse, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                logger.info("MockLLM: Starting stream for \(messages.count) messages with model \(model)")
                
                // Simulate streaming response
                let words = ["Hello", "from", "the", "mock", "LLM", "streaming", "response"]
                
                for (_, word) in words.enumerated() {
                    try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                    
                    continuation.yield(LLMResponse.streamChunk(word))
                }
                
                // Final complete message
                continuation.yield(LLMResponse.complete(content: "Streaming complete!"))
                continuation.finish()
            }
        }
    }
}

// Example usage function
func demonstrateLLMProtocol() async {
    // Set up logging
    LoggingSystem.bootstrap { label in
        var handler = StreamLogHandler.standardOutput(label: label)
        handler.logLevel = .info
        return handler
    }
    
    let logger = Logger(label: "LLMProtocolExample")
    
    // Create a mock LLM
    let mockLLM = MockLLM(model: "mock-gpt-4", logger: logger)
    
    // Create a test message
    let message = Message(
        id: UUID(),
        role: .user,
        content: "Hello, can you help me with a question?"
    )
    
    // Create configuration
    let config = LLMRequestConfig(
        maxTokens: 1000,
        temperature: 0.7,
        stream: false,
        additionalParameters: .object(["custom_param": .string("value")])
    )
    
    logger.info("Starting LLM Protocol demonstration...")
    
    // Test synchronous request
    do {
        let response = try await mockLLM.send(message, config: config)
        
        logger.info("Received complete response: \(response.content)")
        if response.hasToolCalls {
            logger.info("Response contains \(response.toolCalls.count) tool calls")
        }
        if let totalTokens = response.totalTokens {
            logger.info("Total tokens used: \(totalTokens)")
        }
    } catch {
        logger.error("Error sending message: \(error.localizedDescription)")
    }
    
    // Test streaming request
    logger.info("Testing streaming response...")
    
    let streamingConfig = LLMRequestConfig(
        maxTokens: 1000,
        temperature: 0.7,
        stream: true,
        additionalParameters: .object(["streaming_param": .string("value")])
    )
    
    let stream = mockLLM.stream(message, config: streamingConfig)
    
    do {
        for try await response in stream {
            if response.isComplete {
                logger.info("Stream complete: \(response.content)")
                if response.hasToolCalls {
                    logger.info("Final response contains \(response.toolCalls.count) tool calls")
                }
            } else {
                logger.info("Stream chunk: \(response.content)")
            }
        }
    } catch {
        logger.error("Error in stream: \(error.localizedDescription)")
    }
    
    logger.info("LLM Protocol demonstration completed!")
} 