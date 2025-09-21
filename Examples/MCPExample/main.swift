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

// Example: Remote server connection using RemoteServerConfig
func remoteServerConfigExample() async {
    let logger = Logger(label: "RemoteServerConfigExample")
    logger.info("=== SwiftAgentKit Remote Server Config Example ===")
    
    // Example 1: Remote server with Bearer token authentication
    let bearerTokenConfig = MCPConfig.RemoteServerConfig(
        name: "api-server-bearer",
        url: "https://api.example.com/mcp",
        authType: "bearer",
        authConfig: .object([
            "token": .string("your-bearer-token-here")
        ]),
        connectionTimeout: 30.0,
        requestTimeout: 60.0,
        maxRetries: 3
    )
    
    // Example 2: Remote server with API Key authentication
    let apiKeyConfig = MCPConfig.RemoteServerConfig(
        name: "api-server-key",
        url: "https://api.example.com/mcp",
        authType: "apiKey",
        authConfig: .object([
            "apiKey": .string("your-api-key-here"),
            "headerName": .string("X-API-Key")
        ]),
        connectionTimeout: 30.0,
        requestTimeout: 60.0,
        maxRetries: 3
    )
    
    // Example 3: Remote server with PKCE OAuth authentication
    let pkceOAuthConfig = MCPConfig.RemoteServerConfig(
        name: "oauth-server",
        url: "https://mcp.example.com",
        authType: "OAuth",
        authConfig: .object([
            "issuerURL": .string("https://auth.example.com"),
            "clientId": .string("your-client-id"),
            "redirectURI": .string("com.example.mcpclient://oauth"),
            "scope": .string("mcp:read mcp:write"),
            "useOpenIDConnectDiscovery": .boolean(true),
            "resourceURI": .string("https://mcp.example.com")
        ]),
        connectionTimeout: 30.0,
        requestTimeout: 60.0,
        maxRetries: 3
    )
    
    // Example 4: Remote server without authentication
    let noAuthConfig = MCPConfig.RemoteServerConfig(
        name: "public-server",
        url: "https://public.mcp.example.com",
        authType: nil,
        authConfig: nil,
        connectionTimeout: 15.0,
        requestTimeout: 30.0,
        maxRetries: 2
    )
    
    let configs = [bearerTokenConfig, apiKeyConfig, pkceOAuthConfig, noAuthConfig]
    
    for config in configs {
        logger.info("Testing connection to \(config.name) (\(config.url))")
        
        let client = MCPClient(name: "test-client", version: "1.0.0")
        
        do {
            // Use the new connectToRemoteServer(config:) method
            try await client.connectToRemoteServer(config: config)
            logger.info("✓ Successfully connected to \(config.name)")
            
            // Check available tools
            let toolCount = await client.tools.count
            logger.info("  Available tools: \(toolCount)")
            
        } catch let oauthFlowError as OAuthManualFlowRequired {
            logger.info("🔐 OAuth manual flow required for \(config.name)")
            logger.info("📱 Authorization URL: \(oauthFlowError.authorizationURL)")
            logger.info("🔄 Redirect URI: \(oauthFlowError.redirectURI)")
            logger.info("🆔 Client ID: \(oauthFlowError.clientId)")
            if let scope = oauthFlowError.scope {
                logger.info("📋 Scope: \(scope)")
            }
            if let resourceURI = oauthFlowError.resourceURI {
                logger.info("🎯 Resource URI: \(resourceURI)")
            }
            
            // Example of how to handle the OAuth manual flow
            logger.info("💡 To complete authentication:")
            logger.info("   1. Open the authorization URL in a browser")
            logger.info("   2. Complete the OAuth authorization flow")
            logger.info("   3. Capture the authorization code from the redirect")
            logger.info("   4. Use the authorization code to complete authentication")
            
            // In a real application, you would:
            // - Open the URL in the system browser
            // - Set up a local server to capture the redirect
            // - Extract the authorization code
            // - Complete the token exchange
            
        } catch let mcpError as MCPClient.MCPClientError {
            switch mcpError {
            case .connectionFailed(let message):
                logger.warning("⚠ Connection to \(config.name) failed: \(message)")
            case .connectionTimeout(let timeout):
                logger.warning("⏰ Connection to \(config.name) timed out after \(timeout)s")
            case .notConnected:
                logger.warning("🔌 Client not connected to \(config.name)")
            case .pipeError(let message):
                logger.warning("🔌 Pipe error with \(config.name): \(message)")
            case .processTerminated(let message):
                logger.warning("💀 Process terminated for \(config.name): \(message)")
            }
        } catch {
            logger.error("❌ Unexpected error connecting to \(config.name): \(error)")
        }
    }
    
    logger.info("Note: These are example URLs and will fail to connect.")
    logger.info("Replace with actual MCP server URLs and valid authentication credentials.")
}

