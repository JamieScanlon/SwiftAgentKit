import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitMCP

// Example: MCP (Model Context Protocol) usage with MCPManager
func mcpManagerExample() async {
    let logger = Logger(label: "MCPExample")
    logger.info("=== SwiftAgentKit MCP Manager Example ===")
    
    // Create a sample MCP config file for demonstration
    let sampleConfig = """
    {
        "mcpServers": {
            "example-server": {
                "command": "/usr/local/bin/example-mcp-server",
                "args": ["--port", "4242"],
                "env": {
                    "API_KEY": "your-api-key",
                    "MODEL": "gpt-4"
                }
            }
        },
        "globalEnv": {
            "LOG_LEVEL": "info",
            "ENVIRONMENT": "development"
        }
    }
    """
    
    // Write the sample config to a temporary file
    let tempDir = FileManager.default.temporaryDirectory
    let configURL = tempDir.appendingPathComponent("mcp-config.json")
    
    do {
        try sampleConfig.write(to: configURL, atomically: true, encoding: .utf8)
        logger.info("Created sample MCP config at: \(configURL.path)")
    } catch {
        logger.error("Failed to create sample config: \(error)")
        return
    }
    
    // Initialize MCPManager with the config file
    let mcpManager = MCPManager()
    
    do {
        logger.info("Initializing MCPManager...")
        try await mcpManager.initialize(configFileURL: configURL)
        logger.info("MCPManager initialized successfully!")
        
        // Example: Create a tool call
        let toolCall = ToolCall(
            name: "example_tool",
            arguments: [
                "input": "Hello, world!",
                "options": ["option1", "option2"]
            ],
            instructions: "Process this input with the specified options"
        )
        
        logger.info("Making tool call: \(toolCall.name)")
        
        // Execute the tool call
        if let messages = try await mcpManager.toolCall(toolCall) {
            logger.info("Tool call successful! Received \(messages.count) messages:")
            for (index, message) in messages.enumerated() {
                logger.info("Message \(index + 1): \(message.content)")
            }
        } else {
            logger.warning("Tool call returned no messages")
        }
        
    } catch {
        logger.error("Failed to initialize MCPManager: \(error)")
    }
    
    // Clean up the temporary config file
    try? FileManager.default.removeItem(at: configURL)
}

// Example: Using MCPManager with a real config file
func mcpManagerWithRealConfigExample() async {
    let logger = Logger(label: "MCPRealConfigExample")
    logger.info("=== SwiftAgentKit MCP Manager with Real Config Example ===")
    
    // In a real application, you would load your actual MCP config file
    let configPath = "./mcp-config.json" // Replace with your actual config path
    let configURL = URL(fileURLWithPath: configPath)
    
    // Check if the config file exists
    guard FileManager.default.fileExists(atPath: configPath) else {
        logger.error("MCP config file not found at: \(configPath)")
        logger.info("Please create an mcp-config.json file with your MCP server configuration")
        return
    }
    
    let mcpManager = MCPManager()
    
    do {
        logger.info("Initializing MCPManager with config: \(configPath)")
        try await mcpManager.initialize(configFileURL: configURL)
        logger.info("MCPManager initialized successfully!")
        
        // Example: Create a tool call for a real MCP server
        let toolCall = ToolCall(
            name: "text_generation",
            arguments: [
                "prompt": "Write a short story about a robot learning to paint",
                "max_tokens": 100,
                "temperature": 0.7
            ],
            instructions: "Generate creative text based on the provided prompt"
        )
        
        logger.info("Making tool call to: \(toolCall.name)")
        
        // Execute the tool call
        if let messages = try await mcpManager.toolCall(toolCall) {
            logger.info("Tool call successful! Received \(messages.count) messages:")
            for (index, message) in messages.enumerated() {
                logger.info("Message \(index + 1): \(message.content)")
            }
        } else {
            logger.warning("Tool call returned no messages - the tool might not be available")
        }
        
    } catch {
        logger.error("Failed to initialize MCPManager: \(error)")
        logger.info("Make sure your MCP config file is valid and the servers are accessible")
    }
}

