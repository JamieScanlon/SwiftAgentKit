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
    
    // Example 2: With custom tool provider
    logger.info("Creating adapter with custom tool provider...")
    
    let customProvider = CustomToolProvider()
    let toolAwareAdapter = AdapterBuilder()
        .withLLM(AnthropicAdapter(apiKey: "your-anthropic-key"))
        .withToolProvider(customProvider)
        .build()
    
    let toolAwareServer = A2AServer(port: 4246, adapter: toolAwareAdapter)
    
    // Example 3: Manual setup with tool manager
    logger.info("Creating adapter with manual tool manager setup...")
    
    let manualToolManager = ToolManager(providers: [customProvider])
    let manualAdapter = ToolAwareAdapter(
        baseAdapter: GeminiAdapter(apiKey: "your-gemini-key"),
        toolManager: manualToolManager
    )
    
    let manualServer = A2AServer(port: 4247, adapter: manualAdapter)
    
    logger.info("Tool-aware adapters created successfully!")
    logger.info("Basic adapter: \(basicServer)")
    logger.info("Tool-aware adapter: \(toolAwareServer)")
    logger.info("Manual adapter: \(manualServer)")
}

// Example: Testing tool execution
func testToolExecution() async {
    let logger = Logger(label: "TestToolExecution")
    logger.info("=== Testing Tool Execution ===")
    
    // Create a custom tool provider
    let customProvider = CustomToolProvider()
    let toolManager = ToolManager(providers: [customProvider])
    
    // Test tool execution directly
    let toolCall = ToolCall(
        name: "custom_function",
        arguments: ["input": "Hello from tool!"],
        instructions: "Execute the custom function"
    )
    
    do {
        let result = try await toolManager.executeTool(toolCall)
        logger.info("Tool execution result: \(result.success)")
        logger.info("Tool content: \(result.content)")
        if let error = result.error {
            logger.error("Tool error: \(error)")
        }
    } catch {
        logger.error("Tool execution failed: \(error)")
    }
}

// Example: Testing tool parsing
func testToolParsing() async {
    let logger = Logger(label: "TestToolParsing")
    logger.info("=== Testing Tool Call Parsing ===")
    
    // Test the ToolCall.processModelResponse method
    let responseWithTool = "Here's the weather: <|python_tag|>weather_tool(location=\"New York\", units=\"celsius\")<|eom_id|>"
    let (message, toolCall) = ToolCall.processModelResponse(content: responseWithTool)
    
    logger.info("Processed message: \(message)")
    logger.info("Extracted tool call: \(toolCall ?? "none")")
    
    // Test without tool call
    let responseWithoutTool = "Here's a simple response without any tools."
    let (message2, toolCall2) = ToolCall.processModelResponse(content: responseWithoutTool)
    
    logger.info("Processed message (no tools): \(message2)")
    logger.info("Extracted tool call (no tools): \(toolCall2 ?? "none")")
}

// Custom tool provider for demonstration
struct CustomToolProvider: ToolProvider {
    public var name: String { "Custom Tools" }
    
    public func availableTools() async -> [ToolDefinition] {
        return [
            ToolDefinition(
                name: "custom_function",
                description: "A custom function that does something",
                type: .function
            ),
            ToolDefinition(
                name: "weather_tool",
                description: "Get weather information for a location",
                type: .function
            )
        ]
    }
    
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        switch toolCall.name {
        case "custom_function":
            let input = toolCall.arguments["input"] as? String ?? "no input"
            return ToolResult(
                success: true,
                content: "Custom function executed successfully with input: \(input)",
                metadata: .object(["source": .string("custom_function")])
            )
            
        case "weather_tool":
            let location = toolCall.arguments["location"] as? String ?? "unknown"
            let units = toolCall.arguments["units"] as? String ?? "celsius"
            return ToolResult(
                success: true,
                content: "Weather in \(location): 22°\(units), sunny with light breeze",
                metadata: .object([
                    "source": .string("weather_tool"),
                    "location": .string(location),
                    "units": .string(units)
                ])
            )
            
        default:
            return ToolResult(
                success: false,
                content: "",
                error: "Unknown tool: \(toolCall.name)"
            )
        }
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
    logger.info("Server: \(server)")
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
await testToolExecution()
await testToolParsing()
await customToolProviderExample()

print("ToolAwareExample completed!") 