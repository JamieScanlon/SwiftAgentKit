import Foundation
import SwiftAgentKitAdapters
import SwiftAgentKitA2A
import Logging

@main
struct OpenAIAdapterExample {
    static func main() async throws {
        // Set up logging
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .info
            return handler
        }
        
        let logger = Logger(label: "OpenAIAdapterExample")
        logger.info("Starting OpenAI Adapter Example")
        
        // Create OpenAI adapter with MacPaw OpenAI package and custom configuration
        // This demonstrates the full configuration options available:
        // - apiKey: Your OpenAI API key
        // - model: The model to use (gpt-4o, gpt-4, etc.)
        // - systemPrompt: Optional system prompt to set behavior
        // - baseURL: Custom API endpoint (useful for proxies or custom deployments)
        // - organizationIdentifier: OpenAI organization ID for billing
        // - timeoutInterval: Request timeout in seconds
        // - customHeaders: Additional HTTP headers
        // - parsingOptions: Response parsing behavior (.relaxed for better compatibility)
        let openAIAdapter = OpenAIAdapter(
            apiKey: "your-api-key-here", // Replace with your actual API key
            model: "gpt-4o",
            systemPrompt: "You are a helpful AI assistant.",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            organizationIdentifier: "your-org-id", // Optional: Add your OpenAI organization ID
            timeoutInterval: 120.0, // 2 minutes timeout
            customHeaders: [
                "X-Custom-Header": "CustomValue"
            ],
            parsingOptions: .relaxed // Use relaxed parsing for better compatibility
        )
        
        // Create a simple task store
        let taskStore = TaskStore()
        
        // Create a test message
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Hello! Can you tell me a short joke?")],
            messageId: UUID().uuidString,
            taskId: UUID().uuidString,
            contextId: UUID().uuidString
        )
        
        let params = MessageSendParams(message: message)
        
        logger.info("Sending message to OpenAI...")
        
        do {
            // Test non-streaming
            let task = try await openAIAdapter.handleSend(params, store: taskStore)
            if let firstPart = task.status.message?.parts.first,
               case .text(let text) = firstPart {
                logger.info("Response received: \(text)")
            } else {
                logger.info("Response received: No content")
            }
            
            // Test streaming
            logger.info("Testing streaming...")
            try await openAIAdapter.handleStream(params, store: taskStore) { @Sendable event in
                logger.info("Stream event received: \(type(of: event))")
            }
            
        } catch {
            logger.error("Error: \(error)")
        }
        
        logger.info("Example completed!")
    }
} 
