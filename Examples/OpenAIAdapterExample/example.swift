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
        logger.info("This example demonstrates the enhanced OpenAI adapter that can handle:")
        logger.info("- Text content in response messages")
        logger.info("- Tool calls as separate message parts")
        logger.info("- Mixed content types in a single response")
        
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
        
        let taskID = UUID().uuidString
        let params = MessageSendParams(message: message)
        var task = A2ATask(
            id: taskID,
            contextId: UUID().uuidString,
            status: TaskStatus(
                state: .submitted,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            history: [params.message]
        )
        await taskStore.addTask(task: task)
        
        logger.info("Sending message to OpenAI...")
        
        do {
            // Test non-streaming
            try await openAIAdapter.handleSend(params, task: task, store: taskStore)
            
            task = await taskStore.getTask(id: taskID)!
            // The response message can now contain multiple parts:
            // - Text content (.text)
            // - Tool calls (.data with tool call information)
            // - File content (.file)
            if let message = task.status.message {
                logger.info("Response received with \(message.parts.count) parts:")
                for (index, part) in message.parts.enumerated() {
                    switch part {
                    case .text(let text):
                        logger.info("  Part \(index + 1): Text - \(text)")
                    case .data(let data):
                        logger.info("  Part \(index + 1): Data (tool call) - \(data.count) bytes")
                    case .file(let data, let url):
                        logger.info("  Part \(index + 1): File - URL: \(url?.absoluteString ?? "nil"), Data: \(data?.count ?? 0) bytes")
                    }
                }
            } else {
                logger.info("Response received: No content")
            }
            
            // Test streaming
            logger.info("Testing streaming...")
            try await openAIAdapter.handleStream(params, task: task, store: taskStore) { @Sendable event in
                logger.info("Stream event received: \(type(of: event))")
            }
            
        } catch {
            logger.error("Error: \(error)")
        }
        
        logger.info("Example completed!")
    }
} 
