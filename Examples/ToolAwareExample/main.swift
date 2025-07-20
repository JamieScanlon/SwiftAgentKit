import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitAdapters

// Example: Using Tool-Aware Adapters with A2A and MCP capabilities
func toolAwareExample() async {
    let logger = Logger(label: "ToolAwareExample")
    logger.info("=== SwiftAgentKit Tool-Aware Adapter Example ===")
    
    // Example 1: Basic setup (no tools)
    logger.info("Creating basic adapter without tools...")
    let basicAdapter = AdapterBuilder()
        .withLLM(OpenAIAdapter(apiKey: "your-openai-key"))
        .build()
    
    let basicServer = A2AServer(port: 4245, adapter: basicAdapter)
    
    // Example 2: With A2A agents only
    logger.info("Creating adapter with A2A agents...")
    
    // TODO: In a real application, you would initialize A2A clients
    // let a2aClient1 = A2AClient(server: a2aServer1)
    // try await a2aClient1.initializeA2AClient()
    
    // For demonstration, we'll show the builder pattern
    let a2aAdapter = AdapterBuilder()
        .withLLM(AnthropicAdapter(apiKey: "your-anthropic-key"))
        // .withA2AClient(a2aClient1)  // Uncomment when A2A clients are available
        .build()
    
    let a2aServer = A2AServer(port: 4246, adapter: a2aAdapter)
    
    // Example 3: With MCP tools only
    logger.info("Creating adapter with MCP tools...")
    
    // TODO: In a real application, you would initialize MCP clients
    // let mcpClient1 = MCPClient(bootCall: mcpBootCall1, version: "1.0")
    // try await mcpClient1.initializeMCPClient(config: mcpConfig)
    
    let mcpAdapter = AdapterBuilder()
        .withLLM(GeminiAdapter(apiKey: "your-gemini-key"))
        // .withMCPClient(mcpClient1)  // Uncomment when MCP clients are available
        .build()
    
    let mcpServer = A2AServer(port: 4247, adapter: mcpAdapter)
    
    // Example 4: With both A2A and MCP
    logger.info("Creating adapter with both A2A and MCP capabilities...")
    
    let fullAdapter = AdapterBuilder()
        .withLLM(OpenAIAdapter(apiKey: "your-openai-key"))
        // .withA2AClient(a2aClient1)
        // .withMCPClient(mcpClient1)
        .build()
    
    let fullServer = A2AServer(port: 4248, adapter: fullAdapter)
    
    // Example 5: Manual setup without builder
    logger.info("Creating adapter manually...")
    
    // Create tool providers manually
    // let a2aProvider = A2AToolProvider(clients: [a2aClient1])
    // let mcpProvider = MCPToolProvider(clients: [mcpClient1])
    // let toolManager = ToolManager(providers: [a2aProvider, mcpProvider])
    
    // Create enhanced adapter
    // let manualAdapter = ToolAwareAdapter(
    //     baseAdapter: OpenAIAdapter(apiKey: "your-openai-key"),
    //     toolManager: toolManager
    // )
    
    // let manualServer = A2AServer(port: 4249, adapter: manualAdapter)
    
    logger.info("Tool-aware adapters created successfully!")
    logger.info("Note: Tool integration is not yet implemented - adapters will work as basic adapters for now")
    
    // TODO: Start servers when tool integration is implemented
    // try await basicServer.start()
    // try await a2aServer.start()
    // try await mcpServer.start()
    // try await fullServer.start()
}

// Example: Custom tool provider
struct CustomToolProvider: ToolProvider {
    public var name: String { "Custom Tools" }
    
    public func availableTools() async -> [ToolDefinition] {
        return [
            ToolDefinition(
                name: "custom_function",
                description: "A custom function that does something",
                type: .function
            )
        ]
    }
    
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        if toolCall.name == "custom_function" {
            return ToolResult(
                success: true,
                content: "Custom function executed successfully",
                metadata: .object(["source": .string("custom_function")])
            )
        }
        
        return ToolResult(
            success: false,
            content: "",
            error: "Unknown tool: \(toolCall.name)"
        )
    }
}

// Example: Using custom tool provider
func customToolProviderExample() async {
    let logger = Logger(label: "CustomToolProviderExample")
    logger.info("=== Custom Tool Provider Example ===")
    
    let customAdapter = AdapterBuilder()
        .withLLM(OpenAIAdapter(apiKey: "your-openai-key"))
        .withToolProvider(CustomToolProvider())
        .build()
    
    let server = A2AServer(port: 4250, adapter: customAdapter)
    
    logger.info("Custom tool provider adapter created!")
}

// Run examples
print("Starting ToolAwareExample...")

// Set up logging
LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardOutput(label: label)
    handler.logLevel = .info
    return handler
}

// Run examples synchronously
await toolAwareExample()
await customToolProviderExample()

print("ToolAwareExample completed!") 