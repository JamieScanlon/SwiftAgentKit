# SwiftAgentKitAdapters

The SwiftAgentKitAdapters module provides standard agent adapters for popular AI providers and tool integration capabilities.

## Folder Structure

```
Sources/SwiftAgentKitAdapters/
├── Core/                           # Core module functionality
│   ├── SwiftAgentKitAdapters.swift # Main module exports
│   └── AdapterBuilder.swift        # Builder pattern for easy adapter assembly
├── Adapters/                       # LLM provider adapters
│   ├── LLMProtocolAdapter.swift    # Generic wrapper for any LLMProtocol implementation
│   ├── OpenAIAdapter.swift         # OpenAI GPT models (GPT-4, GPT-3.5, etc.)
│   ├── AnthropicAdapter.swift      # Anthropic Claude models
│   └── GeminiAdapter.swift         # Google Gemini models
├── ToolProviders/                  # Tool integration providers
│   ├── A2AToolProvider.swift       # A2A clients as tools
│   └── MCPToolProvider.swift       # MCP clients as tools
└── ToolAware/                      # Tool-aware adapter functionality
    └── ToolAwareAdapter.swift      # Enhanced adapter with tool capabilities
```

## Components

### Core
- **SwiftAgentKitAdapters.swift**: Main module exports and type aliases
- **AdapterBuilder.swift**: Builder pattern for easily assembling adapters with different tool capabilities

### Adapters
- **LLMProtocolAdapter**: Generic adapter that wraps any `LLMProtocol` implementation
- **OpenAIAdapter**: Integration with OpenAI's GPT models
- **AnthropicAdapter**: Integration with Anthropic's Claude models
- **GeminiAdapter**: Integration with Google's Gemini models

### ToolProviders
- **A2AToolProvider**: Wraps A2A clients to provide them as tools
- **MCPToolProvider**: Wraps MCP clients to provide them as tools

### ToolAware
- **ToolAwareAdapter**: Enhanced adapter that can use tools while keeping the base adapter unchanged

## Usage

### Basic Adapter Usage
```swift
import SwiftAgentKitAdapters

// Create an OpenAI adapter
let openAIAdapter = OpenAIAdapter(apiKey: "your-api-key")

// Create an A2A server with the adapter
let server = A2AServer(port: 4245, adapter: openAIAdapter)
```

### Tool-Aware Usage
```swift
import SwiftAgentKitAdapters

// Create base adapter
let baseAdapter = OpenAIAdapter(apiKey: "your-api-key")

// Create tool providers
let a2aProvider = A2AToolProvider(clients: [a2aClient])
let mcpProvider = MCPToolProvider(clients: [mcpClient])

// Build tool-aware adapter
let toolAwareAdapter = AdapterBuilder()
    .withLLM(baseAdapter)
    .withToolProviders([a2aProvider, mcpProvider])
    .build()
```

### Generic LLM Wrapper
```swift
import SwiftAgentKitAdapters

// Create your custom LLM
let myLLM = MyCustomLLM(model: "my-model")

// Wrap it with the adapter
let adapter = LLMProtocolAdapter(
    llm: myLLM,
    model: "my-model",
    maxTokens: 1000,
    temperature: 0.7
)
```

## Architecture

The module is organized to provide:

1. **Separation of Concerns**: Each component has a clear responsibility
2. **Modularity**: Components can be used independently or combined
3. **Extensibility**: Easy to add new adapters or tool providers
4. **Composability**: Use the builder pattern to assemble complex configurations

## Adding New Adapters

To add a new adapter:

1. Create a new file in the `Adapters/` directory
2. Implement the `AgentAdapter` protocol (or `ToolAwareAgentAdapter` for tool support)
3. Add any necessary imports and dependencies
4. Update the main module exports if needed

## Adding New Tool Providers

To add a new tool provider:

1. Create a new file in the `ToolProviders/` directory
2. Implement the `ToolProvider` protocol
3. Add the provider to the `AdapterBuilder` if needed

## Testing

All components include comprehensive tests in the `Tests/SwiftAgentKitAdaptersTests/` directory. 