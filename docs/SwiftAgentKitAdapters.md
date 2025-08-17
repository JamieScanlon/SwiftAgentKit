# SwiftAgentKit Adapters

The `SwiftAgentKitAdapters` module provides standard agent adapters for popular AI providers, making it easy to integrate with various language models through a unified interface.

## Overview

This module includes adapters for:
- **OpenAI** - GPT models (gpt-4o, gpt-4, gpt-3.5-turbo, etc.)
- **Anthropic** - Claude models (claude-3-5-sonnet, claude-3-opus, etc.)
- **Google Gemini** - Gemini models (gemini-1.5-flash, gemini-1.5-pro, etc.)

All adapters implement the `AgentAdapter` protocol from `SwiftAgentKitA2A`, allowing them to be used with A2A servers. As of the latest API, adapter handlers accept an existing `A2ATask` and write results as `artifacts` and status updates into a shared `TaskStore` rather than returning a response object.

## Tool-Aware Adapters

The module also provides a composable architecture for building adapters with A2A and MCP tool calling capabilities:

- **ToolProvider Protocol** - Base protocol for any tool system
- **ToolManager** - Coordinates multiple tool providers
- **A2AToolProvider** - Wraps A2A clients as tools
- **MCPToolProvider** - Wraps MCP clients as tools
- **ToolAwareAdapter** - Enhanced adapter with tool capabilities
- **AdapterBuilder** - Builder pattern for easy assembly

## Installation

Add the `SwiftAgentKitAdapters` dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-repo/SwiftAgentKit.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            "SwiftAgentKitAdapters"
        ]
    )
]
```

## OpenAI Adapter

The `OpenAIAdapter` provides integration with OpenAI's GPT models through their Chat Completions API. This adapter is particularly important as many other AI providers have adopted the OpenAI API format.

### Basic Usage

```swift
let adapter = OpenAIAdapter(
    apiKey: "your-openai-api-key",
    model: "gpt-4o",
    systemPrompt: "You are a helpful assistant."
)
```

### Configuration Options

- `apiKey`: Your OpenAI API key
- `model`: The model to use (default: "gpt-4o")
- `baseURL`: Custom base URL for the API (default: OpenAI's official URL)
- `maxTokens`: Maximum number of tokens to generate
- `temperature`: Controls randomness (0.0 to 2.0)
- `systemPrompt`: System message to set the assistant's behavior
- `topP`: Nucleus sampling parameter (0.0 to 1.0)
- `frequencyPenalty`: Reduces repetition of frequent tokens (-2.0 to 2.0)
- `presencePenalty`: Reduces repetition of any token (-2.0 to 2.0)
- `stopSequences`: Array of strings that stop generation when encountered
- `user`: User identifier for tracking and moderation

### Advanced Configuration

```swift
let config = OpenAIAdapter.Configuration(
    apiKey: "your-key",
    model: "gpt-4o",
    maxTokens: 1000,
    temperature: 0.7,
    systemPrompt: "You are an expert software developer. Provide detailed technical explanations.",
    topP: 0.9,
    frequencyPenalty: 0.1,
    presencePenalty: 0.1,
    stopSequences: ["END", "STOP"],
    user: "developer-user"
)
let adapter = OpenAIAdapter(configuration: config)
```

### Features

- **System Prompts**: Configure the assistant's behavior and role
- **Conversation History**: Maintains context across multiple messages
- **Comprehensive Parameters**: Support for all OpenAI API parameters
- **Error Handling**: Detailed error types for different failure scenarios
- **Cross-Provider Compatibility**: Works with any service that adopts OpenAI's API format

### Error Types

The adapter provides specific error types for different scenarios:
- `rateLimitExceeded`: When API rate limits are hit
- `quotaExceeded`: When API quota is exceeded
- `modelNotFound`: When the specified model doesn't exist
- `invalidApiKey`: When the API key is invalid
- `contextLengthExceeded`: When the conversation exceeds token limits

## Anthropic Adapter

The `AnthropicAdapter` provides integration with Anthropic's Claude models.

### Basic Usage

```swift
let adapter = AnthropicAdapter(
    apiKey: "your-anthropic-api-key",
    model: "claude-3-5-sonnet-20241022"
)
```

### Configuration Options

- `apiKey`: Your Anthropic API key
- `model`: The model to use (default: "claude-3-5-sonnet-20241022")
- `maxTokens`: Maximum number of tokens to generate
- `temperature`: Controls randomness (0.0 to 1.0)

## Gemini Adapter

The `GeminiAdapter` provides integration with Google's Gemini models.

### Basic Usage

```swift
let adapter = GeminiAdapter(
    apiKey: "your-gemini-api-key",
    model: "gemini-1.5-flash"
)
```

### Configuration Options

- `apiKey`: Your Gemini API key
- `model`: The model to use (default: "gemini-1.5-flash")
- `maxTokens`: Maximum number of tokens to generate
- `temperature`: Controls randomness (0.0 to 2.0)

## Using Adapters with A2A Servers

All adapters can be used with A2A servers to create standardized AI endpoints:

```swift
// Create an adapter
let openAIAdapter = OpenAIAdapter(
    apiKey: "your-key",
    model: "gpt-4o",
    systemPrompt: "You are a helpful coding assistant."
)

