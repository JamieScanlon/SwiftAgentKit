# LLMProtocolAdapter

The `LLMProtocolAdapter` is a generic adapter that wraps any `LLMProtocol` implementation and makes it compatible with the A2A (Agent-to-Agent) protocol. This adapter provides a bridge between the SwiftAgentKit's LLM interface and the A2A server infrastructure.

> ℹ️ **Logging tip**  
> The adapter now emits detailed debug information (agentic iterations, tool execution, streaming progress) through `SwiftAgentKitLogging`. Bootstrap once prior to creating the adapter:
> ```swift
> import Logging
> import SwiftAgentKit
> 
> SwiftAgentKitLogging.bootstrap(
>     logger: Logger(label: "com.example.llm"),
>     level: .info
> )
> ```
> Any `print` statements in this guide are for illustrative CLI feedback; the adapter itself relies on the logger you configure.

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
- **Image Generation**: Automatic detection and support for image generation requests
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

// Create the adapter with DynamicPrompt
var prompt = DynamicPrompt(template: "You are a helpful assistant.")
let adapter = LLMProtocolAdapter(
    llm: myLLM,
    model: "my-model",
    maxTokens: 1000,
    temperature: 0.7,
    systemPrompt: prompt
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
    public let systemPrompt: DynamicPrompt?     // System prompt for the LLM (supports token replacement)
    public let additionalParameters: JSON?      // Model-specific parameters
}
```

### Convenience Initializer

For simpler use cases, you can use the convenience initializer:

```swift
var prompt = DynamicPrompt(template: "You are a helpful assistant.")
let adapter = LLMProtocolAdapter(
    llm: myLLM,
    model: "my-model",
    maxTokens: 1000,
    temperature: 0.7,
    systemPrompt: prompt
)
```

### Dynamic Prompts with Tokens

You can use `DynamicPrompt` to create system prompts with replaceable tokens:

```swift
var prompt = DynamicPrompt(template: "You are {{role}} assistant. Your expertise is in {{domain}}.")
prompt["role"] = "helpful"
prompt["domain"] = "software development"

let adapter = LLMProtocolAdapter(
    llm: myLLM,
    model: "my-model",
    systemPrompt: prompt
)

