import Foundation
import SwiftAgentKitOrchestrator
import SwiftAgentKit
import Logging
import EasyJSON

// Mock LLM for demonstration
struct MockLLM: LLMProtocol {
    let model: String
    let logger: Logger
    
    init(model: String = "mock-gpt-4", logger: Logger) {
        self.model = model
        self.logger = logger
    }
    
    func getModelName() -> String {
        return model
    }
    
    func getCapabilities() -> [LLMCapability] {
        return [.completion, .tools]
    }
    
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        // Check if this is a tool response (contains tool messages)
        let hasToolMessages = messages.contains { $0.role == .tool }
        
        if hasToolMessages {
            logger.info("LLM received tool responses, generating final answer")
            return LLMResponse.complete(content: "Based on the tool results, here's my final answer: The weather is sunny and 75°F today.")
        } else {
            // Check if we should make a tool call
            let lastMessage = messages.last
            if lastMessage?.content.contains("weather") == true {
                logger.info("LLM making tool call for weather information")
                let toolCall = ToolCall(
                    name: "get_weather",
                    arguments: try! JSON(["location": "current"])
                )
                return LLMResponse.withToolCalls(
                    content: "I need to check the weather for you.",
                    toolCalls: [toolCall]
                )
            } else {
                return LLMResponse.complete(content: "Mock response from orchestrator")
            }
        }
    }
    
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                // Check if this is a tool response
                let hasToolMessages = messages.contains { $0.role == .tool }
                
                if hasToolMessages {
                    logger.info("LLM received tool responses, generating final streaming answer")
                    continuation.yield(.stream(LLMResponse.streamChunk("Based on the tool results, ")))
                    continuation.yield(.stream(LLMResponse.streamChunk("here's my final answer: ")))
                    continuation.yield(.complete(LLMResponse.complete(content: "The weather is sunny and 75°F today.")))
                } else {
                    // Check if we should make a tool call
                    let lastMessage = messages.last
                    if lastMessage?.content.contains("weather") == true {
                        logger.info("LLM making tool call for weather information")
                        // First yield some partial chunks
                        continuation.yield(.stream(LLMResponse.streamChunk("I need to ")))
                        continuation.yield(.stream(LLMResponse.streamChunk("check the weather ")))
                        continuation.yield(.stream(LLMResponse.streamChunk("for you.")))
                        
                        // Then yield the tool call
                        let toolCall = ToolCall(
                            name: "get_weather",
                            arguments: try! JSON(["location": "current"])
                        )
                        continuation.yield(.complete(LLMResponse.withToolCalls(
                            content: "I need to check the weather for you.",
                            toolCalls: [toolCall]
                        )))
                    } else {
                        // Yield partial chunks for regular responses
                        continuation.yield(.stream(LLMResponse.streamChunk("Mock ")))
                        continuation.yield(.stream(LLMResponse.streamChunk("streaming ")))
                        continuation.yield(.complete(LLMResponse.complete(content: "response from orchestrator")))
                    }
                }
                continuation.finish()
            }
        }
    }
}



// Set up logging
LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardOutput(label: label)
    handler.logLevel = .info
    return handler
}

let logger = Logger(label: "OrchestratorExample")

func main() async {
    logger.info("Starting SwiftAgentKitOrchestrator Example")
    
    // Create a mock LLM for demonstration
    let mockLLM = MockLLM(model: "mock-gpt-4", logger: logger)
    
    // Create orchestrator configuration
    let config = OrchestratorConfig(
        streamingEnabled: true,
        mcpEnabled: true,
        a2aEnabled: false
    )
    
    // Initialize the orchestrator
    let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM, config: config, logger: logger)
    logger.info("Orchestrator initialized successfully: \(orchestrator)")
    logger.info("Configuration - Streaming: \(config.streamingEnabled), MCP: \(config.mcpEnabled), A2A: \(config.a2aEnabled)")
    
    // Demonstrate conversation processing
    logger.info("Demonstrating conversation processing...")
    
    let conversation = [
        Message(id: UUID(), role: .user, content: "What's the weather like today?")
    ]
    
    do {
        // Get both streams
        let messageStream = await orchestrator.messageStream
        let partialContentStream = await orchestrator.partialContentStream
        logger.info("Processing conversation...")
        
        // Start listening to streams before processing
        _ = Task {
            for await message in messageStream {
                logger.info("Received final message: \(message.content)")
            }
        }
        
        _ = Task {
            for await partialContent in partialContentStream {
                logger.info("Received partial content: \(partialContent)")
            }
        }
        
        // Process the conversation (this will publish to the streams)
        do {
            try await orchestrator.updateConversation(conversation, availableTools: [])
        } catch {
            logger.error("Error processing conversation: \(error.localizedDescription)")
        }
        
        // The method has finished, but streams continue to exist
        logger.info("Conversation processing finished, streams remain active")
        logger.info("Conversation processed successfully!")
        logger.info("Original messages: \(conversation.count)")
    }
    
    logger.info("Orchestrator example completed")
}

// Run the example
await main() 