// Create an A2A server with the adapter
let server = A2AServer(port: 4246, adapter: openAIAdapter)

// Start the server
try await server.start()
```

## Tool-Aware Adapters

The tool-aware adapter system allows you to easily assemble adapters with different tool capabilities without modifying the core A2AServer or AgentAdapter protocol.

### Basic Setup (No Tools)

```swift
let adapter = AdapterBuilder()
    .withLLM(OpenAIAdapter(apiKey: "your-key"))
    .build()

let server = A2AServer(port: 4245, adapter: adapter)
```

### With A2A Agents

```swift
// Initialize A2A clients
let a2aClient = A2AClient(server: a2aServer)
try await a2aClient.initializeA2AClient()

let adapter = AdapterBuilder()
    .withLLM(AnthropicAdapter(apiKey: "your-key"))
    .withA2AClient(a2aClient)
    .build()
```

### With MCP Tools

```swift
// Initialize MCP clients using the new architecture
let serverManager = MCPServerManager()
let serverPipes = try await serverManager.bootServers(config: mcpConfig)

var mcpClients: [MCPClient] = []
for (serverName, pipes) in serverPipes {
    let client = MCPClient(name: serverName, version: "1.0")
    try await client.connect(inPipe: pipes.inPipe, outPipe: pipes.outPipe)
    mcpClients.append(client)
}

let adapter = AdapterBuilder()
    .withLLM(GeminiAdapter(apiKey: "your-key"))
    .withMCPClients(mcpClients)
    .build()
```

### With Both A2A and MCP

```swift
let adapter = AdapterBuilder()
    .withLLM(OpenAIAdapter(apiKey: "your-key"))
    .withA2AClient(a2aClient)
    .withMCPClients(mcpClients)
    .build()
```

### Custom Tool Provider

You can create custom tool providers by implementing the `ToolProvider` protocol:

```swift
struct CustomToolProvider: ToolProvider {
    public var name: String { "Custom Tools" }
    
    public var availableTools: [ToolDefinition] {
        [
            ToolDefinition(
                name: "custom_function",
                description: "A custom function that does something",
                type: .function
            )
        ]
    }
    
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        if toolCall.name == "custom_function" {
            return ToolResult(
                success: true,
                content: "Custom function executed successfully",
                metadata: .object(["source": .string("custom_function")])
            )
        }
        
        return ToolResult(
            success: false,
            content: "",
            error: "Unknown tool: \(toolCall.name)"
        )
    }
}

// Use the custom tool provider
let adapter = AdapterBuilder()
    .withLLM(OpenAIAdapter(apiKey: "your-key"))
    .withToolProvider(CustomToolProvider())
    .build()
```

### Manual Setup (Without Builder)

You can also create tool-aware adapters manually:

```swift
// Create tool providers
let a2aProvider = A2AToolProvider(clients: [a2aClient])
let mcpProvider = MCPToolProvider(clients: mcpClients)
let toolManager = ToolManager(providers: [a2aProvider, mcpProvider])

// Create enhanced adapter
let adapter = ToolAwareAdapter(
    baseAdapter: OpenAIAdapter(apiKey: "your-key"),
    toolManager: toolManager
)
```

## Custom Adapters

You can create custom adapters by implementing the `AgentAdapter` protocol:

```swift
struct CustomAdapter: AgentAdapter {
    var agentName: String {
        "Custom Agent"
    }
    
    var agentDescription: String {
        "A custom A2A-compliant agent with custom skill implementation."
    }
    
    var cardCapabilities: AgentCard.AgentCapabilities {
        .init(streaming: true, pushNotifications: false, stateTransitionHistory: true)
    }
    
    var skills: [AgentCard.AgentSkill] {
        [.init(id: "custom", name: "Custom", description: "Custom skill")]
    }
    
