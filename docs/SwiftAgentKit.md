# SwiftAgentKit Module: Core Networking and Utilities

The SwiftAgentKit module provides core networking capabilities and utilities that are shared across other modules. It includes a modular REST API manager with helper types for building requests, validating responses, and handling streaming connections.

> ℹ️ **Logging**  
> All library diagnostics now flow through the shared `SwiftAgentKitLogging` surface. Before issuing requests, bootstrap the logger you want SwiftAgentKit to use:
> ```swift
> import Logging
> import SwiftAgentKit
> 
> let appLogger = Logger(label: "com.example.app")
> SwiftAgentKitLogging.bootstrap(
>     logger: appLogger,
>     level: .info,
>     metadata: ["deployment": .string("staging")]
> )
> ```
> Once bootstrapped, every component (core, MCP, A2A, adapters, orchestrator) automatically derives scoped loggers with consistent metadata. The `print` calls in the snippets below represent **application output**; structured library logs are emitted via the logger you configure.

## Key Types

### Core Networking
- **RestAPIManager**: Main networking manager with modular architecture
- **RequestBuilder**: Constructs HTTP requests with proper headers and body formatting
- **ResponseValidator**: Validates HTTP responses and handles error cases
- **StreamClient**: Manages streaming HTTP connections with proper continuation handling
- **SSEClient**: Handles Server-Sent Events (SSE) connections

### Utilities
- **Shell**: Executes shell commands and manages subprocesses

## Example: Basic REST API Usage

```swift
import SwiftAgentKit

let apiManager = RestAPIManager()

// Simple GET request
let response = try await apiManager.get(
    url: "https://api.example.com/data",
    headers: ["Authorization": "Bearer token"]
)

print("Response: \(response)")
```

## Example: POST Request with JSON Body

```swift
let requestBody = ["name": "John", "age": 30]
let response = try await apiManager.post(
    url: "https://api.example.com/users",
    headers: ["Content-Type": "application/json"],
    body: requestBody
)

print("Created user: \(response)")
```

## Example: Streaming Response

```swift
let stream = apiManager.stream(
    url: "https://api.example.com/stream",
    headers: ["Authorization": "Bearer token"]
)

for try await chunk in stream {
    print("Received chunk: \(chunk)")
}
```

## Example: Server-Sent Events

```swift
let sseClient = SSEClient()
let events = sseClient.connect(
    url: "https://api.example.com/events",
    headers: ["Authorization": "Bearer token"]
)

for try await event in events {
    print("SSE Event: \(event.event) - \(event.data)")
}
```

## Example: Shell Command Execution

```swift
import SwiftAgentKit

let shell = Shell()

// Execute a simple command
let result = try await shell.execute("ls -la")
print("Output: \(result.output)")
print("Exit code: \(result.exitCode)")

// Execute with environment variables
let envResult = try await shell.execute(
    "echo $API_KEY",
    environment: ["API_KEY": "secret-value"]
)
print("Environment output: \(envResult.output)")
```

## Example: Using Individual Components

### RequestBuilder
```swift
let builder = RequestBuilder()
let request = try builder.buildRequest(
    method: "POST",
    url: "https://api.example.com/data",
    headers: ["Content-Type": "application/json"],
    body: ["key": "value"]
)

print("Built request: \(request)")
```

### ResponseValidator
```swift
let validator = ResponseValidator()
let response = HTTPURLResponse(
    url: URL(string: "https://api.example.com")!,
    statusCode: 200,
    httpVersion: nil,
    headerFields: nil
)!

let isValid = validator.validateResponse(response, data: "response data".data(using: .utf8))
print("Response valid: \(isValid)")
```

### StreamClient
```swift
let streamClient = StreamClient()
let stream = streamClient.createStream(
    url: "https://api.example.com/stream",
    headers: ["Authorization": "Bearer token"]
)

for try await chunk in stream {
    print("Stream chunk: \(chunk)")
}
```

## Logging

SwiftAgentKit uses the unified logging surface described in [`docs/logging-api-design.md`](logging-api-design.md). Retrieve a scoped logger whenever you need additional metadata:

```swift
let networkingLogger = SwiftAgentKitLogging.logger(
    for: .networking("RestAPIManager"),
    metadata: SwiftAgentKitLogging.metadata(("requestId", .string(uuid.uuidString)))
)
networkingLogger.debug("Issuing GET request")
```

You can raise or lower verbosity at runtime with `SwiftAgentKitLogging.setLevel(_:)`. Call `SwiftAgentKitLogging.level()` to inspect the current setting.

## Architecture

The SwiftAgentKit module is designed with a modular architecture:

1. **RestAPIManager**: Orchestrates the other components
2. **RequestBuilder**: Handles request construction and formatting
3. **ResponseValidator**: Validates responses and handles errors
4. **StreamClient**: Manages streaming connections with proper continuation handling
5. **SSEClient**: Specialized client for Server-Sent Events

This modular design allows for:
- Easy testing of individual components
- Custom implementations of specific functionality
- Better separation of concerns
- Improved maintainability

## Related Modules

For higher-level orchestration capabilities, see:
- **SwiftAgentKitOrchestrator**: LLM orchestrator with MCP and A2A support
- **SwiftAgentKitMCP**: Model Context Protocol support
- **SwiftAgentKitA2A**: Agent-to-Agent communication
- **SwiftAgentKitAdapters**: AI provider adapters and tool-aware architecture 