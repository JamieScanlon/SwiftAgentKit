# Adapters Module: Standard Agent Adapters

The Adapters module provides pre-built implementations of the `AgentAdapter` protocol for popular AI providers, making it easy to create A2A-compliant servers that connect to external AI services.

## Overview

The `SwiftAgentKitAdapters` module includes adapters for:
- **OpenAI**: GPT-4, GPT-3.5, and other OpenAI models
- **Anthropic**: Claude models (Claude 3.5 Sonnet, Claude 3 Opus, etc.)
- **Google Gemini**: Gemini 1.5 Flash, Gemini 1.5 Pro, and other Gemini models

## Quick Start

```swift
import SwiftAgentKitA2A
import SwiftAgentKitAdapters

// Create an OpenAI adapter
let openAIAdapter = OpenAIAdapter(apiKey: "your-openai-api-key")

// Create an A2A server with the adapter
let server = A2AServer(port: 4245, adapter: openAIAdapter)

// Start the server
try await server.start()
```

## Available Adapters

### OpenAI Adapter

The `OpenAIAdapter` connects to OpenAI's API and supports GPT-4, GPT-3.5, and other OpenAI models.

```swift
import SwiftAgentKitAdapters

// Basic usage
let adapter = OpenAIAdapter(apiKey: "your-api-key")

// With custom configuration
let config = OpenAIAdapter.Configuration(
    apiKey: "your-api-key",
    model: "gpt-4o",
    maxTokens: 1000,
    temperature: 0.7
)
let adapter = OpenAIAdapter(configuration: config)
```

**Supported Models:**
- `gpt-4o` (default)
- `gpt-4o-mini`
- `gpt-4-turbo`
- `gpt-3.5-turbo`
- And other OpenAI models

**Skills:**
- Text Generation
- Code Generation
- Text Analysis

### Anthropic Adapter

The `AnthropicAdapter` connects to Anthropic's Claude API.

```swift
import SwiftAgentKitAdapters

// Basic usage
let adapter = AnthropicAdapter(apiKey: "your-api-key")

// With custom configuration
let config = AnthropicAdapter.Configuration(
    apiKey: "your-api-key",
    model: "claude-3-5-sonnet-20241022",
    maxTokens: 1000,
    temperature: 0.7
)
let adapter = AnthropicAdapter(configuration: config)
```

**Supported Models:**
- `claude-3-5-sonnet-20241022` (default)
- `claude-3-opus-20240229`
- `claude-3-sonnet-20240229`
- `claude-3-haiku-20240307`
- And other Claude models

**Skills:**
- Text Generation
- Code Generation
- Text Analysis
- Logical Reasoning

### Gemini Adapter

The `GeminiAdapter` connects to Google's Gemini API and supports multimodal inputs.

```swift
import SwiftAgentKitAdapters

// Basic usage
let adapter = GeminiAdapter(apiKey: "your-api-key")

// With custom configuration
let config = GeminiAdapter.Configuration(
    apiKey: "your-api-key",
    model: "gemini-1.5-flash",
    maxTokens: 1000,
    temperature: 0.7
)
let adapter = GeminiAdapter(configuration: config)
```

**Supported Models:**
- `gemini-1.5-flash` (default)
- `gemini-1.5-pro`
- `gemini-1.0-pro`
- And other Gemini models

**Skills:**
- Text Generation
- Code Generation
- Text Analysis
- Multimodal Processing (text + images)

## Configuration Options

All adapters support the following configuration options:

```swift
public struct Configuration {
    public let apiKey: String           // Required API key
    public let model: String            // Model name
    public let baseURL: URL             // API base URL
    public let maxTokens: Int?          // Maximum tokens in response
    public let temperature: Double?     // Response randomness (0.0-1.0)
}
```

## Creating Custom Adapters

You can create custom adapters by implementing the `AgentAdapter` protocol:

```swift
import SwiftAgentKitA2A
import SwiftAgentKitAdapters

struct MyCustomAdapter: AgentAdapter {
    var agentName: String {
        "My Custom Agent"
    }
    
    var agentDescription: String {
        "A custom A2A-compliant agent with custom skill implementation."
    }
    
    var cardCapabilities: AgentCard.AgentCapabilities {
        .init(
            streaming: true,
            pushNotifications: false,
            stateTransitionHistory: true
        )
    }
    
    var skills: [AgentCard.AgentSkill] {
        [
            .init(
                id: "custom-skill",
                name: "Custom Skill",
                description: "A custom skill implementation",
                tags: ["custom"],
                examples: ["Example usage"],
                inputModes: ["text/plain"],
                outputModes: ["text/plain"]
            )
        ]
    }
    
    var defaultInputModes: [String] { ["text/plain"] }
    var defaultOutputModes: [String] { ["text/plain"] }
    
    func handleSend(_ params: MessageSendParams, store: TaskStore) async throws -> A2ATask {
        // Implement your custom logic here
        // This could call external APIs, process data, etc.
    }
    
    func handleStream(_ params: MessageSendParams, store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws {
        // Implement streaming logic here
    }
}
```

