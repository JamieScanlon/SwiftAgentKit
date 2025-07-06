# SwiftAgentKit

A comprehensive toolkit for building local AI agents in Swift with optional sub-packages for different functionality.

## Overview

SwiftAgentKit is designed as a modular package that allows you to choose which components you need for your AI agent project. The package includes:

- **Core Module** (`SwiftAgentKit`) - Basic functionality and logging
- **A2A Module** (`SwiftAgentKitA2A`) - Agent-to-Agent communication
- **MCP Module** (`SwiftAgentKitMCP`) - Model Context Protocol support

## Installation

### Swift Package Manager

Add SwiftAgentKit to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/JamieScanlon/SwiftAgentKit.git", from: "0.1.0")
]
```

## Usage

### Basic Setup

Import only the core module for basic functionality:

```swift
import SwiftAgentKit

let config = SwiftAgentKitConfig(
    enableLogging: true,
    logLevel: .info
)

let manager = SwiftAgentKitManager(config: config)
let core = manager.getCore()
core.log("SwiftAgentKit initialized!")
```

### Using Optional Modules

#### A2A (Agent-to-Agent) Module

```swift
import SwiftAgentKit
import SwiftAgentKitA2A

let config = SwiftAgentKitConfig(
    enableLogging: true,
    enableA2A: true
)

let manager = SwiftAgentKitManager(config: config)
// A2A functionality is now available
```

#### MCP (Model Context Protocol) Module

```swift
import SwiftAgentKit
import SwiftAgentKitMCP

let config = SwiftAgentKitConfig(
    enableLogging: true,
    enableMCP: true
)

let manager = SwiftAgentKitManager(config: config)
// MCP functionality is now available
```

### Using Multiple Modules

You can enable multiple modules at once:

```swift
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitMCP

let config = SwiftAgentKitConfig(
    enableLogging: true,
    logLevel: .debug,
    enableA2A: true,
    enableMCP: true
)

let manager = SwiftAgentKitManager(config: config)
// All modules are now available
```

---

## A2A Module: Agent-to-Agent Communication

The A2A module provides support for the [Agent-to-Agent (A2A) protocol](https://a2aproject.github.io/A2A/v0.2.5/specification/), enabling your agent to communicate with other A2A-compliant agents and servers. This module includes both client and server implementations.

### Key Types
- **A2AClient**: Connects to and communicates with A2A servers
- **A2AServer**: Creates an A2A-compliant server that other agents can connect to
- **A2AConfig**: Configuration for A2A servers and boot calls
- **AgentAdapter**: Protocol for implementing custom agent behavior

### Example: Setting up an A2A Client

```swift
import SwiftAgentKitA2A

// Load A2A configuration from a JSON file
let configURL = URL(fileURLWithPath: "./a2a-config.json")
let a2aConfig = try A2AConfigHelper.parseA2AConfig(fileURL: configURL)

// Create a client for the first configured server
let server = a2aConfig.servers.first!
let bootCall = a2aConfig.serverBootCalls.first { $0.name == server.name }
let client = A2AClient(server: server, bootCall: bootCall)

Task {
    try await client.initializeA2AClient(globalEnvironment: a2aConfig.globalEnvironment)
    print("A2A client connected to \(server.name)!")
}
```

### Example: Sending a Message to an Agent

```swift
Task {
    let messageParams = MessageSendParams(
        message: A2AMessage(
            role: "user",
            parts: [.text(text: "Hello, can you help me with a task?")],
            messageId: UUID().uuidString
        )
    )
    
    let result = try await client.sendMessage(params: messageParams)
    
    switch result {
    case .message(let message):
        print("Received message: \(message.parts)")
    case .task(let task):
        print("Task created: \(task.id)")
    }
}
```

### Example: Streaming Messages from an Agent

```swift
Task {
    let messageParams = MessageSendParams(
        message: A2AMessage(
            role: "user",
            parts: [.text(text: "Generate a long response")],
            messageId: UUID().uuidString
        )
    )
    
    for try await response in client.streamMessage(params: messageParams) {
        switch response.result {
        case .message(let message):
            print("Streamed message: \(message.parts)")
        case .task(let task):
            print("Task created: \(task.id)")
        case .taskStatusUpdate(let status):
            print("Status update: \(status.state)")
        case .taskArtifactUpdate(let artifact):
            print("New artifact: \(artifact.artifactId)")
        }
    }
}
```

### Example: Creating an A2A Server

```swift
import SwiftAgentKitA2A

