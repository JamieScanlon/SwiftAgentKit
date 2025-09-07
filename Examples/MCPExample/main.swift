import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitMCP

// Example: New MCP Architecture with MCPServerManager and MCPClient
func newMCPArchitectureExample() async {
    let logger = Logger(label: "NewMCPExample")
    logger.info("=== SwiftAgentKit New MCP Architecture Example ===")
    
    // Step 1: Create MCP configuration programmatically
    let serverBootCall = MCPConfig.ServerBootCall(
        name: "example-server",
        command: "echo",
        arguments: ["hello from MCP server"],
        environment: .object([
            "API_KEY": .string("your-api-key"),
            "MODEL": .string("gpt-4")
        ])
    )
    
    var config = MCPConfig()
    config.serverBootCalls = [serverBootCall]
    config.globalEnvironment = .object([
        "LOG_LEVEL": .string("info"),
        "ENVIRONMENT": .string("development")
    ])
    
    logger.info("Created MCP configuration with server: \(serverBootCall.name)")
    
    // Step 2: Use MCPServerManager to boot servers
    let serverManager = MCPServerManager()
    
    // Alternative: Use MCPManager with custom timeout for all clients
    // let mcpManager = MCPManager(connectionTimeout: 15.0)
    // try await mcpManager.initialize(configFileURL: configURL)
    
    // Alternative: Use SwiftAgentKitOrchestrator with custom MCP timeout
    // let config = OrchestratorConfig(mcpEnabled: true, mcpConnectionTimeout: 15.0)
    // let orchestrator = SwiftAgentKitOrchestrator(llm: yourLLM, config: config)
    
    do {
        logger.info("Booting MCP servers using MCPServerManager...")
        let serverPipes = try await serverManager.bootServers(config: config)
        logger.info("Successfully booted \(serverPipes.count) MCP servers")
        
        // Step 3: Create MCPClient instances and connect them
        var clients: [MCPClient] = []
        
        for (serverName, pipes) in serverPipes {
            logger.info("Creating MCPClient for server: \(serverName)")
            
            // Create client with name, version, and custom timeout
            // Use a shorter timeout for problematic servers (e.g., Docker-based GitHub MCP server)
            let client = MCPClient(name: serverName, version: "1.0.0", connectionTimeout: 15.0)
            
            do {
                // Connect using the new transport-based approach with improved error handling
                // This includes SIGPIPE signal handling to prevent process termination (exit code 141)
                try await client.connect(inPipe: pipes.inPipe, outPipe: pipes.outPipe)
                logger.info("✓ Connected to server: \(serverName)")
            } catch let mcpError as MCPClient.MCPClientError {
                switch mcpError {
                case .connectionTimeout(let timeout):
                    logger.warning("⏰ Server '\(serverName)' connection timed out after \(timeout) seconds")
                case .pipeError(let message):
                    logger.warning("🔌 Server '\(serverName)' pipe error: \(message)")
                case .processTerminated(let message):
                    logger.warning("💀 Server '\(serverName)' process terminated: \(message)")
                case .connectionFailed(let message):
                    logger.warning("❌ Server '\(serverName)' connection failed: \(message)")
                case .notConnected:
                    logger.warning("🔌 Server '\(serverName)' not connected")
                }
                continue
            } catch {
                logger.error("❌ Failed to connect to server '\(serverName)': \(error)")
                continue
            }
            
            // Check available tools (tools will be populated when first tool call is made)
            let _ = await client.tools.count
            logger.info("✓ Connected to server: \(serverName) (tools will be available on first call)")
            
            clients.append(client)
        }
        
        logger.info("✓ Successfully created and connected \(clients.count) MCP clients")
        logger.info("Note: Echo servers don't implement MCP protocol, so tool calls would fail")
        logger.info("In a real scenario, you would connect to actual MCP-compliant servers")
        
    } catch {
        logger.error("Failed to boot MCP servers: \(error)")
    }
}

// Example: Direct MCPClient usage with custom transport
func directMCPClientExample() async {
    let logger = Logger(label: "DirectMCPClientExample")
    logger.info("=== SwiftAgentKit Direct MCPClient Example ===")
    
    // Create a simple echo server for demonstration
    let echoServerProcess = Process()
    echoServerProcess.executableURL = URL(fileURLWithPath: "/bin/echo")
    echoServerProcess.arguments = ["Hello from echo server"]
    
    let inPipe = Pipe()
    let outPipe = Pipe()
    
    echoServerProcess.standardInput = inPipe
    echoServerProcess.standardOutput = outPipe
    
    do {
        logger.info("Starting echo server process...")
        try echoServerProcess.run()
        
        // Create MCPClient
        let client = MCPClient(name: "echo-client", version: "1.0.0")
        
        // Connect using the new transport-based approach
        logger.info("Connecting MCPClient to echo server...")
        try await client.connect(inPipe: inPipe, outPipe: outPipe)
        logger.info("✓ MCPClient connected successfully")
        
        // Demonstrate client state
        let state = await client.state
        logger.info("Client state: \(state)")
        
        // Check available tools (echo server might not have MCP tools, but we can still connect)
        let toolCount = await client.tools.count
        logger.info("Available tools: \(toolCount)")
        
        logger.info("Note: Echo server doesn't implement MCP protocol")
        logger.info("In a real scenario, you would connect to an MCP-compliant server")
        
        // Clean up
        echoServerProcess.terminate()
        
    } catch {
        logger.error("Failed to demonstrate direct MCPClient usage: \(error)")
        echoServerProcess.terminate()
    }
}

