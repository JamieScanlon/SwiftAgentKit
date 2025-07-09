# MCP Module: Model Context Protocol

The MCP module provides support for the [Model Context Protocol (MCP)](https://modelcontextprotocol.org), enabling your agent to connect to and interact with MCP-compliant model servers, tools, and resources.

## Key Types
- **MCPManager**: Manages multiple MCP clients and tool calls. Now requires a config file URL provided by the consumer.
- **MCPClient**: Manages the connection to an MCP server, tool invocation, and resource access.
- **MCPConfig**: Loads and parses configuration for MCP servers and environments.

## Example: Loading MCP Config and Using MCPManager

```swift
import SwiftAgentKitMCP

// Load MCP config from a JSON file (consumer provides the file URL)
let configURL = URL(fileURLWithPath: "./mcp-config.json")

let mcpManager = MCPManager()

Task {
    try await mcpManager.initialize(configFileURL: configURL)
    // Now you can use mcpManager to call tools, etc.
}
```

## Example: Loading MCP Config and Starting a Client (Direct)

```swift
import SwiftAgentKitMCP

// Load MCP config from a JSON file
let configURL = URL(fileURLWithPath: "./mcp-config.json")
let mcpConfig = try MCPConfigHelper.parseMCPConfig(fileURL: configURL)

// Start a client for the first configured server
let bootCall = mcpConfig.serverBootCalls.first!
let client = MCPClient(bootCall: bootCall, version: "0.1.3")

Task {
    try await client.initializeMCPClient(config: mcpConfig)
    print("MCP client connected!")
}
```

## Example: Listing Tools and Calling a Tool

```swift
Task {
    try await client.getTools()
    print("Available tools: \(client.tools.map(\.name))")
    
    if let toolName = client.tools.first?.name {
        let result = try await client.callTool(toolName)
        print("Tool result: \(result ?? [])")
    }
}
```

## Example: Subscribing to Resource Updates

```swift
Task {
    try await client.getResources()
    if let resource = client.resources.first {
        try await client.subscribeToResource(resource.uri)
        print("Subscribed to resource: \(resource.uri)")
    }
}
```

## Configuration File Format

The MCP module uses a JSON configuration file to define MCP servers and environments:

```json
{
  "mcpServers": {
    "example-server": {
      "command": "/usr/local/bin/example-mcp-server",
      "args": ["--port", "4242"],
      "env": {
        "API_KEY": "your-api-key",
        "MODEL": "gpt-4",
        "LOG_LEVEL": "info"
      }
    },
    "another-server": {
      "command": "/path/to/another/server",
      "args": ["--config", "/path/to/config.json"],
      "env": {
        "DATABASE_URL": "postgresql://localhost:5432/mcp",
        "CACHE_ENABLED": "true"
      }
    }
  },
  "globalEnv": {
    "LOG_LEVEL": "info",
    "ENVIRONMENT": "development",
    "TIMEOUT": "30"
  }
}
```

## Configuration Fields

- **mcpServers**: Object containing server configurations
  - **command**: Path to the MCP server executable
  - **args**: Array of command-line arguments for the server
  - **env**: Environment variables specific to this server
- **globalEnv**: Environment variables shared across all servers

## Logging
All MCP operations use Swift Logging for structured logging. You can view logs using the macOS Console app or with:

```
log stream --predicate 'subsystem == "com.swiftagentkit"' --style compact
``` 