import Foundation
import Logging
import EasyJSON
import SwiftAgentKit
import SwiftAgentKitMCP

private func configureRemoteLogging() {
    SwiftAgentKitLogging.bootstrap(
        logger: Logger(label: "com.example.swiftagentkit.mcp.remote"),
        level: .info,
        metadata: SwiftAgentKitLogging.metadata(("example", .string("MCPRemote")))
    )
}

// Example: Connecting to Remote MCP Servers with Authentication
func remoteMCPExample() async {
    configureRemoteLogging()
    let logger = SwiftAgentKitLogging.logger(for: .examples("RemoteMCPExample"))
    logger.info("=== SwiftAgentKit Remote MCP Authentication Example ===")
    
    // Example 1: Direct MCPClient connection with Bearer token
    await directRemoteConnectionExample(logger: logger)
    
    // Example 2: Using MCPManager with mixed local and remote servers
    await mixedServersExample(logger: logger)
    
    // Example 3: Environment-based authentication
    await environmentAuthExample(logger: logger)
    
    // Example 4: Different authentication types
    await multipleAuthTypesExample(logger: logger)
}

// MARK: - Direct Remote Connection Example

func directRemoteConnectionExample(logger: Logger) async {
    logger.info("--- Direct Remote Connection Example ---")
    
    do {
        // Create authentication provider
        let authProvider = BearerTokenAuthProvider(token: "your-api-token-here")
        
        // Create MCP client
        let client = MCPClient(
            name: "remote-mcp-client",
            version: "1.0.0",
            connectionTimeout: 15.0
        )
        
        // Connect to remote MCP server
        let serverURL = URL(string: "https://api.example.com/mcp")!
        try await client.connectToRemoteServer(
            serverURL: serverURL,
            authProvider: authProvider,
            connectionTimeout: 30.0,
            requestTimeout: 60.0,
            maxRetries: 3
        )
        
        logger.info("✓ Successfully connected to remote MCP server")
        
        // List available tools
        let tools = await client.tools
        logger.info("Available tools: \(tools.map(\.name).joined(separator: ", "))")
        
        // Example tool call (if tools are available)
        if let firstTool = tools.first {
            logger.info("Calling tool: \(firstTool.name)")
            if let result = try await client.callTool(firstTool.name, arguments: nil) {
                logger.info("Tool result: \(result)")
            }
        }
        
    } catch {
        logger.error("Direct remote connection failed: \(error)")
    }
}

// MARK: - Mixed Servers Example (Local + Remote)

func mixedServersExample(logger: Logger) async {
    logger.info("--- Mixed Local and Remote Servers Example ---")
    
    // Create configuration with both local and remote servers
    var config = MCPConfig()
    
    // Local server configuration
    config.serverBootCalls = [
        MCPConfig.ServerBootCall(
            name: "local-server",
            command: "echo",
            arguments: ["Local MCP server"],
            environment: .object(["LOCAL_ENV": .string("local-value")])
        )
    ]
    
    // Remote servers configuration
    config.remoteServers = [
        MCPConfig.RemoteServerConfig(
            name: "remote-api-server",
            url: "https://api.example.com/mcp",
            authType: "bearer",
            authConfig: .object([
                "token": .string("remote-api-token")
            ]),
            connectionTimeout: 30.0,
            requestTimeout: 60.0,
            maxRetries: 3
        ),
        MCPConfig.RemoteServerConfig(
            name: "remote-oauth-server",
            url: "https://oauth.example.com/mcp",
            authType: "oauth",
            authConfig: .object([
                "accessToken": .string("oauth-access-token"),
                "refreshToken": .string("oauth-refresh-token"),
                "tokenEndpoint": .string("https://oauth.example.com/token"),
                "clientId": .string("my-client-id"),
                "clientSecret": .string("my-client-secret")
            ])
        )
    ]
    
    do {
        // Use MCPManager to handle both local and remote servers
        let mcpManager = MCPManager(connectionTimeout: 20.0)
        
        // Create temporary config file
        let tempDir = FileManager.default.temporaryDirectory
        let configURL = tempDir.appendingPathComponent("mixed-mcp-config.json")
        
        // Create JSON config manually (since MCPConfig encoding is complex)
        let configJSON = """
        {
            "serverBootCalls": [
                {
                    "name": "local-server",
                    "command": "echo",
                    "arguments": ["Local MCP server"],
                    "environment": {"LOCAL_ENV": "local-value"}
                }
            ],
            "remoteServers": {
                "remote-api-server": {
                    "url": "https://api.example.com/mcp",
                    "authType": "bearer",
                    "authConfig": {
                        "token": "remote-api-token"
                    },
                    "connectionTimeout": 30,
                    "requestTimeout": 60,
                    "maxRetries": 3
                }
            }
        }
        """
        try configJSON.write(to: configURL, atomically: true, encoding: .utf8)
        
        // Initialize MCPManager with the config
        try await mcpManager.initialize(configFileURL: configURL)
        
        logger.info("✓ MCPManager initialized with mixed servers")
        
        // Get available tools from all servers
        let allTools = await mcpManager.availableTools()
        logger.info("Total available tools from all servers: \(allTools.count)")
        
        // Clean up
        try FileManager.default.removeItem(at: configURL)
        
    } catch {
        logger.error("Mixed servers example failed: \(error)")
    }
}

// MARK: - Environment-Based Authentication Example