// Implement the AgentAdapter protocol
struct MyAgentAdapter: AgentAdapter {
    var cardCapabilities: AgentCard.AgentCapabilities {
        .init(streaming: true, pushNotifications: false)
    }
    
    var skills: [AgentCard.AgentSkill] {
        [
            .init(
                id: "text-generation",
                name: "Text Generation",
                description: "Generates text based on prompts",
                tags: ["text", "generation"]
            )
        ]
    }
    
    var defaultInputModes: [String] { ["text/plain"] }
    var defaultOutputModes: [String] { ["text/plain"] }
    
    func handleSend(_ params: MessageSendParams, store: TaskStore) async throws -> A2ATask {
        // Create a task for processing the message
        let taskId = UUID().uuidString
        let contextId = UUID().uuidString
        
        let task = A2ATask(
            id: taskId,
            contextId: contextId,
            status: TaskStatus(state: .working)
        )
        
        // Store the task
        await store.storeTask(task)
        
        // Process the message asynchronously
        Task {
            // Simulate processing
            try await Task.sleep(for: .seconds(2))
            
            // Create response message
            let responseMessage = A2AMessage(
                role: "assistant",
                parts: [.text(text: "I processed your request: \(params.message.parts)")],
                messageId: UUID().uuidString,
                taskId: taskId
            )
            
            // Update task with completed status
            var updatedTask = task
            updatedTask.status = TaskStatus(
                state: .completed,
                message: responseMessage
            )
            await store.storeTask(updatedTask)
        }
        
        return task
    }
    