// Example: Error handling with the new architecture
func newMCPErrorHandlingExample() async {
    let logger = Logger(label: "NewMCPErrorHandlingExample")
    logger.info("=== SwiftAgentKit New MCP Error Handling Example ===")
    
    // Example 1: Try to use MCPClient without connecting
    let client = MCPClient(name: "test-client", version: "1.0.0")
    
    do {
        logger.info("Attempting to call tool without connecting...")
        let _ = try await client.callTool("test_tool", arguments: ["test": "value"])
    } catch {
        logger.error("Expected error when not connected: \(error)")
    }
    
    // Example 2: Try to boot non-existent server
    let serverManager = MCPServerManager()
    
    let invalidBootCall = MCPConfig.ServerBootCall(
        name: "non-existent-server",
        command: "/path/to/nonexistent/server",
        arguments: [],
        environment: .object([:])
    )
    
    do {
        logger.info("Attempting to boot non-existent server...")
        let _ = try await serverManager.bootServer(bootCall: invalidBootCall)
    } catch {
        logger.error("Expected error when server doesn't exist: \(error)")
    }
    
    // Example 3: Try to connect to invalid pipes
    let invalidClient = MCPClient(name: "invalid-client", version: "1.0.0")
    
    do {
        logger.info("Attempting to connect with invalid pipes...")
        // Create pipes but don't connect them to any process
        let inPipe = Pipe()
        let outPipe = Pipe()
        
        try await invalidClient.connect(inPipe: inPipe, outPipe: outPipe)
        logger.info("✓ Connected with pipes (this might work for basic connection)")
        
    } catch {
        logger.error("Error connecting with pipes: \(error)")
    }
}

// Example: Multiple servers with the new architecture
func multipleServersExample() async {
    let logger = Logger(label: "MultipleServersExample")
    logger.info("=== SwiftAgentKit Multiple Servers Example ===")
    
    // Create configuration with multiple servers
    let server1 = MCPConfig.ServerBootCall(
        name: "server-1",
        command: "echo",
        arguments: ["Server 1 response"],
        environment: .object(["SERVER_ID": .string("1")])
    )
    
    let server2 = MCPConfig.ServerBootCall(
        name: "server-2", 
        command: "echo",
        arguments: ["Server 2 response"],
        environment: .object(["SERVER_ID": .string("2")])
    )
    
    var config = MCPConfig()
    config.serverBootCalls = [server1, server2]
    config.globalEnvironment = .object([
        "SHARED_ENV": .string("shared-value")
    ])
    
    let serverManager = MCPServerManager()
    
    do {
        logger.info("Booting multiple servers...")
        let serverPipes = try await serverManager.bootServers(config: config)
        logger.info("✓ Booted \(serverPipes.count) servers")
        
        // Create and connect clients for each server
        for (serverName, pipes) in serverPipes {
            logger.info("Setting up client for \(serverName)...")
            
            let client = MCPClient(name: serverName, version: "1.0.0")
            try await client.connect(inPipe: pipes.inPipe, outPipe: pipes.outPipe)
            
            let state = await client.state
            logger.info("✓ \(serverName) client state: \(state)")
        }
        
    } catch {
        logger.error("Failed to boot multiple servers: \(error)")
    }
}

// Example: Using MCPManager with the new architecture (backward compatibility)
func mcpManagerWithNewArchitectureExample() async {
    let logger = Logger(label: "MCPManagerNewArchExample")
    logger.info("=== SwiftAgentKit MCPManager with New Architecture Example ===")
    
    // Create a sample config file
    let sampleConfig = """
    {
        "serverBootCalls": [
            {
                "name": "example-server",
                "command": "echo",
                "arguments": ["hello from MCPManager"],
                "environment": {
                    "API_KEY": "your-api-key"
                }
            }
        ],
        "globalEnvironment": {
            "LOG_LEVEL": "info"
        }
    }
    """
    
    let tempDir = FileManager.default.temporaryDirectory
    let configURL = tempDir.appendingPathComponent("mcp-config-new.json")
    
    do {
        try sampleConfig.write(to: configURL, atomically: true, encoding: .utf8)
        logger.info("Created sample config at: \(configURL.path)")
        
        // Use MCPManager (which now uses the new architecture internally)
        let mcpManager = MCPManager()
        try await mcpManager.initialize(configFileURL: configURL)
        logger.info("✓ MCPManager initialized using new architecture")
        
        // Demonstrate tool call
        let toolCall = ToolCall(
            name: "example_tool",
            arguments: ["input": "Hello from new architecture!"],
            instructions: "Process this input"
        )
        
        if let messages = try await mcpManager.toolCall(toolCall) {
            logger.info("✓ Tool call successful with \(messages.count) messages")
        } else {
            logger.info("⚠ Tool call returned no messages")
        }
        
        // Clean up
        try FileManager.default.removeItem(at: configURL)
        
    } catch {
        logger.error("Failed to demonstrate MCPManager with new architecture: \(error)")
        try? FileManager.default.removeItem(at: configURL)
    }
}

// Run examples
print("Starting MCP Examples...")

// Run examples in a Task to handle async functions
Task {
    print("Running newMCPArchitectureExample...")
    await newMCPArchitectureExample()
    print("Running directMCPClientExample...")
    await directMCPClientExample()
    print("Running newMCPErrorHandlingExample...")
    await newMCPErrorHandlingExample()
    print("Running multipleServersExample...")
    await multipleServersExample()
    print("Running mcpManagerWithNewArchitectureExample...")
    await mcpManagerWithNewArchitectureExample()
    print("MCP Examples completed!")
}

// Keep the main thread alive for a moment to allow async tasks to complete
Thread.sleep(forTimeInterval: 3.0) 