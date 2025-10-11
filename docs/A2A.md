# A2A Module: Agent-to-Agent Communication

The A2A module provides support for the [Agent-to-Agent (A2A) protocol](https://a2aproject.github.io/A2A/v0.2.5/specification/), enabling your agent to communicate with other A2A-compliant agents and servers. This module includes both client and server implementations.

## Key Types
- **A2AManager**: Manages multiple A2A clients and agent calls. Now requires a config file URL provided by the consumer.
- **A2AClient**: Connects to and communicates with A2A servers
- **A2AServer**: Creates an A2A-compliant server that other agents can connect to
- **A2AConfig**: Configuration for A2A servers and boot calls
- **AgentAdapter**: Protocol for implementing custom agent behavior. Handlers now receive an existing `A2ATask` and write updates (status and `artifacts`) to the shared `TaskStore` instead of returning a response directly.

## Example: Loading A2A Config and Using A2AManager

```swift
import SwiftAgentKitA2A

// Load A2A config from a JSON file (consumer provides the file URL)
let configURL = URL(fileURLWithPath: "./a2a-config.json")

let a2aManager = A2AManager()

Task {
    try await a2aManager.initialize(configFileURL: configURL)
    // Now you can use a2aManager to call agents, etc.
}
```

## Example: Setting up an A2A Client (Direct)

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

## Example: Making Agent Calls with A2AManager

```swift
Task {
    // Create a tool call for an A2A agent
    let toolCall = ToolCall(
        name: "text_generation",
        arguments: [
            "instructions": "Write a short story about a robot learning to paint"
        ],
        instructions: "Generate creative text based on the provided prompt",
        id: UUID().uuidString
    )
    
    // Execute the agent call
    if let messages = try await a2aManager.agentCall(toolCall) {
        print("Agent call successful! Received \(messages.count) messages:")
        for (index, message) in messages.enumerated() {
            print("Message \(index + 1): \(message.content)")
        }
    } else {
        print("Agent call returned no messages")
    }
}
```

## Example: Sending a Message to an Agent (Direct Client)

```swift
Task {
    let messageParams = MessageSendParams(
        message: A2AMessage(
            role: "user",
            parts: [.text(text: "Hello, can you help me with a task?")],
            messageId: UUID().uuidString
        ),
        configuration: MessageSendConfiguration(
            acceptedOutputModes: ["text/plain"],
            historyLength: 5,
            blocking: true
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

## Example: Streaming Messages from an Agent

```swift
Task {
    let messageParams = MessageSendParams(
        message: A2AMessage(
            role: "user",
            parts: [.text(text: "Generate a long response")],
            messageId: UUID().uuidString
        ),
        configuration: MessageSendConfiguration(
            acceptedOutputModes: ["text/plain"],
            blocking: false
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

## Message vs Task Responses

According to the A2A spec, an agent can respond with either a simple **Message** or a tracked **Task**. Your adapter implementation decides which to use:

### When to Use Message Responses

Return `.message(A2AMessage)` for:
- **Quick, synchronous responses** that complete immediately
- **Simple conversations** that don't need progress tracking
- **Lightweight interactions** where task overhead isn't needed

### When to Use Task Responses

Return `.task` for:
- **Long-running operations** that take time to complete
- **Operations with progress updates** that benefit from status tracking
- **Work that might be queried later** via `tasks/get`
- **Operations with multiple artifacts** that build up over time

## Example: Creating an A2A Server with Message Responses

```swift
import SwiftAgentKitA2A

// Simple adapter that returns messages for quick responses
struct QuickResponseAdapter: AgentAdapter {
    var agentName: String { "Quick Response Agent" }
    var agentDescription: String { "Provides instant responses to simple queries" }
    var cardCapabilities: AgentCard.AgentCapabilities {
        .init(streaming: false, pushNotifications: false)
    }
    var skills: [AgentCard.AgentSkill] {
        [.init(id: "qa", name: "Q&A", description: "Quick answers", tags: ["text"])]
    }
    var defaultInputModes: [String] { ["text/plain"] }
    var defaultOutputModes: [String] { ["text/plain"] }
    
    // Tell the server this adapter returns messages
    func responseType(for params: MessageSendParams) -> AdapterResponseType {
        return .message
    }
    
    // Handle message responses (called when responseType returns .message)
    func handleMessageSend(_ params: MessageSendParams) async throws -> A2AMessage {
        // Process the request quickly
        let responseText = "Here's a quick response to: \(params.message.parts)"
        
        // Return a simple message (no task tracking)
        return A2AMessage(
            role: "assistant",
            parts: [.text(text: responseText)],
            messageId: UUID().uuidString
        )
    }
    
    // Not used for message-only adapters
    func handleTaskSend(_ params: MessageSendParams, taskId: String, contextId: String, store: TaskStore) async throws {
        // Not called - this adapter always returns messages
    }
    
    func handleStream(_ params: MessageSendParams, taskId: String?, contextId: String?, store: TaskStore?, eventSink: @escaping (Encodable) -> Void) async throws {
        // Simple message streaming (no task tracking needed)
        let responseText = "Streaming quick response!"
        let message = A2AMessage(
            role: "assistant",
            parts: [.text(text: responseText)],
            messageId: UUID().uuidString
        )
        eventSink(SendStreamingMessageSuccessResponse(jsonrpc: "2.0", id: 1, result: MessageResult.message(message)))
    }
}
```

## Example: Creating an A2A Server with Task Responses

```swift
import SwiftAgentKitA2A

// Complex adapter that returns tasks for tracked operations
struct LongRunningAdapter: AgentAdapter {
    var agentName: String { "Long Running Agent" }
    var agentDescription: String { "Handles complex, long-running operations" }
    var cardCapabilities: AgentCard.AgentCapabilities {
        .init(streaming: true, pushNotifications: false)
    }
    var skills: [AgentCard.AgentSkill] {
        [.init(id: "analysis", name: "Analysis", description: "Deep analysis", tags: ["analysis"])]
    }
    var defaultInputModes: [String] { ["text/plain"] }
    var defaultOutputModes: [String] { ["text/plain"] }
    
    // Tell the server this adapter returns tasks
    func responseType(for params: MessageSendParams) -> AdapterResponseType {
        return .task
    }
    
    // Not used for task-only adapters
    func handleMessageSend(_ params: MessageSendParams) async throws -> A2AMessage {
        // Not called - this adapter always returns tasks
        fatalError("This adapter always returns tasks")
    }
    
    // Handle task responses (called when responseType returns .task)
    func handleTaskSend(_ params: MessageSendParams, taskId: String, contextId: String, store: TaskStore) async throws {
        // Mark as working
        await store.updateTaskStatus(
            id: taskId,
            status: TaskStatus(state: .working, timestamp: ISO8601DateFormatter().string(from: Date()))
        )
        
        // Simulate long-running work
        try await Task.sleep(for: .seconds(2))
        
        // Create artifacts
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [.text(text: "Analysis complete: processed \(params.message.parts)")]
        )
        await store.updateTaskArtifacts(id: taskId, artifacts: [artifact])
        
        // Mark completed
        await store.updateTaskStatus(
            id: taskId,
            status: TaskStatus(state: .completed, timestamp: ISO8601DateFormatter().string(from: Date()))
        )
    }
    
    func handleStream(_ params: MessageSendParams, taskId: String?, contextId: String?, store: TaskStore?, eventSink: @escaping (Encodable) -> Void) async throws {
        // Task-based streaming requires all parameters
        guard let taskId = taskId, let contextId = contextId, let store = store else {
            throw NSError(domain: "LongRunningAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Task streaming requires taskId, contextId, and store"])
        }
        
        // Send working status
        let working = TaskStatus(state: .working, timestamp: ISO8601DateFormatter().string(from: Date()))
        await store.updateTaskStatus(id: taskId, status: working)
        let workingEvent = TaskStatusUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            status: working,
            final: false
        )
        eventSink(SendStreamingMessageSuccessResponse(jsonrpc: "2.0", id: 1, result: MessageResult.taskStatusUpdate(workingEvent)))
        
        // Stream progress updates
        for i in 1...3 {
            try await Task.sleep(for: .seconds(1))
            let artifact = Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: "Progress update \(i)/3")],
                name: "progress-\(i)"
            )
            await store.updateTaskArtifacts(id: taskId, artifacts: [artifact])
            let artifactEvent = TaskArtifactUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                artifact: artifact,
                append: true,
                lastChunk: i == 3
            )
            eventSink(SendStreamingMessageSuccessResponse(jsonrpc: "2.0", id: 1, result: MessageResult.taskArtifactUpdate(artifactEvent)))
        }
        
        // Send completion
        let completed = TaskStatus(state: .completed, timestamp: ISO8601DateFormatter().string(from: Date()))
        await store.updateTaskStatus(id: taskId, status: completed)
        let completedEvent = TaskStatusUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            status: completed,
            final: true
        )
        eventSink(SendStreamingMessageSuccessResponse(jsonrpc: "2.0", id: 1, result: MessageResult.taskStatusUpdate(completedEvent)))
    }
}

// Create and start the server
let adapter = LongRunningAdapter() // or QuickResponseAdapter()
let server = A2AServer(port: 4245, adapter: adapter)

Task {
    try await server.start()
    print("A2A server started on port 4245")
}
```

## Configuration File Format

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

## Logging

The A2A module uses Swift Logging for structured logging across all operations, providing cross-platform logging capabilities for debugging and monitoring. 
