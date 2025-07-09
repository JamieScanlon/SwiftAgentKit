# A2A Module: Agent-to-Agent Communication

The A2A module provides support for the [Agent-to-Agent (A2A) protocol](https://a2aproject.github.io/A2A/v0.2.5/specification/), enabling your agent to communicate with other A2A-compliant agents and servers. This module includes both client and server implementations.

## Key Types
- **A2AManager**: Manages multiple A2A clients and agent calls. Now requires a config file URL provided by the consumer.
- **A2AClient**: Connects to and communicates with A2A servers
- **A2AServer**: Creates an A2A-compliant server that other agents can connect to
- **A2AConfig**: Configuration for A2A servers and boot calls
- **AgentAdapter**: Protocol for implementing custom agent behavior

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
        instructions: "Generate creative text based on the provided prompt"
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

## Example: Creating an A2A Server

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
All A2A operations use Swift Logging for structured logging. You can view logs using the macOS Console app or with:

```
log stream --predicate 'subsystem == "com.swiftagentkit"' --style compact
``` 