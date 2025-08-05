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

let conversationStream = orchestrator.updateConversation(conversation, availableTools: [])
var finalConversation: [Message]?

for try await result in conversationStream {
    switch result {
    case .stream(let message):
        // Handle streaming chunks
        print("Received: \(message.content)")
    case .complete(let conversation):
        // Handle final conversation history
        finalConversation = conversation
    }
}

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
- Returns a stream of `StreamResult<Message, [Message]>` containing both streaming chunks and final conversation history
- Supports both synchronous and streaming responses based on configuration
- Preserves the original message order
- Handles errors gracefully with proper logging
- Uses the `StreamResult` type for standardized streaming + final result pattern

## Examples

See `Examples/OrchestratorExample/` for usage examples. 