    var defaultInputModes: [String] { ["text/plain"] }
    var defaultOutputModes: [String] { ["text/plain"] }
    
    // New API: update the provided task in the TaskStore
    func handleSend(_ params: MessageSendParams, task: A2ATask, store: TaskStore) async throws {
        // Mark working
        await store.updateTaskStatus(id: task.id, status: TaskStatus(state: .working))
        // Produce an artifact and complete
        let artifact = Artifact(artifactId: UUID().uuidString, parts: [.text(text: "result text")])
        await store.updateTaskArtifacts(id: task.id, artifacts: [artifact])
        await store.updateTaskStatus(id: task.id, status: TaskStatus(state: .completed))
    }
    
    func handleStream(_ params: MessageSendParams, task: A2ATask, store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws {
        // Emit status and artifact update events while updating the store
    }
}
```

## Examples

See the example directories for complete demonstrations:

### AdaptersExample
The `Examples/AdaptersExample` directory demonstrates:
- Basic adapter usage
- Custom adapter implementations
- Enhanced OpenAI adapter features
- Multi-provider fallback strategies

### ToolAwareExample
The `Examples/ToolAwareExample` directory demonstrates:
- Basic tool-aware adapter setup
- A2A agent integration
- MCP tool integration
- Custom tool providers
- Builder pattern usage
- Manual setup without builder

Run the examples:
```bash
# Basic adapters
swift run AdaptersExample

# Tool-aware adapters
swift run ToolAwareExample
```

## Testing

The module includes comprehensive tests using the Swift Testing framework:

```bash
swift test --filter SwiftAgentKitAdaptersTests
```

## Architecture Benefits

The tool-aware adapter architecture provides several key benefits:

### Composable
Mix and match A2A agents and MCP tools as needed:
```swift
let adapter = AdapterBuilder()
    .withLLM(OpenAIAdapter(apiKey: "your-key"))
    .withA2AClient(weatherAgent)
    .withMCPClients(fileTools)
    .withToolProvider(CustomToolProvider())
    .build()
```

### Extensible
Easy to add new tool providers by implementing the `ToolProvider` protocol:
```swift
struct DatabaseToolProvider: ToolProvider {
    // Your database tool implementation
}
```

### Simple
Basic setup requires minimal code:
```swift
let adapter = AdapterBuilder()
    .withLLM(OpenAIAdapter(apiKey: "your-key"))
    .build()
```

### Flexible
Can use any LLM adapter with any combination of tools:
```swift
// OpenAI with A2A agents
let adapter1 = AdapterBuilder()
    .withLLM(OpenAIAdapter(apiKey: "your-key"))
    .withA2AClient(specialistAgent)
    .build()

// Anthropic with MCP tools
let adapter2 = AdapterBuilder()
    .withLLM(AnthropicAdapter(apiKey: "your-key"))
    .withMCPClients(webTools)
    .build()
```

### Backward Compatible
Existing adapters work unchanged:
```swift
// This still works exactly as before
let server = A2AServer(port: 4245, adapter: OpenAIAdapter(apiKey: "your-key"))
```

## Contributing

When adding new adapters:

1. Create a new adapter file in `Sources/SwiftAgentKitAdapters/`
2. Implement the `AgentAdapter` protocol
3. Add tests in `Tests/SwiftAgentKitAdaptersTests/`
4. Update documentation
5. Add the adapter to the module exports in `SwiftAgentKitAdapters.swift`

When adding new tool providers:

1. Create a new tool provider file in `Sources/SwiftAgentKitAdapters/`
2. Implement the `ToolProvider` protocol
3. Add tests in `Tests/SwiftAgentKitAdaptersTests/`
4. Update documentation with usage examples
5. Add the tool provider to the module exports if needed

## Implementation Status

### ✅ Completed
- ToolProvider protocol and supporting types
- ToolManager for coordinating multiple providers
- A2AToolProvider for A2A client integration
- MCPToolProvider for MCP client integration
- ToolAwareAdapter for enhanced adapter capabilities
- AdapterBuilder for easy assembly
- Comprehensive documentation and examples

### ⚠️ In Progress
- LLM tool calling integration (OpenAI function calling, Anthropic tool use, etc.)
- Streaming tool support
- Argument conversion for MCP tools
- Enhanced error handling and logging

### 🔮 Future Enhancements
- Tool discovery and automatic registration
- Tool composition (tools calling other tools)
- Tool versioning support
- Tool security and access control
- Tool metrics and performance tracking
5. Update this documentation
6. Add examples demonstrating usage 