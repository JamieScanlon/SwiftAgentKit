# MCP Module: Model Context Protocol

The MCP module provides support for the [Model Context Protocol (MCP)](https://modelcontextprotocol.org), enabling your agent to connect to and interact with MCP-compliant model servers, tools, and resources.

## Architecture Overview

The MCP module follows a **separation of concerns** architecture:

- **MCPServerManager**: Handles server process bootup and management
- **MCPClient**: Manages communication with MCP servers (transport-agnostic)
- **ClientTransport**: Provides transport layer abstraction (stdio pipes)
- **MCPManager**: High-level manager that orchestrates multiple clients (backward compatible)

## Key Types

- **MCPServerManager**: Boots and manages MCP server processes, returns communication pipes
- **MCPClient**: Manages the connection to an MCP server, tool invocation, and resource access
- **ClientTransport**: Implements the Transport protocol for stdio-based communication
- **MCPManager**: Manages multiple MCP clients and tool calls (uses new architecture internally)
- **MCPConfig**: Configuration for MCP servers and environments

## New Architecture: Step-by-Step Usage

### Step 1: Create MCP Configuration

```swift
import SwiftAgentKitMCP

// Create server configuration programmatically
let serverBootCall = MCPConfig.ServerBootCall(
    name: "example-server",
    command: "/usr/local/bin/example-mcp-server",
    arguments: ["--port", "4242"],
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
```

### Step 2: Boot Servers with MCPServerManager

```swift
// Use MCPServerManager to boot servers
let serverManager = MCPServerManager()
let serverPipes = try await serverManager.bootServers(config: config)

// serverPipes is a dictionary: [String: (inPipe: Pipe, outPipe: Pipe)]
for (serverName, pipes) in serverPipes {
    print("Server \(serverName) is ready for connection")
}
```

### Step 3: Create and Connect MCPClient Instances

```swift
var clients: [MCPClient] = []

for (serverName, pipes) in serverPipes {
    // Create client with name and version
    let client = MCPClient(name: serverName, version: "1.0.0")
    
    // Connect using the new transport-based approach
    try await client.connect(inPipe: pipes.inPipe, outPipe: pipes.outPipe)
    
    clients.append(client)
}
```

### Step 4: Use Connected Clients

```swift
for client in clients {
    // Check client state
    let state = await client.state
    print("Client \(await client.name) state: \(state)")
    
    // Call tools (tools will be populated on first call)
    if let result = try await client.callTool("example_tool", arguments: ["input": "Hello"]) {
        print("Tool call successful with \(result.count) content items")
    }
}
```

## Direct MCPClient Usage with Custom Transport

```swift
// Create a custom transport (e.g., for testing or custom protocols)
let customTransport = MyCustomTransport()

// Create and connect client
let client = MCPClient(name: "custom-client", version: "1.0.0")
try await client.connect(transport: customTransport)

// Use the connected client
let state = await client.state
print("Client connected: \(state == .connected)")
```

## Backward Compatibility: Using MCPManager

The `MCPManager` continues to work with the new architecture internally:

```swift
// Load MCP config from a JSON file
let configURL = URL(fileURLWithPath: "./mcp-config.json")
let mcpManager = MCPManager()

Task {
    try await mcpManager.initialize(configFileURL: configURL)
    
    // Create a tool call
    let toolCall = ToolCall(
        name: "example_tool",
        arguments: ["input": "Hello from MCPManager"],
        instructions: "Process this input",
        id: UUID().uuidString
    )
    
    // Execute the tool call
    if let messages = try await mcpManager.toolCall(toolCall) {
        print("Tool call successful with \(messages.count) messages")
    }
}
```

## Error Handling

### MCPClient Errors

```swift
let client = MCPClient(name: "test-client", version: "1.0.0")

do {
    // This will throw MCPClientError.notConnected
    let _ = try await client.callTool("test_tool")
} catch MCPClient.MCPClientError.notConnected {
    print("Client is not connected")
} catch {
    print("Other error: \(error)")
}
```

### MCPServerManager Errors

```swift
let serverManager = MCPServerManager()

do {
    let invalidBootCall = MCPConfig.ServerBootCall(
        name: "non-existent",
        command: "/path/to/nonexistent/server",
        arguments: [],
        environment: .object([:])
    )
    
    let _ = try await serverManager.bootServer(bootCall: invalidBootCall)
} catch MCPServerManager.MCPServerManagerError.serverStartupFailed {
    print("Server failed to start")
} catch {
    print("Other error: \(error)")
}
```

## Configuration File Format

The MCP module uses a JSON configuration file to define MCP servers and environments:

```json
{
  "serverBootCalls": [
    {
      "name": "example-server",
      "command": "/usr/local/bin/example-mcp-server",
      "arguments": ["--port", "4242"],
      "environment": {
        "API_KEY": "your-api-key",
        "MODEL": "gpt-4",
        "LOG_LEVEL": "info"
      }
    },
    {
      "name": "another-server",
      "command": "/path/to/another/server",
      "arguments": ["--config", "/path/to/config.json"],
      "environment": {
        "DATABASE_URL": "postgresql://localhost:5432/mcp",
        "CACHE_ENABLED": "true"
      }
    }
  ],
  "globalEnvironment": {
    "LOG_LEVEL": "info",
    "ENVIRONMENT": "development",
    "TIMEOUT": "30"
  }
}
```

## Configuration Fields

- **serverBootCalls**: Array of server configurations
  - **name**: Unique identifier for the server
  - **command**: Path to the MCP server executable
  - **arguments**: Array of command-line arguments for the server
  - **environment**: Environment variables specific to this server
- **globalEnvironment**: Environment variables shared across all servers

## Architecture Benefits

### Separation of Concerns
- **MCPServerManager**: Focuses solely on server process management
- **MCPClient**: Focuses solely on MCP protocol communication
- **ClientTransport**: Provides transport layer abstraction
- **MCPManager**: Provides high-level orchestration

### Transport Agnostic
- `MCPClient` can work with any transport that implements the `Transport` protocol
- Easy to test with mock transports
- Support for different communication protocols (stdio, TCP, etc.)

### Improved Testability
- Each component can be tested independently
- Mock transports enable unit testing without real servers
- Clear interfaces make mocking straightforward

### Better Error Handling
- Specific error types for different failure modes
- Clear separation between server startup errors and communication errors
- Proper error propagation through the stack

## Remote MCP Server Authentication

### Automatic OAuth Discovery

When connecting to remote MCP servers that require OAuth authentication, SwiftAgentKit automatically handles OAuth discovery and dynamic client registration according to the MCP specification.

#### How It Works

1. **Initial Connection Attempt**: When no authentication is configured, the client first attempts to connect without authentication
2. **OAuth Challenge Detection**: If the server responds with `401 Unauthorized` and includes a `WWW-Authenticate` header with `resource_metadata`, the client detects this as an OAuth discovery opportunity
3. **Automatic Discovery**: The client automatically creates an `OAuthDiscoveryAuthProvider` and attempts OAuth discovery using the resource metadata
4. **Dynamic Client Registration**: If needed, the client performs dynamic client registration with the authorization server
5. **Retry Connection**: The client retries the connection with the discovered OAuth credentials

#### Example Response Triggering OAuth Discovery

```http
HTTP/1.1 401 Unauthorized
Content-Type: application/json; charset=utf-8
WWW-Authenticate: Bearer resource_metadata="https://mcp.example.com/.well-known/oauth-protected-resource"

{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"Missing or invalid OAuth authorization"}}
```

#### Configuration

No special configuration is required. Simply omit the `authType` and `authConfig` fields:

```swift
let config = MCPConfig.RemoteServerConfig(
    name: "oauth-server",
    url: "https://mcp.example.com/api"
    // No authType or authConfig - OAuth discovery will be attempted automatically
)

try await client.connectToRemoteServer(config: config)
```

#### Manual OAuth Configuration

You can also manually configure OAuth if you already have credentials:

```swift
let config = MCPConfig.RemoteServerConfig(
    name: "oauth-server",
    url: "https://mcp.example.com/api",
    authType: "OAuth",
    authConfig: .object([
        "resourceServerURL": .string("https://mcp.example.com"),
        "clientId": .string("your-client-id"),
        "redirectURI": .string("your-app://oauth-callback"),
        "useOAuthDiscovery": .boolean(true)
    ])
)
```

## Logging

The MCP module uses Swift Logging for structured logging across all operations, providing cross-platform logging capabilities for debugging and monitoring. 