// Example: Error handling and state management
func mcpManagerErrorHandlingExample() async {
    let logger = Logger(label: "MCPErrorHandlingExample")
    logger.info("=== SwiftAgentKit MCP Manager Error Handling Example ===")
    
    let mcpManager = MCPManager()
    
    // Example 1: Try to initialize with a non-existent config file
    let nonExistentURL = URL(fileURLWithPath: "/path/to/nonexistent/config.json")
    
    do {
        logger.info("Attempting to initialize with non-existent config...")
        try await mcpManager.initialize(configFileURL: nonExistentURL)
    } catch {
        logger.error("Expected error when config file doesn't exist: \(error)")
    }
    
    // Example 2: Try to make a tool call before initialization
    let toolCall = ToolCall(name: "test_tool", arguments: [:])
    
    do {
        logger.info("Attempting tool call before initialization...")
        let _ = try await mcpManager.toolCall(toolCall)
    } catch {
        logger.error("Expected error when calling tool before initialization: \(error)")
    }
    
    // Example 3: Create an invalid config file
    let invalidConfig = """
    {
        "invalid": "json",
        "missing": "required fields"
    }
    """
    
    let tempDir = FileManager.default.temporaryDirectory
    let invalidConfigURL = tempDir.appendingPathComponent("invalid-mcp-config.json")
    
    do {
        try invalidConfig.write(to: invalidConfigURL, atomically: true, encoding: .utf8)
        logger.info("Created invalid MCP config for testing...")
        
        try await mcpManager.initialize(configFileURL: invalidConfigURL)
    } catch {
        logger.error("Expected error with invalid config: \(error)")
    }
    
    // Clean up
    try? FileManager.default.removeItem(at: invalidConfigURL)
}

// Example: Working with multiple tools
func mcpManagerMultipleToolsExample() async {
    let logger = Logger(label: "MCPMultipleToolsExample")
    logger.info("=== SwiftAgentKit MCP Manager Multiple Tools Example ===")
    
    // This example assumes you have a config file with multiple MCP servers
    let configPath = "./mcp-config-multiple.json"
    let configURL = URL(fileURLWithPath: configPath)
    
    guard FileManager.default.fileExists(atPath: configPath) else {
        logger.info("Skipping multiple tools example - config file not found")
        return
    }
    
    let mcpManager = MCPManager()
    
    do {
        try await mcpManager.initialize(configFileURL: configURL)
        logger.info("MCPManager initialized with multiple servers!")
        
        // Example tool calls for different types of tools
        let toolCalls = [
            ToolCall(
                name: "text_generation",
                arguments: ["prompt": "Hello, how are you?"],
                instructions: "Generate a friendly response"
            ),
            ToolCall(
                name: "image_analysis",
                arguments: ["image_url": "https://example.com/image.jpg"],
                instructions: "Analyze the content of this image"
            ),
            ToolCall(
                name: "data_processing",
                arguments: ["data": "sample data", "format": "json"],
                instructions: "Process the provided data"
            )
        ]
        
        for toolCall in toolCalls {
            logger.info("Trying tool: \(toolCall.name)")
            
            do {
                if let messages = try await mcpManager.toolCall(toolCall) {
                    logger.info("✓ \(toolCall.name) succeeded with \(messages.count) messages")
                } else {
                    logger.info("⚠ \(toolCall.name) returned no messages (tool may not be available)")
                }
            } catch {
                logger.error("✗ \(toolCall.name) failed: \(error)")
            }
        }
        
    } catch {
        logger.error("Failed to initialize MCPManager: \(error)")
    }
}

// Run examples
Task {
    await mcpManagerExample()
    await mcpManagerWithRealConfigExample()
    await mcpManagerErrorHandlingExample()
    await mcpManagerMultipleToolsExample()
} 