// Example: OAuth Manual Flow Handling
func oAuthManualFlowExample() async {
    let logger = Logger(label: "OAuthManualFlowExample")
    logger.info("=== SwiftAgentKit OAuth Manual Flow Example ===")
    
    // Example OAuth server configuration that will trigger manual flow
    let oauthConfig = MCPConfig.RemoteServerConfig(
        name: "oauth-server-example",
        url: "https://mcp.example.com",
        authType: "OAuth",
        authConfig: .object([
            "issuerURL": .string("https://auth.example.com"),
            "clientId": .string("example-client-id"),
            "redirectURI": .string("com.example.mcpclient://oauth"),
            "scope": .string("mcp:read mcp:write"),
            "useOpenIDConnectDiscovery": .boolean(true),
            "resourceURI": .string("https://mcp.example.com")
        ]),
        connectionTimeout: 30.0,
        requestTimeout: 60.0,
        maxRetries: 3
    )
    
    let client = MCPClient(name: "oauth-test-client", version: "1.0.0")
    
    do {
        logger.info("Attempting to connect to OAuth-protected MCP server...")
        try await client.connectToRemoteServer(config: oauthConfig)
        logger.info("✓ Successfully connected to OAuth-protected server")
        
    } catch let oauthFlowError as OAuthManualFlowRequired {
        logger.info("🔐 OAuth manual flow required!")
        logger.info("📱 Authorization URL: \(oauthFlowError.authorizationURL)")
        logger.info("🔄 Redirect URI: \(oauthFlowError.redirectURI)")
        logger.info("🆔 Client ID: \(oauthFlowError.clientId)")
        
        if let scope = oauthFlowError.scope {
            logger.info("📋 Scope: \(scope)")
        }
        if let resourceURI = oauthFlowError.resourceURI {
            logger.info("🎯 Resource URI: \(resourceURI)")
        }
        
        logger.info("📊 Additional Metadata:")
        for (key, value) in oauthFlowError.additionalMetadata {
            logger.info("   \(key): \(value)")
        }
        
        logger.info("💡 Implementation Steps:")
        logger.info("   1. Open authorization URL in browser: \(oauthFlowError.authorizationURL)")
        logger.info("   2. User completes OAuth authorization")
        logger.info("   3. Capture authorization code from redirect to: \(oauthFlowError.redirectURI)")
        logger.info("   4. Exchange authorization code for access token")
        logger.info("   5. Retry connection with valid access token")
        
        // Example of how you might handle this in a real application:
        // await handleOAuthManualFlow(oauthFlowError)
        
    } catch let mcpError as MCPClient.MCPClientError {
        logger.error("❌ MCP connection error: \(mcpError.localizedDescription)")
        
    } catch {
        logger.error("❌ Unexpected error: \(error)")
    }
}

// Example helper function for handling OAuth manual flow (commented out as it requires system integration)
/*
func handleOAuthManualFlow(_ oauthFlowError: OAuthManualFlowRequired) async {
    let logger = Logger(label: "OAuthFlowHandler")
    
    // Step 1: Open the authorization URL in the system browser
    logger.info("Opening authorization URL in browser...")
    if let url = URL(string: oauthFlowError.authorizationURL.absoluteString) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif os(Linux)
        // On Linux, you might use xdg-open or similar
        // system("xdg-open \(url.absoluteString)")
        #endif
    }
    
    // Step 2: Set up a local server to capture the redirect
    logger.info("Setting up local server to capture OAuth redirect...")
    // Implementation would depend on your platform and requirements
    
    // Step 3: Wait for the authorization code
    logger.info("Waiting for user to complete OAuth flow...")
    // You would implement a mechanism to wait for the redirect and extract the code
    
    // Step 4: Exchange the authorization code for tokens
    logger.info("Exchanging authorization code for access token...")
    // You would call the token endpoint with the authorization code
    
    // Step 5: Retry the connection
    logger.info("Retrying MCP connection with new access token...")
    // You would retry the original connection attempt
}
*/

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
    print("Running remoteServerConfigExample...")
    await remoteServerConfigExample()
    print("Running oAuthManualFlowExample...")
    await oAuthManualFlowExample()
    print("MCP Examples completed!")
}

// Keep the main thread alive for a moment to allow async tasks to complete
Thread.sleep(forTimeInterval: 3.0) 