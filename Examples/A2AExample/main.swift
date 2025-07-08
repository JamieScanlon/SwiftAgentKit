import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitA2A

// Example: A2A (Agent-to-Agent) usage with A2AManager
func a2aManagerExample() async {
    let logger = Logger(label: "A2AExample")
    logger.info("=== SwiftAgentKit A2A Manager Example ===")
    
    // Create a sample A2A config file for demonstration
    let sampleConfig = """
    {
        "a2aServers": {
            "example-agent": {
                "boot": {
                    "command": "/usr/local/bin/example-a2a-agent",
                    "args": ["--port", "4245"],
                    "env": {
                        "API_KEY": "your-api-key",
                        "MODEL": "gpt-4"
                    }
                },
                "run": {
                    "url": "http://localhost:4245",
                    "token": "optional-auth-token",
                    "api_key": "optional-api-key"
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
    let configURL = tempDir.appendingPathComponent("a2a-config.json")
    
    do {
        try sampleConfig.write(to: configURL, atomically: true, encoding: .utf8)
        logger.info("Created sample A2A config at: \(configURL.path)")
    } catch {
        logger.error("Failed to create sample config: \(error)")
        return
    }
    
    // Initialize A2AManager with the config file
    let a2aManager = A2AManager()
    
    do {
        logger.info("Initializing A2AManager...")
        try await a2aManager.initialize(configFileURL: configURL)
        logger.info("A2AManager initialized successfully!")
        
        // Example: Create a tool call for an A2A agent
        let toolCall = ToolCall(
            name: "agent_interaction",
            arguments: [
                "instructions": "Hello! Can you help me with a task? Please provide a brief response."
            ],
            instructions: "Send a greeting and request for help to the A2A agent"
        )
        
        logger.info("Making agent call: \(toolCall.name)")
        
        // Execute the agent call
        if let messages = try await a2aManager.agentCall(toolCall) {
            logger.info("Agent call successful! Received \(messages.count) messages:")
            for (index, message) in messages.enumerated() {
                logger.info("Message \(index + 1): \(message.content)")
            }
        } else {
            logger.warning("Agent call returned no messages")
        }
        
    } catch {
        logger.error("Failed to initialize A2AManager: \(error)")
    }
    
    // Clean up the temporary config file
    try? FileManager.default.removeItem(at: configURL)
}

// Example: Using A2AManager with a real config file
func a2aManagerWithRealConfigExample() async {
    let logger = Logger(label: "A2ARealConfigExample")
    logger.info("=== SwiftAgentKit A2A Manager with Real Config Example ===")
    
    // In a real application, you would load your actual A2A config file
    let configPath = "./a2a-config.json" // Replace with your actual config path
    let configURL = URL(fileURLWithPath: configPath)
    
    // Check if the config file exists
    guard FileManager.default.fileExists(atPath: configPath) else {
        logger.error("A2A config file not found at: \(configPath)")
        logger.info("Please create an a2a-config.json file with your A2A server configuration")
        return
    }
    
    let a2aManager = A2AManager()
    
    do {
        logger.info("Initializing A2AManager with config: \(configPath)")
        try await a2aManager.initialize(configFileURL: configURL)
        logger.info("A2AManager initialized successfully!")
        
        // Example: Create a tool call for a real A2A agent
        let toolCall = ToolCall(
            name: "text_generation",
            arguments: [
                "instructions": "Write a short story about a robot learning to paint"
            ],
            instructions: "Generate creative text based on the provided prompt"
        )
        
        logger.info("Making agent call to: \(toolCall.name)")
        
        // Execute the agent call
        if let messages = try await a2aManager.agentCall(toolCall) {
            logger.info("Agent call successful! Received \(messages.count) messages:")
            for (index, message) in messages.enumerated() {
                logger.info("Message \(index + 1): \(message.content)")
            }
        } else {
            logger.warning("Agent call returned no messages - the agent might not be available")
        }
        
    } catch {
        logger.error("Failed to initialize A2AManager: \(error)")
        logger.info("Make sure your A2A config file is valid and the servers are accessible")
    }
}

// Example: Error handling and state management
func a2aManagerErrorHandlingExample() async {
    let logger = Logger(label: "A2AErrorHandlingExample")
    logger.info("=== SwiftAgentKit A2A Manager Error Handling Example ===")
    
    let a2aManager = A2AManager()
    
    // Example 1: Try to initialize with a non-existent config file
    let nonExistentURL = URL(fileURLWithPath: "/path/to/nonexistent/config.json")
    
    do {
        logger.info("Attempting to initialize with non-existent config...")
        try await a2aManager.initialize(configFileURL: nonExistentURL)
    } catch {
        logger.error("Expected error when config file doesn't exist: \(error)")
    }
    
    // Example 2: Try to make an agent call before initialization
    let toolCall = ToolCall(name: "test_agent", arguments: [:])
    
    do {
        logger.info("Attempting agent call before initialization...")
        let _ = try await a2aManager.agentCall(toolCall)
    } catch {
        logger.error("Expected error when calling agent before initialization: \(error)")
    }
    
    // Example 3: Create an invalid config file
    let invalidConfig = """
    {
        "invalid": "json",
        "missing": "required fields"
    }
    """
    
    let tempDir = FileManager.default.temporaryDirectory
    let invalidConfigURL = tempDir.appendingPathComponent("invalid-a2a-config.json")
    
    do {
        try invalidConfig.write(to: invalidConfigURL, atomically: true, encoding: .utf8)
        logger.info("Created invalid A2A config for testing...")
        
        try await a2aManager.initialize(configFileURL: invalidConfigURL)
    } catch {
        logger.error("Expected error with invalid config: \(error)")
    }
    
    // Clean up
    try? FileManager.default.removeItem(at: invalidConfigURL)
}

// Example: Working with multiple agents
func a2aManagerMultipleAgentsExample() async {
    let logger = Logger(label: "A2AMultipleAgentsExample")
    logger.info("=== SwiftAgentKit A2A Manager Multiple Agents Example ===")
    
    // This example assumes you have a config file with multiple A2A servers
    let configPath = "./a2a-config-multiple.json"
    let configURL = URL(fileURLWithPath: configPath)
    
    guard FileManager.default.fileExists(atPath: configPath) else {
        logger.info("Skipping multiple agents example - config file not found")
        return
    }
    
    let a2aManager = A2AManager()
    
    do {
        try await a2aManager.initialize(configFileURL: configURL)
        logger.info("A2AManager initialized with multiple agents!")
        
        // Example agent calls for different types of agents
        let agentCalls = [
            ToolCall(
                name: "text_generation",
                arguments: ["instructions": "Hello, how are you?"],
                instructions: "Generate a friendly response"
            ),
            ToolCall(
                name: "image_analysis",
                arguments: ["instructions": "Analyze this image: https://example.com/image.jpg"],
                instructions: "Analyze the content of this image"
            ),
            ToolCall(
                name: "data_processing",
                arguments: ["instructions": "Process this data: sample data in JSON format"],
                instructions: "Process the provided data"
            )
        ]
        
        for agentCall in agentCalls {
            logger.info("Trying agent: \(agentCall.name)")
            
            do {
                if let messages = try await a2aManager.agentCall(agentCall) {
                    logger.info("✓ \(agentCall.name) succeeded with \(messages.count) messages")
                } else {
                    logger.info("⚠ \(agentCall.name) returned no messages (agent may not be available)")
                }
            } catch {
                logger.error("✗ \(agentCall.name) failed: \(error)")
            }
        }
        
    } catch {
        logger.error("Failed to initialize A2AManager: \(error)")
    }
}

// Example: Streaming agent responses
func a2aManagerStreamingExample() async {
    let logger = Logger(label: "A2AStreamingExample")
    logger.info("=== SwiftAgentKit A2A Manager Streaming Example ===")
    
    // This example shows how to work with streaming responses from A2A agents
    let configPath = "./a2a-config-streaming.json"
    let configURL = URL(fileURLWithPath: configPath)
    
    guard FileManager.default.fileExists(atPath: configPath) else {
        logger.info("Skipping streaming example - config file not found")
        return
    }
    
    let a2aManager = A2AManager()
    
    do {
        try await a2aManager.initialize(configFileURL: configURL)
        logger.info("A2AManager initialized for streaming!")
        
        // Example: Create a tool call that might result in streaming responses
        let toolCall = ToolCall(
            name: "long_text_generation",
            arguments: [
                "instructions": "Write a detailed story about space exploration with multiple chapters"
            ],
            instructions: "Generate a long-form story that will be streamed back"
        )
        
        logger.info("Making streaming agent call: \(toolCall.name)")
        
        // Execute the agent call and handle potential streaming
        if let messages = try await a2aManager.agentCall(toolCall) {
            logger.info("Streaming agent call successful! Received \(messages.count) messages:")
            
            // Process each message as it comes in
            for (index, message) in messages.enumerated() {
                logger.info("Streamed message \(index + 1): \(message.content)")
                
                // You could process each message incrementally here
                // For example, update UI, save to database, etc.
            }
        } else {
            logger.warning("Streaming agent call returned no messages")
        }
        
    } catch {
        logger.error("Failed to initialize A2AManager for streaming: \(error)")
    }
}

// Run examples
Task {
    await a2aManagerExample()
    await a2aManagerWithRealConfigExample()
    await a2aManagerErrorHandlingExample()
    await a2aManagerMultipleAgentsExample()
    await a2aManagerStreamingExample()
} 