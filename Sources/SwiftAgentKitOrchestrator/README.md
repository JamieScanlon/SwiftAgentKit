# SwiftAgentKitOrchestrator

SwiftAgentKitOrchestrator provides building blocks for creating LLM orchestrators that can:

- Use tools through MCP (Model Context Protocol)
- Communicate with other agents through A2A (Agent-to-Agent)

## Dependencies

This module depends on:
- `SwiftAgentKit` - Core functionality
- `SwiftAgentKitA2A` - Agent-to-Agent communication
- `SwiftAgentKitMCP` - Model Context Protocol support
- `swift-log` - Cross-platform logging

## Usage

```swift
import SwiftAgentKitOrchestrator
import SwiftAgentKit

// Create an LLM that conforms to LLMProtocol
let llm: LLMProtocol = SomeLLMImplementation(logger: logger)

// Create orchestrator configuration
let config = OrchestratorConfig(
    streamingEnabled: true,
    mcpEnabled: true,
    a2aEnabled: false
)

// Initialize the orchestrator with the LLM and configuration
let orchestrator = SwiftAgentKitOrchestrator(llm: llm, config: config, logger: logger)

// Access the underlying LLM if needed
let llmInstance = orchestrator.llmProtocol

// Access the configuration
let orchestratorConfig = orchestrator.orchestratorConfig

// Process a conversation
let conversation = [
    Message(id: UUID(), role: .user, content: "Hello"),
    Message(id: UUID(), role: .assistant, content: "Hi there!")
]

// Get the message stream for complete messages
let messageStream = await orchestrator.messageStream
var finalConversation: [Message]?

// Listen for complete messages
Task {
    for await message in messageStream {
        print("Received complete message: \(message.content)")
        finalConversation = finalConversation ?? []
        finalConversation?.append(message)
    }
}

// Process the conversation (this will publish to the streams)
try await orchestrator.updateConversation(conversation, availableTools: [])

// Note: The orchestrator automatically manages stream lifecycle and cleanup

// Example with available tools
let availableTools = [
    ToolDefinition(
        name: "calculator",
        description: "A simple calculator",
        parameters: [
            .init(name: "expression", description: "Mathematical expression", type: "string", required: true)
        ],
        type: .function
    )
]

let conversationWithTools = [
    Message(id: UUID(), role: .user, content: "What's 2 + 2?")
]

let toolConversationStream = orchestrator.updateConversation(conversationWithTools, availableTools: availableTools)
```

## Features

- **LLM Orchestration**: Coordinate multiple LLM interactions
- **Tool Integration**: Use MCP tools for enhanced capabilities
- **Agent Communication**: Connect with other agents via A2A
- **Cross-platform**: Works on macOS, iOS, and visionOS
- **Automatic Stream Management**: Handles streaming lifecycle and cleanup automatically

## Configuration

The `OrchestratorConfig` struct allows you to enable or disable specific features:

- **`streamingEnabled`**: Enable streaming responses from the LLM
- **`mcpEnabled`**: Enable MCP (Model Context Protocol) tool usage
- **`a2aEnabled`**: Enable A2A (Agent-to-Agent) communication

All configuration options default to `false` for safety.

## Main Functionality

The orchestrator provides an `updateConversation` method that:

- Takes an array of messages representing the conversation thread
- Takes an optional array of available tools that can be used during conversation processing
- Supports both synchronous and streaming responses based on configuration
- Preserves the original message order
- Handles errors gracefully with proper logging
- Automatically manages streaming lifecycle and cleanup

### Streaming Behavior

When `streamingEnabled` is `true`, the orchestrator:

- Publishes partial content chunks to the `partialContentStream` as they arrive
- Automatically finishes and cleans up the partial content stream when streaming completes
- Publishes the final complete message to the `messageStream`
- Handles tool calls and recursive conversation updates seamlessly

### Stream Management

The orchestrator provides two main streams:

- **`messageStream`**: Publishes complete messages (user, assistant, and tool messages)
- **`partialContentStream`**: Publishes streaming text chunks during LLM responses

Both streams are automatically managed and cleaned up when appropriate. The partial content stream is automatically finished when streaming completes, ensuring proper resource management.

## Examples

See `Examples/OrchestratorExample/` for usage examples. 