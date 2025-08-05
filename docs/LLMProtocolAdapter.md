# LLMProtocolAdapter

The `LLMProtocolAdapter` is a generic adapter that wraps any `LLMProtocol` implementation and makes it compatible with the A2A (Agent-to-Agent) protocol. This adapter provides a bridge between the SwiftAgentKit's LLM interface and the A2A server infrastructure.

## Overview

The `LLMProtocolAdapter` allows you to:
- Wrap any LLM that implements the `LLMProtocol` interface
- Use that LLM with A2A servers and clients
- Maintain conversation history and context
- Support both synchronous and streaming responses
- Configure LLM parameters like temperature, max tokens, etc.

## Key Features

- **Generic Design**: Works with any LLM that implements `LLMProtocol`
- **A2A Compatibility**: Full integration with the A2A protocol
- **Conversation History**: Maintains context across multiple messages
- **Streaming Support**: Real-time streaming responses
- **Configurable**: Customizable parameters and system prompts
- **Error Handling**: Graceful error handling and recovery

## Basic Usage

### Creating an LLMProtocolAdapter

```swift
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitAdapters

// Create your LLM implementation
let myLLM = MyCustomLLM(model: "my-model")

// Create the adapter
let adapter = LLMProtocolAdapter(
    llm: myLLM,
    model: "my-model",
    maxTokens: 1000,
    temperature: 0.7,
    systemPrompt: "You are a helpful assistant."
)

// Use with A2A server
let server = A2AServer(port: 4245, adapter: adapter)
try await server.start()
```

### Configuration Options

The `LLMProtocolAdapter.Configuration` struct supports the following parameters:

```swift
public struct Configuration: Sendable {
    public let model: String                    // Model identifier
    public let maxTokens: Int?                  // Maximum tokens to generate
    public let temperature: Double?             // Response randomness (0.0-2.0)
    public let topP: Double?                    // Top-p sampling parameter
    public let systemPrompt: String?            // System prompt for the LLM
    public let additionalParameters: JSON?      // Model-specific parameters
}
```

### Convenience Initializer

For simpler use cases, you can use the convenience initializer:

```swift
let adapter = LLMProtocolAdapter(
    llm: myLLM,
    model: "my-model",
    maxTokens: 1000,
    temperature: 0.7,
    systemPrompt: "You are a helpful assistant."
)
```

## Advanced Usage

### Custom LLM Implementation

To use the `LLMProtocolAdapter`, your LLM must implement the `LLMProtocol` interface:

```swift
struct MyCustomLLM: LLMProtocol {
    let model: String
    let logger: Logger
    
    init(model: String) {
        self.model = model
        self.logger = Logger(label: "MyCustomLLM")
    }
    
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        // Your LLM implementation here
        let response = "Response from my custom LLM"
        return LLMResponse(content: response)
    }
    
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<LLMResponse, Error> {
        // Your streaming implementation here
        return AsyncThrowingStream { continuation in
            // Stream implementation
        }
    }
}
```

### Using with Tool-Aware Architecture

The `LLMProtocolAdapter` can be combined with the tool-aware architecture:

```swift
// Create base adapter
let baseAdapter = LLMProtocolAdapter(llm: myLLM)

// Create tool-aware adapter
let toolAwareAdapter = ToolAwareAdapter(
    baseAdapter: baseAdapter,
    toolManager: toolManager
)

// Use with A2A server
let server = A2AServer(port: 4245, adapter: toolAwareAdapter)
```

### Conversation History

The adapter automatically maintains conversation history:

```swift
// First message
let message1 = A2AMessage(
    role: "user",
    parts: [.text(text: "My name is Alice")],
    messageId: UUID().uuidString
)

// Second message (includes context from first)
let message2 = A2AMessage(
    role: "user",
    parts: [.text(text: "What's my name?")],
    messageId: UUID().uuidString
)

// The LLM will have context from the previous message
```

## Example: Complete Implementation

Here's a complete example showing how to create and use an `LLMProtocolAdapter`:

