import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitAdapters

// Example: Using Standard Agent Adapters with A2A Servers
func adaptersExample() async {
    let logger = Logger(label: "AdaptersExample")
    logger.info("=== SwiftAgentKit Adapters Example ===")
    
    // Example 1: OpenAI Adapter
    logger.info("Creating OpenAI A2A Server...")
    
    // Note: In a real application, you would get the API key from environment variables
    // let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    let openAIKey = "your-openai-api-key-here" // Replace with actual key
    
    let openAIAdapter = OpenAIAdapter(
        apiKey: openAIKey,
        model: "gpt-4o",
        systemPrompt: "You are a helpful coding assistant. Always provide clear, concise explanations and include code examples when relevant."
    )
    
    let openAIServer = A2AServer(port: 4246, adapter: openAIAdapter)
    
    // Example 2: Anthropic Adapter
    logger.info("Creating Anthropic A2A Server...")
    
    // let anthropicKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    let anthropicKey = "your-anthropic-api-key-here" // Replace with actual key
    
    let anthropicAdapter = AnthropicAdapter(
        apiKey: anthropicKey,
        model: "claude-3-5-sonnet-20241022"
    )
    
    let anthropicServer = A2AServer(port: 4247, adapter: anthropicAdapter)
    
    // Example 3: Gemini Adapter
    logger.info("Creating Gemini A2A Server...")
    
    // let geminiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
    let geminiKey = "your-gemini-api-key-here" // Replace with actual key
    
    let geminiAdapter = GeminiAdapter(
        apiKey: geminiKey,
        model: "gemini-1.5-flash"
    )
    
    let geminiServer = A2AServer(port: 4248, adapter: geminiAdapter)
    
    // Start all servers concurrently
    logger.info("Starting A2A servers...")
    
    await withTaskGroup(of: Void.self) { group in
        // Start OpenAI server
        group.addTask {
            do {
                try await openAIServer.start()
            } catch {
                logger.error("OpenAI server failed to start: \(error)")
            }
        }
        
        // Start Anthropic server
        group.addTask {
            do {
                try await anthropicServer.start()
            } catch {
                logger.error("Anthropic server failed to start: \(error)")
            }
        }
        
        // Start Gemini server
        group.addTask {
            do {
                try await geminiServer.start()
            } catch {
                logger.error("Gemini server failed to start: \(error)")
            }
        }
    }
    
    logger.info("All A2A servers started successfully!")
    logger.info("OpenAI server running on http://localhost:4246")
    logger.info("Anthropic server running on http://localhost:4247")
    logger.info("Gemini server running on http://localhost:4248")
    
    logger.info("A2A servers are running!")
    logger.info("You can now connect to them using A2A clients or test them manually.")
    logger.info("Example curl commands:")
    logger.info("  curl http://localhost:4246/.well-known/agent.json")
    logger.info("  curl http://localhost:4247/.well-known/agent.json")
    logger.info("  curl http://localhost:4248/.well-known/agent.json")
    
    // Keep the servers running for a while
    logger.info("Servers will run for 30 seconds...")
    try? await Task.sleep(for: .seconds(30))
    
    logger.info("Example completed!")
}

