import Foundation
import SwiftAgentKit
import SwiftAgentKitAdapters
import SwiftAgentKitA2A
import Logging
import EasyJSON

private func configureLogging() {
    SwiftAgentKitLogging.bootstrap(
        logger: Logger(label: "com.example.swiftagentkit.openaiadapter"),
        level: .info,
        metadata: SwiftAgentKitLogging.metadata(("example", .string("OpenAIAdapter")))
    )
}

@main
struct OpenAIAdapterExample {
    static func main() async throws {
        configureLogging()
        
        let logger = SwiftAgentKitLogging.logger(for: .examples("OpenAIAdapterExample"))
        logger.info("Starting OpenAI Adapter Example")
        logger.info("This example demonstrates the enhanced OpenAI adapter that can handle:")
        logger.info("- Text content in response messages")
        logger.info("- Tool calls as separate message parts")
        logger.info("- Mixed content types in a single response")
        logger.info("- Image generation using DALL-E")
        
        // Create OpenAI adapter with MacPaw OpenAI package and custom configuration
        // This demonstrates the full configuration options available:
        // - apiKey: Your OpenAI API key
        // - model: The model to use (gpt-4o, gpt-4, etc.)
        // - systemPrompt: Optional DynamicPrompt to set behavior (supports token replacement)
        // - baseURL: Custom API endpoint (useful for proxies or custom deployments)
        // - organizationIdentifier: OpenAI organization ID for billing
        // - timeoutInterval: Request timeout in seconds
        // - customHeaders: Additional HTTP headers
        // - parsingOptions: Response parsing behavior (.relaxed for better compatibility)
        
        // Create a dynamic prompt with token support
        var systemPrompt = DynamicPrompt(template: "You are a {{tone}} AI assistant.")
        systemPrompt["tone"] = "helpful"
        
        let openAIAdapter = OpenAIAdapter(
            apiKey: "your-api-key-here", // Replace with your actual API key
            model: "gpt-4o",
            systemPrompt: systemPrompt,
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
            try await openAIAdapter.handleTaskSend(params, taskId: taskID, contextId: task.contextId, store: taskStore)
            
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
            try await openAIAdapter.handleStream(params, taskId: taskID, contextId: task.contextId, store: taskStore) { @Sendable event in
                logger.info("Stream event received: \(type(of: event))")
            }
            
            // Test image generation
            logger.info("\nTesting image generation...")
            let imageMessage = A2AMessage(
                role: "user",
                parts: [.text(text: "Generate a beautiful sunset over mountains")],
                messageId: UUID().uuidString,
                taskId: UUID().uuidString,
                contextId: UUID().uuidString
            )
            
            let imageTaskID = UUID().uuidString
            let imageConfig = MessageSendConfiguration(
                acceptedOutputModes: ["image/png", "text/plain"]
            )
            let imageParams = MessageSendParams(
                message: imageMessage,
                configuration: imageConfig,
                metadata: try? JSON(["n": 1, "size": "1024x1024"])
            )
            
            var imageTask = A2ATask(
                id: imageTaskID,
                contextId: UUID().uuidString,
                status: TaskStatus(
                    state: .submitted,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                ),
                history: [imageParams.message]
            )
            await taskStore.addTask(task: imageTask)
            
            try await openAIAdapter.handleTaskSend(imageParams, taskId: imageTaskID, contextId: imageTask.contextId, store: taskStore)
            
            imageTask = await taskStore.getTask(id: imageTaskID)!
            logger.info("Image generation completed. Status: \(imageTask.status.state)")
            
            if let artifacts = imageTask.artifacts {
                logger.info("Generated \(artifacts.count) image artifact(s):")
                for (index, artifact) in artifacts.enumerated() {
                    logger.info("  Artifact \(index + 1):")
                    logger.info("    - Name: \(artifact.name ?? "unnamed")")
                    logger.info("    - Description: \(artifact.description ?? "none")")
                    for part in artifact.parts {
                        if case .file(_, let url) = part {
                            logger.info("    - Image URL: \(url?.path ?? "nil")")
                        }
                    }
                    if let metadata = artifact.metadata?.literalValue as? [String: Any] {
                        if let mimeType = metadata["mimeType"] as? String {
                            logger.info("    - MIME Type: \(mimeType)")
                        }
                        if let createdAt = metadata["createdAt"] as? String {
                            logger.info("    - Created At: \(createdAt)")
                        }
                    }
                }
            }
            
        } catch {
            logger.error("Error: \(error)")
        }
        
        logger.info("Example completed!")
    }
} 