func environmentAuthExample(logger: Logger) async {
    logger.info("--- Environment-Based Authentication Example ---")
    
    // Set environment variables for different auth types
    setenv("ENVSERVER_TOKEN", "env-bearer-token", 1)
    setenv("APISERVER_API_KEY", "env-api-key", 1)
    setenv("BASICSERVER_USERNAME", "env-user", 1)
    setenv("BASICSERVER_PASSWORD", "env-pass", 1)
    
    defer {
        unsetenv("ENVSERVER_TOKEN")
        unsetenv("APISERVER_API_KEY")
        unsetenv("BASICSERVER_USERNAME")
        unsetenv("BASICSERVER_PASSWORD")
    }
    
    // Create remote servers that will use environment-based auth
    let remoteServers = [
        MCPConfig.RemoteServerConfig(
            name: "envserver",
            url: "https://env.example.com/mcp"
        ),
        MCPConfig.RemoteServerConfig(
            name: "apiserver",
            url: "https://api.example.com/mcp"
        ),
        MCPConfig.RemoteServerConfig(
            name: "basicserver",
            url: "https://basic.example.com/mcp"
        )
    ]
    
    for remoteConfig in remoteServers {
        do {
            // Test environment-based auth provider creation
            let authProvider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: remoteConfig.name)
            
            if let authProvider = authProvider {
                logger.info("✓ Created \(authProvider.scheme.rawValue) auth provider for \(remoteConfig.name)")
                
                let headers = try await authProvider.authenticationHeaders()
                logger.info("  Auth headers: \(headers.keys.joined(separator: ", "))")
            } else {
                logger.warning("⚠ No authentication found for \(remoteConfig.name)")
            }
            
        } catch {
            logger.error("Failed to create auth provider for \(remoteConfig.name): \(error)")
        }
    }
}

// MARK: - Multiple Authentication Types Example

func multipleAuthTypesExample(logger: Logger) async {
    logger.info("--- Multiple Authentication Types Example ---")
    
    // Example configurations for different auth types
    let authConfigs: [(String, String, JSON)] = [
        ("Bearer Token", "bearer", try! JSON([
            "token": "bearer-token-example"
        ])),
        ("API Key", "apikey", try! JSON([
            "apiKey": "api-key-example",
            "headerName": "X-Custom-API-Key",
            "prefix": "ApiKey "
        ])),
        ("Basic Auth", "basic", try! JSON([
            "username": "demo-user",
            "password": "demo-password"
        ])),
        ("OAuth", "oauth", try! JSON([
            "accessToken": "oauth-access-token",
            "refreshToken": "oauth-refresh-token",
            "tokenEndpoint": "https://auth.example.com/token",
            "clientId": "demo-client-id",
            "clientSecret": "demo-client-secret",
            "scope": "read write",
            "tokenType": "Bearer",
            "expiresIn": 3600
        ]))
    ]
    
    for (authName, authType, authConfig) in authConfigs {
        do {
            logger.info("Testing \(authName) authentication...")
            
            let authProvider = try AuthenticationFactory.createAuthProvider(
                authType: authType,
                config: authConfig
            )
            
            logger.info("✓ Created \(authProvider.scheme.rawValue) provider")
            
            let headers = try await authProvider.authenticationHeaders()
            logger.info("  Headers: \(headers.keys.joined(separator: ", "))")
            
            let isValid = await authProvider.isAuthenticationValid()
            logger.info("  Valid: \(isValid)")
            
        } catch {
            logger.error("Failed to test \(authName): \(error)")
        }
    }
}

// MARK: - Configuration File Example

func createSampleConfigFile() -> URL {
    let sampleConfig = """
    {
        "serverBootCalls": [
            {
                "name": "local-echo-server",
                "command": "echo",
                "arguments": ["Hello from local server"],
                "environment": {
                    "LOCAL_VAR": "local-value"
                }
            }
        ],
        "remoteServers": {
            "production-api": {
                "url": "https://api.production.com/mcp",
                "authType": "bearer",
                "authConfig": {
                    "token": "prod-api-token"
                },
                "connectionTimeout": 30,
                "requestTimeout": 120,
                "maxRetries": 5
            },
            "staging-oauth": {
                "url": "https://staging.example.com/mcp",
                "authType": "oauth",
                "authConfig": {
                    "accessToken": "staging-access-token",
                    "refreshToken": "staging-refresh-token",
                    "tokenEndpoint": "https://auth.staging.com/token",
                    "clientId": "staging-client-id"
                }
            },
            "dev-apikey": {
                "url": "https://dev.example.com/mcp",
                "authType": "apikey",
                "authConfig": {
                    "apiKey": "dev-api-key-123",
                    "headerName": "X-Dev-API-Key"
                }
            }
        },
        "globalEnvironment": {
            "LOG_LEVEL": "info",
            "ENVIRONMENT": "development"
        }
    }
    """
    
    let tempDir = FileManager.default.temporaryDirectory
    let configURL = tempDir.appendingPathComponent("remote-mcp-config.json")
    
    do {
        try sampleConfig.write(to: configURL, atomically: true, encoding: .utf8)
        return configURL
    } catch {
        fatalError("Failed to create sample config file: \(error)")
    }
}

// MARK: - Example Usage
// 
// To run this example, call remoteMCPExample() from your main function
// Example:
// Task {
//     await remoteMCPExample()
// }