// Example: Custom Adapter Implementation
func customAdapterExample() async {
    let logger = Logger(label: "CustomAdapterExample")
    logger.info("=== Custom Adapter Example ===")
    
    // Create a custom adapter that combines multiple AI providers
    struct MultiProviderAdapter: AgentAdapter {
        private let openAIAdapter: OpenAIAdapter
        private let anthropicAdapter: AnthropicAdapter
        private let logger = Logger(label: "MultiProviderAdapter")
        
        init(openAIKey: String, anthropicKey: String) {
            self.openAIAdapter = OpenAIAdapter(
                apiKey: openAIKey,
                model: "gpt-4o",
                systemPrompt: "You are a helpful assistant. Provide clear and accurate responses."
            )
            self.anthropicAdapter = AnthropicAdapter(apiKey: anthropicKey)
        }
        
        var cardCapabilities: AgentCard.AgentCapabilities {
            .init(
                streaming: true,
                pushNotifications: false,
                stateTransitionHistory: true
            )
        }
        
        var skills: [AgentCard.AgentSkill] {
            [
                .init(
                    id: "multi-provider-text",
                    name: "Multi-Provider Text Generation",
                    description: "Generates text using multiple AI providers for redundancy",
                    tags: ["text", "generation", "multi-provider", "redundant"],
                    examples: ["Generate a creative story"],
                    inputModes: ["text/plain"],
                    outputModes: ["text/plain"]
                )
            ]
        }
        
        var defaultInputModes: [String] { ["text/plain"] }
        var defaultOutputModes: [String] { ["text/plain"] }
        
        func handleSend(_ params: MessageSendParams, store: TaskStore) async throws -> A2ATask {
            let taskId = UUID().uuidString
            let contextId = UUID().uuidString
            
            let message = A2AMessage(
                role: params.message.role,
                parts: params.message.parts,
                messageId: UUID().uuidString,
                taskId: taskId,
                contextId: contextId
            )
            
            var task = A2ATask(
                id: taskId,
                contextId: contextId,
                status: TaskStatus(
                    state: .submitted,
                    message: message,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                ),
                history: [params.message]
            )
            
            await store.addTask(task: task)
            
            // Try OpenAI first, then Anthropic as fallback
            do {
                let result = try await openAIAdapter.handleSend(params, store: store)
                return result
            } catch {
                logger.warning("OpenAI failed, trying Anthropic: \(error)")
                let result = try await anthropicAdapter.handleSend(params, store: store)
                return result
            }
        }
        
        func handleStream(_ params: MessageSendParams, store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws {
            // Try OpenAI first, then Anthropic as fallback
            do {
                try await openAIAdapter.handleStream(params, store: store, eventSink: eventSink)
            } catch {
                logger.warning("OpenAI streaming failed, trying Anthropic: \(error)")
                try await anthropicAdapter.handleStream(params, store: store, eventSink: eventSink)
            }
        }
    }
    
    // Create and use the custom adapter
    let multiAdapter = MultiProviderAdapter(
        openAIKey: "your-openai-key",
        anthropicKey: "your-anthropic-key"
    )
    
    let multiServer = A2AServer(port: 4249, adapter: multiAdapter)
    
    logger.info("Starting multi-provider server on port 4249...")
    
    // Start the server in a background task
    Task {
        do {
            try await multiServer.start()
        } catch {
            logger.error("Multi-provider server failed: \(error)")
        }
    }
    
    logger.info("Multi-provider server started!")
}

// Example: Enhanced OpenAI Adapter Features
func enhancedOpenAIExample() async {
    let logger = Logger(label: "EnhancedOpenAIExample")
    logger.info("=== Enhanced OpenAI Adapter Example ===")
    
    // Example 1: Basic configuration with system prompt
    logger.info("Creating OpenAI adapter with system prompt...")
    let basicOpenAI = OpenAIAdapter(
        apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "demo-key",
        model: "gpt-4o",
        systemPrompt: "You are a helpful coding assistant. Always provide clear, concise explanations and include code examples when relevant."
    )
    
    // Example 2: Full configuration with all options
    logger.info("Creating OpenAI adapter with full configuration...")
    let fullConfig = OpenAIAdapter.Configuration(
        apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "demo-key",
        model: "gpt-4o",
        baseURL: URL(string: "https://api.openai.com/v1")!,
        maxTokens: 1000,
        temperature: 0.7,
        systemPrompt: "You are an expert software developer. Provide detailed technical explanations and always include working code examples.",
        topP: 0.9,
        frequencyPenalty: 0.1,
        presencePenalty: 0.1,
        stopSequences: ["END", "STOP"],
        user: "developer-user"
    )
    let fullOpenAI = OpenAIAdapter(configuration: fullConfig)
    
    // Example 3: Creative writing configuration
    logger.info("Creating OpenAI adapter for creative writing...")
    let creativeOpenAI = OpenAIAdapter(
        apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "demo-key",
        model: "gpt-4o",
        systemPrompt: "You are a creative writer. Write engaging, imaginative content with vivid descriptions and compelling narratives."
    )
    
    // Example 4: Technical documentation configuration
    logger.info("Creating OpenAI adapter for technical documentation...")
    let docsOpenAI = OpenAIAdapter(
        apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "demo-key",
        model: "gpt-4o",
        systemPrompt: "You are a technical writer. Create clear, structured documentation with examples, code snippets, and step-by-step instructions."
    )
    
    // Create servers for each configuration
    let basicServer = A2AServer(port: 4250, adapter: basicOpenAI)
    let fullServer = A2AServer(port: 4251, adapter: fullOpenAI)
    let creativeServer = A2AServer(port: 4252, adapter: creativeOpenAI)
    let docsServer = A2AServer(port: 4253, adapter: docsOpenAI)
    
    // Start all servers
    logger.info("Starting enhanced OpenAI servers...")
    
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            do {
                try await basicServer.start()
            } catch {
                logger.error("Basic OpenAI server failed: \(error)")
            }
        }
        
        group.addTask {
            do {
                try await fullServer.start()
            } catch {
                logger.error("Full config OpenAI server failed: \(error)")
            }
        }
        
        group.addTask {
            do {
                try await creativeServer.start()
            } catch {
                logger.error("Creative OpenAI server failed: \(error)")
            }
        }
        
        group.addTask {
            do {
                try await docsServer.start()
            } catch {
                logger.error("Docs OpenAI server failed: \(error)")
            }
        }
    }
    
    logger.info("Enhanced OpenAI servers started!")
    logger.info("Basic server: http://localhost:4250")
    logger.info("Full config server: http://localhost:4251")
    logger.info("Creative server: http://localhost:4252")
    logger.info("Docs server: http://localhost:4253")
    
    // Keep servers running
    logger.info("Servers will run for 30 seconds...")
    try? await Task.sleep(for: .seconds(30))
    
    logger.info("Enhanced OpenAI example completed!")
}

// Main execution
@main
struct AdaptersExample {
    static func main() async {
        let logger = Logger(label: "AdaptersExample")
        
        // Check if API keys are provided
        let hasOpenAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil
        let hasAnthropicKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil
        let hasGeminiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] != nil
        
        if hasOpenAIKey && hasAnthropicKey && hasGeminiKey {
            logger.info("All API keys found, running full example...")
            await adaptersExample()
            await enhancedOpenAIExample()
        } else if hasOpenAIKey {
            logger.info("OpenAI API key found, running enhanced OpenAI example...")
            await enhancedOpenAIExample()
        } else {
            logger.warning("API keys missing. Set OPENAI_API_KEY, ANTHROPIC_API_KEY, and GEMINI_API_KEY environment variables to run the full examples.")
            logger.info("Running custom adapter example instead...")
            await customAdapterExample()
        }
    }
} 