## Multi-Provider Adapters

You can create adapters that combine multiple AI providers for redundancy or fallback:

```swift
struct MultiProviderAdapter: AgentAdapter {
    private let openAIAdapter: OpenAIAdapter
    private let anthropicAdapter: AnthropicAdapter
    
    init(openAIKey: String, anthropicKey: String) {
        self.openAIAdapter = OpenAIAdapter(apiKey: openAIKey)
        self.anthropicAdapter = AnthropicAdapter(apiKey: anthropicKey)
    }
    
    var agentName: String {
        "Multi-Provider Agent"
    }
    
    var agentDescription: String {
        "An A2A-compliant agent that provides redundancy and fallback using multiple AI providers."
    }
    
    var cardCapabilities: AgentCard.AgentCapabilities {
        .init(
            streaming: true,
            pushNotifications: false,
            stateTransitionHistory: true
        )
    }
    
    var skills: [AgentCard.AgentSkill] {
        [
            .init(
                id: "openai-skill",
                name: "OpenAI Skill",
                description: "Provides text generation and code generation capabilities from OpenAI.",
                tags: ["openai"],
                examples: ["Tell me about Swift."],
                inputModes: ["text/plain"],
                outputModes: ["text/plain"]
            ),
            .init(
                id: "anthropic-skill",
                name: "Anthropic Skill",
                description: "Provides text generation and code generation capabilities from Anthropic.",
                tags: ["anthropic"],
                examples: ["What is the capital of France?"],
                inputModes: ["text/plain"],
                outputModes: ["text/plain"]
            )
        ]
    }
    
    var defaultInputModes: [String] { ["text/plain"] }
    var defaultOutputModes: [String] { ["text/plain"] }
    
    func handleSend(_ params: MessageSendParams, store: TaskStore) async throws -> A2ATask {
        // Try OpenAI first, then Anthropic as fallback
        do {
            return try await openAIAdapter.handleSend(params, store: store)
        } catch {
            return try await anthropicAdapter.handleSend(params, store: store)
        }
    }
    
    func handleStream(_ params: MessageSendParams, store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws {
        // Implement streaming logic here
    }
}
```

## Error Handling

All adapters include proper error handling and will update task status appropriately:

- **Success**: Task status updated to `.completed`
- **Failure**: Task status updated to `.failed`
- **Streaming**: Real-time status updates and artifact creation

## Environment Variables

For production use, store API keys in environment variables:

```bash
export OPENAI_API_KEY="your-openai-key"
export ANTHROPIC_API_KEY="your-anthropic-key"
export GEMINI_API_KEY="your-gemini-key"
```

Then access them in your code:

```swift
let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
let anthropicKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
let geminiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
```

## Example: Complete Server Setup

```swift
import Foundation
import SwiftAgentKitA2A
import SwiftAgentKitAdapters

@main
struct MyA2AServer {
    static func main() async {
        // Get API keys from environment
        guard let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !openAIKey.isEmpty else {
            print("Error: OPENAI_API_KEY environment variable not set")
            return
        }
        
        // Create adapter
        let adapter = OpenAIAdapter(
            apiKey: openAIKey,
            model: "gpt-4o"
        )
        
        // Create and start server
        let server = A2AServer(port: 4245, adapter: adapter)
        
        do {
            try await server.start()
            print("A2A server started on port 4245")
        } catch {
            print("Failed to start server: \(error)")
        }
    }
}
```

## Testing

The adapters module includes comprehensive tests using the Swift Testing framework:

```bash
swift test --filter SwiftAgentKitAdaptersTests
```

## Dependencies

The `SwiftAgentKitAdapters` module depends on:
- `SwiftAgentKit` (core functionality)
- `SwiftAgentKitA2A` (A2A protocol support)
- `swift-log` (logging)

## Security Considerations

- Never hardcode API keys in your source code
- Use environment variables or secure key management systems
- Consider implementing rate limiting for production use
- Monitor API usage and costs
- Implement proper error handling and logging

## Troubleshooting

### Common Issues

1. **API Key Errors**: Ensure your API key is valid and has sufficient credits
2. **Model Not Found**: Verify the model name is correct for your API provider
3. **Rate Limiting**: Implement exponential backoff for retry logic
4. **Network Issues**: Check your internet connection and firewall settings

### Debug Logging

Enable debug logging to troubleshoot issues:

```swift
import Logging

LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardOutput(label: label)
    handler.logLevel = .debug
    return handler
}
```

## Contributing

To add new adapters:

1. Create a new adapter file in `Sources/SwiftAgentKitAdapters/`
2. Implement the `AgentAdapter` protocol
3. Add tests in `Tests/SwiftAgentKitAdaptersTests/`
4. Update documentation
5. Add the adapter to the module exports in `SwiftAgentKitAdapters.swift` 