    func handleStream(_ params: MessageSendParams, store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws {
        // Handle streaming requests
        let taskId = UUID().uuidString
        let contextId = UUID().uuidString
        
        let task = A2ATask(
            id: taskId,
            contextId: contextId,
            status: TaskStatus(state: .working)
        )
        
        await store.storeTask(task)
        
        // Stream status updates
        for i in 1...5 {
            try await Task.sleep(for: .seconds(1))
            
            let statusUpdate = TaskStatusUpdateEvent(
                taskId: taskId,
                status: TaskStatus(
                    state: i == 5 ? .completed : .working,
                    message: A2AMessage(
                        role: "assistant",
                        parts: [.text(text: "Processing step \(i)/5")],
                        messageId: UUID().uuidString,
                        taskId: taskId
                    )
                )
            )
            
            eventSink(statusUpdate)
        }
    }
}

// Create and start the server
let adapter = MyAgentAdapter()
let server = A2AServer(port: 4245, adapter: adapter)

Task {
    try await server.start()
    print("A2A server started on port 4245")
}
```

### Configuration File Format

The A2A module uses a JSON configuration file to define servers and boot calls:

```json
{
  "a2aServers": {
    "my-agent": {
      "boot": {
        "command": "/path/to/agent",
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
```

### Logging
All A2A operations use Swift's cross-platform `os.Logger` for structured logging. You can view logs using the macOS Console app or with:

```
log stream --predicate 'subsystem == "com.swiftagentkit"' --style compact
```

---

## MCP Module: Model Context Protocol

The MCP module provides support for the [Model Context Protocol (MCP)](https://modelcontextprotocol.org), enabling your agent to connect to and interact with MCP-compliant model servers, tools, and resources.

### Key Types
- **MCPClient**: Manages the connection to an MCP server, tool invocation, and resource access.
- **MCPConfig**: Loads and parses configuration for MCP servers and environments.

### Example: Loading MCP Config and Starting a Client

```swift
import SwiftAgentKitMCP

// Load MCP config from a JSON file
let configURL = URL(fileURLWithPath: "./mcp-config.json")
let mcpConfig = try MCPConfigHelper.parseMCPConfig(fileURL: configURL)

// Start a client for the first configured server
let bootCall = mcpConfig.serverBootCalls.first!
let client = MCPClient(bootCall: bootCall, version: "1.0.0")

Task {
    try await client.initializeMCPClient(config: mcpConfig)
    print("MCP client connected!")
}
```

### Example: Listing Tools and Calling a Tool

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

### Example: Subscribing to Resource Updates

```swift
Task {
    try await client.getResources()
    if let resource = client.resources.first {
        try await client.subscribeToResource(resource.uri)
        print("Subscribed to resource: \(resource.uri)")
    }
}
```

### Logging
All MCP operations use Swift's cross-platform `os.Logger` for structured logging. You can view logs using the macOS Console app or with:

```
log stream --predicate 'subsystem == "com.swiftagentkit"' --style compact
```

---

## Networking Module

SwiftAgentKit provides a modular networking layer for making HTTP requests, handling streaming responses, and working with Server-Sent Events (SSE). The networking code is organized under `Sources/SwiftAgentKit/Networking/` and is composed of the following main classes:

- **RestAPIManager**: High-level interface for making requests, streaming, and SSE.
- **RequestBuilder**: Constructs URLRequests from endpoints, parameters, and headers.
- **ResponseValidator**: Validates HTTP responses and decodes data.
- **StreamClient**: Handles streaming HTTP responses using Swift concurrency.
- **SSEClient**: Handles Server-Sent Events (SSE) connections and event parsing.

### Example: Basic Request

```swift
import SwiftAgentKit
// If needed: import SwiftAgentKit.Networking

let manager = RestAPIManager(baseURL: URL(string: "https://api.example.com")!)

Task {
    do {
        let result: MyDecodableType = try await manager.request(
            endpoint: "/data",
            method: .get,
            parameters: ["foo": "bar"],
            headers: ["Authorization": "Bearer ..."]
        )
        print(result)
    } catch {
        print("Request failed: \(error)")
    }
}
```

### Example: Streaming Response

```swift
Task {
    do {
        for try await chunk in manager.stream(
            endpoint: "/stream",
            method: .get,
            parameters: nil,
            headers: nil
        ) {
            print("Received chunk: \(chunk)")
        }
    } catch {
        print("Streaming failed: \(error)")
    }
}
```

### Example: Server-Sent Events (SSE)

```swift
Task {
    do {
        for try await event in manager.sse(
            endpoint: "/sse",
            parameters: nil,
            headers: nil
        ) {
            print("Received SSE event: \(event)")
        }
    } catch {
        print("SSE failed: \(error)")
    }
}
```

### Customizing Requests

You can use `RequestBuilder` and `ResponseValidator` directly for advanced scenarios:

```swift
let builder = RequestBuilder(baseURL: URL(string: "https://api.example.com")!)
let validator = ResponseValidator()

let request = try builder.buildRequest(
    endpoint: "/custom",
    method: .post,
    parameters: ["foo": "bar"],
    headers: nil
)

let (data, response) = try await URLSession.shared.data(for: request)
let decoded: MyDecodableType = try validator.validateAndDecode(data: data, response: response)
```

---

## Package Structure

```
SwiftAgentKit/
├── Sources/
│   ├── SwiftAgentKit/           # Core functionality
│   ├── SwiftAgentKitA2A/        # Agent-to-Agent communication
│   └── SwiftAgentKitMCP/        # Model Context Protocol
├── Tests/
│   ├── SwiftAgentKitTests/
│   ├── SwiftAgentKitA2ATests/
│   └── SwiftAgentKitMCPTests/
└── Package.swift
```

## Dependencies

- **Core**: No external dependencies
- **A2A**: Vapor, EasyJSON
- **MCP**: SwiftNIO, MCP SDK

## Requirements

- macOS 13.0+
- iOS 16.0+
- visionOS 1.0+
- Swift 6.0+

## License

[Add your license information here]

## Contributing

[Add contribution guidelines here]
