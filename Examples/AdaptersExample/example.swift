import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitAdapters

// Example: Using OpenAI Adapter with A2A Server
func openAIAdapterExample() async {
    let logger = Logger(label: "OpenAIAdapterExample")
    logger.info("=== SwiftAgentKit OpenAI Adapter Example ===")
    
    // Note: In a real application, you would get the API key from environment variables
    // let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    let openAIKey = "your-openai-api-key-here" // Replace with actual key
    
    let openAIAdapter = OpenAIAdapter(
        apiKey: openAIKey,
        model: "gpt-4o",
        systemPrompt: "You are a helpful coding assistant. Always provide clear, concise explanations and include code examples when relevant."
    )
    
    let openAIServer = A2AServer(port: 4246, adapter: openAIAdapter)
    
    logger.info("Starting OpenAI A2A server on port 4246...")
    
    Task {
        do {
            try await openAIServer.start()
        } catch {
            logger.error("OpenAI server failed to start: \(error)")
        }
    }
    
    logger.info("OpenAI A2A server started!")
    logger.info("Server running on http://localhost:4246")
    logger.info("Agent card available at http://localhost:4246/.well-known/agent.json")
    
    // Keep the server running
    logger.info("Server will run indefinitely. Press Ctrl+C to stop...")
    try? await Task.sleep(for: .seconds(.infinity))
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
}

// Main execution
@main
struct AdaptersExample {
    static func main() async {
        let logger = Logger(label: "AdaptersExample")
        
        // Check if API keys are provided
        let hasOpenAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil
        
        if hasOpenAIKey {
            logger.info("OpenAI API key found, running examples...")
            await openAIAdapterExample()
        } else {
            logger.warning("OPENAI_API_KEY environment variable not set.")
            logger.info("Set OPENAI_API_KEY to run the full example.")
            logger.info("Example: export OPENAI_API_KEY='your-key-here'")
        }
    }
}