// The prompt will be rendered as: "You are helpful assistant. Your expertise is in software development."
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
    
    func getModelName() -> String {
        return model
    }
    
    func getCapabilities() -> [LLMCapability] {
        return [.completion, .tools, .imageGeneration]  // Include .imageGeneration if supported
    }
    
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        // Your LLM implementation here
        let response = "Response from my custom LLM"
        return LLMResponse(content: response)
    }
    
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        // Your streaming implementation here
        return AsyncThrowingStream { continuation in
            // Stream implementation
        }
    }
    
    // Optional: Implement image generation if your LLM supports it
    func generateImage(_ config: ImageGenerationRequestConfig) async throws -> ImageGenerationResponse {
        // Your image generation implementation here
        // Return ImageGenerationResponse with URLs to generated images
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
    
    func getModelName() -> String {
        return model
    }
    
    func getCapabilities() -> [LLMCapability] {
        return [.completion, .tools]
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
        var prompt = DynamicPrompt(template: "You are a helpful assistant.")
        let adapter = LLMProtocolAdapter(
            llm: exampleLLM,
            model: "example-llm-v1",
            maxTokens: 1000,
            temperature: 0.7,
            systemPrompt: prompt
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

## Image Generation Support

The `LLMProtocolAdapter` automatically detects and handles image generation requests when:

1. **LLM supports image generation**: The LLM's `getCapabilities()` includes `.imageGeneration`
2. **Client accepts image output**: The request's `acceptedOutputModes` includes image MIME types (e.g., `"image/png"`, `"image/jpeg"`, `"image/*"`)
3. **Message contains a prompt**: The message has text content to use as the image generation prompt

### How It Works

The adapter uses A2A-compliant detection by checking the `acceptedOutputModes` field in `MessageSendConfiguration`. This means any standard A2A client can request image generation by simply specifying image output modes.

### Example: Client Requesting Image Generation

```swift
// Client sends a request accepting image output
let config = MessageSendConfiguration(
    acceptedOutputModes: ["image/png", "text/plain"]  // Client accepts images
)

let params = MessageSendParams(
    message: A2AMessage(
        role: "user",
        parts: [.text(text: "Generate a beautiful sunset over mountains")],
        messageId: UUID().uuidString
    ),
    configuration: config
)

// Optional: Pass additional parameters via metadata
let paramsWithOptions = MessageSendParams(
    message: message,
    configuration: config,
    metadata: try JSON([
        "n": 2,           // Generate 2 images
        "size": "512x512" // Image size
    ])
)
```

### Image Generation Response

When image generation is detected and the LLM supports it:

- The adapter calls `llm.generateImage(config)` instead of `llm.send()`
- Generated images are returned as **artifacts** with `A2AMessagePart.file` parts
- Each image URL is wrapped in a separate artifact
- Artifacts include MIME type metadata and creation timestamps

### Fallback Behavior

If the client requests images but the LLM doesn't support image generation:
- The adapter gracefully falls back to text generation
- No error is thrown - the request is handled as a normal text request
- This ensures compatibility with LLMs that don't support image generation

### Implementing Image Generation in Your LLM

To add image generation support to your custom LLM:

```swift
struct MyImageGeneratingLLM: LLMProtocol {
    // ... other methods ...
    
    func getCapabilities() -> [LLMCapability] {
        return [.completion, .tools, .imageGeneration]  // Add .imageGeneration
    }
    
    func generateImage(_ config: ImageGenerationRequestConfig) async throws -> ImageGenerationResponse {
        // Your image generation logic here
        // Generate images based on config.prompt, config.image, etc.
        
        // Save generated images to filesystem and return URLs
        let imageURLs = try await generateImagesAndSaveToDisk(config)
        
        return ImageGenerationResponse(
            images: imageURLs,
            createdAt: Date(),
            metadata: LLMMetadata(totalTokens: 100)
        )
    }
}
```

## Integration with Existing Adapters

The `LLMProtocolAdapter` complements the existing adapters in SwiftAgentKitAdapters:

- **OpenAIAdapter**: For OpenAI GPT models (also supports DALL-E image generation)
- **AnthropicAdapter**: For Anthropic Claude models  
- **GeminiAdapter**: For Google Gemini models
- **LLMProtocolAdapter**: For any custom LLM implementation

This allows you to use the same A2A infrastructure with both commercial LLM providers and your own custom implementations.

### Image Generation Across Adapters

Both `LLMProtocolAdapter` and `OpenAIAdapter` support image generation using the same A2A-compliant detection mechanism:

- **LLMProtocolAdapter**: Automatically supports image generation if the wrapped LLM implements `generateImage()`
- **OpenAIAdapter**: Directly supports DALL-E image generation via OpenAI's API

Both adapters use the same detection logic (checking `acceptedOutputModes`) and return images as file-based artifacts, ensuring a consistent experience across different LLM providers.

### Error Handling for Image Generation

The adapter provides comprehensive error handling for image generation:

- **Invalid Parameters**: Invalid `n` (not 1-10) or `size` values are automatically clamped to valid ranges with warnings logged
- **Prompt Length**: Prompts exceeding 1000 characters log warnings (LLM may truncate)
- **LLM Errors**: Errors from the underlying LLM's `generateImage()` method are properly propagated
- **No Images Generated**: If LLM returns no images, throws `LLMError.imageGenerationError(.noImagesGenerated)`

### File Storage and Cleanup

Generated images are saved to filesystem URLs returned by the LLM's `generateImage()` method. The adapter:

- Creates artifacts with file URLs pointing to the generated images
- Relies on the LLM implementation to manage file storage and cleanup
- Does not automatically delete generated images (LLM implementation responsibility)

For production use, ensure your LLM implementation handles file cleanup appropriately.

### Tool-Aware Compatibility

Image generation requests bypass tool handling - they are direct operations that don't require tool execution. When using `ToolAwareAdapter`:

- Image generation requests are detected and handled before tool processing
- Tools are not available during image generation (by design)
- This ensures image generation is fast and direct without agentic loops

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
    public init(llm: LLMProtocol, model: String?, maxTokens: Int?, temperature: Double?, topP: Double?, systemPrompt: DynamicPrompt?, additionalParameters: JSON?)
    
    public var agentName: String
    public var agentDescription: String
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
    public let systemPrompt: DynamicPrompt?
    public let additionalParameters: JSON?
    
    public init(model: String, maxTokens: Int?, temperature: Double?, topP: Double?, systemPrompt: DynamicPrompt?, additionalParameters: JSON?)
}
``` 