```swift
import Foundation
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitAdapters
import Logging

// Custom LLM implementation
struct ExampleLLM: LLMProtocol {
    let model: String
    let logger: Logger
    
    init(model: String = "example-llm") {
        self.model = model
        self.logger = Logger(label: "ExampleLLM")
    }
    
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        let lastUserMessage = messages.last { $0.role == .user }?.content ?? "Hello"
        let response = "Response to: '\(lastUserMessage)'"
        
        return LLMResponse(
            content: response,
            metadata: LLMMetadata(
                promptTokens: 10,
                completionTokens: response.count / 4,
                totalTokens: 10 + (response.count / 4),
                finishReason: "stop"
            )
        )
    }
    
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<LLMResponse, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                let response = try await send(messages, config: config)
                let words = response.content.components(separatedBy: " ")
                
                for (index, word) in words.enumerated() {
                    let isComplete = index == words.count - 1
                    let chunk = LLMResponse(
                        content: word + (isComplete ? "" : " "),
                        isComplete: isComplete
                    )
                    continuation.yield(chunk)
                    
                    if !isComplete {
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
                continuation.finish()
            }
        }
    }
}

// Main application
@main
struct ExampleApp {
    static func main() async throws {
        // Set up logging
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .info
            return handler
        }
        
        // Create LLM and adapter
        let exampleLLM = ExampleLLM(model: "example-llm-v1")
        let adapter = LLMProtocolAdapter(
            llm: exampleLLM,
            model: "example-llm-v1",
            maxTokens: 1000,
            temperature: 0.7,
            systemPrompt: "You are a helpful assistant."
        )
        
        // Create and start A2A server
        let server = A2AServer(port: 4245, adapter: adapter)
        try await server.start()
        
        print("Server running on http://localhost:4245")
        
        // Keep server running
        try await Task.sleep(nanoseconds: UInt64.max)
    }
}
```

## Integration with Existing Adapters

The `LLMProtocolAdapter` complements the existing adapters in SwiftAgentKitAdapters:

- **OpenAIAdapter**: For OpenAI GPT models
- **AnthropicAdapter**: For Anthropic Claude models  
- **GeminiAdapter**: For Google Gemini models
- **LLMProtocolAdapter**: For any custom LLM implementation

This allows you to use the same A2A infrastructure with both commercial LLM providers and your own custom implementations.

## Error Handling

The adapter includes comprehensive error handling:

- **LLM Errors**: Errors from the underlying LLM are properly propagated
- **A2A Protocol Errors**: Protocol-specific errors are handled gracefully
- **Network Errors**: Network-related issues are caught and reported
- **Task State Management**: Failed tasks are properly marked in the A2A task store

## Performance Considerations

- **Memory Usage**: The adapter maintains conversation history in memory
- **Streaming**: Real-time streaming with minimal latency
- **Concurrency**: Fully async/await compatible
- **Resource Management**: Proper cleanup of resources

## Best Practices

1. **Model Selection**: Choose appropriate model parameters for your use case
2. **System Prompts**: Use clear, specific system prompts to guide LLM behavior
3. **Error Handling**: Always handle potential errors from the LLM
4. **Resource Cleanup**: Ensure proper cleanup when shutting down servers
5. **Monitoring**: Monitor token usage and response times
6. **Testing**: Test with various input types and conversation lengths

## Troubleshooting

### Common Issues

1. **Compilation Errors**: Ensure your LLM implements all required `LLMProtocol` methods
2. **Runtime Errors**: Check that your LLM handles edge cases properly
3. **Performance Issues**: Monitor token usage and consider caching strategies
4. **Memory Leaks**: Ensure proper cleanup of streaming resources

### Debugging

Enable debug logging to troubleshoot issues:

```swift
LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardOutput(label: label)
    handler.logLevel = .debug  // Set to debug level
    return handler
}
```

## API Reference

### LLMProtocolAdapter

```swift
public struct LLMProtocolAdapter: AgentAdapter {
    public init(llm: LLMProtocol, configuration: Configuration)
    public init(llm: LLMProtocol, model: String?, maxTokens: Int?, temperature: Double?, topP: Double?, systemPrompt: String?, additionalParameters: JSON?)
    
    public var cardCapabilities: AgentCard.AgentCapabilities
    public var skills: [AgentCard.AgentSkill]
    public var defaultInputModes: [String]
    public var defaultOutputModes: [String]
    
    public func handleSend(_ params: MessageSendParams, store: TaskStore) async throws -> A2ATask
    public func handleStream(_ params: MessageSendParams, store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws
}
```

### Configuration

```swift
public struct Configuration: Sendable {
    public let model: String
    public let maxTokens: Int?
    public let temperature: Double?
    public let topP: Double?
    public let systemPrompt: String?
    public let additionalParameters: JSON?
    
    public init(model: String, maxTokens: Int?, temperature: Double?, topP: Double?, systemPrompt: String?, additionalParameters: JSON?)
}
``` 