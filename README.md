# SwiftAgentKit

A comprehensive toolkit for building local AI agents in Swift with optional sub-packages for different functionality.

## Overview

SwiftAgentKit is designed as a modular package that allows you to choose which components you need for your AI agent project. The package includes:

- **Core Module** (`SwiftAgentKit`) - Basic functionality and logging
- **A2A Module** (`SwiftAgentKitA2A`) - Agent-to-Agent communication
- **MCP Module** (`SwiftAgentKitMCP`) - Model Context Protocol support
- **Intercom Module** (`SwiftAgentKitIntercom`) - Inter-agent communication

## Installation

### Swift Package Manager

Add SwiftAgentKit to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/JamieScanlon/SwiftAgentKit.git", from: "1.0.0")
]
```

## Usage

### Basic Setup

Import only the core module for basic functionality:

```swift
import SwiftAgentKit

let config = SwiftAgentKitConfig(
    enableLogging: true,
    logLevel: .info
)

let manager = SwiftAgentKitManager(config: config)
let core = manager.getCore()
core.log("SwiftAgentKit initialized!")
```

### Using Optional Modules

#### A2A (Agent-to-Agent) Module

```swift
import SwiftAgentKit
import SwiftAgentKitA2A

let config = SwiftAgentKitConfig(
    enableLogging: true,
    enableA2A: true
)

let manager = SwiftAgentKitManager(config: config)
// A2A functionality is now available
```

#### MCP (Model Context Protocol) Module

```swift
import SwiftAgentKit
import SwiftAgentKitMCP

let config = SwiftAgentKitConfig(
    enableLogging: true,
    enableMCP: true
)

let manager = SwiftAgentKitManager(config: config)
// MCP functionality is now available
```

#### Intercom Module

```swift
import SwiftAgentKit
import SwiftAgentKitIntercom

let config = SwiftAgentKitConfig(
    enableLogging: true,
    enableIntercom: true
)

let manager = SwiftAgentKitManager(config: config)
// Intercom functionality is now available
```

### Using Multiple Modules

You can enable multiple modules at once:

```swift
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitMCP
import SwiftAgentKitIntercom

let config = SwiftAgentKitConfig(
    enableLogging: true,
    logLevel: .debug,
    enableA2A: true,
    enableMCP: true,
    enableIntercom: true
)

let manager = SwiftAgentKitManager(config: config)
// All modules are now available
```

---

## Networking Module

SwiftAgentKit provides a modular networking layer for making HTTP requests, handling streaming responses, and working with Server-Sent Events (SSE). The networking code is organized under `Sources/SwiftAgentKit/Networking/` and is composed of the following main classes:

- **RestAPIManager**: High-level interface for making requests, streaming, and SSE.
- **RequestBuilder**: Constructs URLRequests from endpoints, parameters, and headers.
- **ResponseValidator**: Validates HTTP responses and decodes data.
- **StreamClient**: Handles streaming HTTP responses using Swift concurrency.
- **SSEClient**: Handles Server-Sent Events (SSE) connections and event parsing.

### Example: Basic Request

```swift
import SwiftAgentKit
// If needed: import SwiftAgentKit.Networking

let manager = RestAPIManager(baseURL: URL(string: "https://api.example.com")!)

Task {
    do {
        let result: MyDecodableType = try await manager.request(
            endpoint: "/data",
            method: .get,
            parameters: ["foo": "bar"],
            headers: ["Authorization": "Bearer ..."]
        )
        print(result)
    } catch {
        print("Request failed: \(error)")
    }
}
```

### Example: Streaming Response

```swift
Task {
    do {
        for try await chunk in manager.stream(
            endpoint: "/stream",
            method: .get,
            parameters: nil,
            headers: nil
        ) {
            print("Received chunk: \(chunk)")
        }
    } catch {
        print("Streaming failed: \(error)")
    }
}
```

### Example: Server-Sent Events (SSE)

```swift
Task {
    do {
        for try await event in manager.sse(
            endpoint: "/sse",
            parameters: nil,
            headers: nil
        ) {
            print("Received SSE event: \(event)")
        }
    } catch {
        print("SSE failed: \(error)")
    }
}
```

### Customizing Requests

You can use `RequestBuilder` and `ResponseValidator` directly for advanced scenarios:

```swift
let builder = RequestBuilder(baseURL: URL(string: "https://api.example.com")!)
let validator = ResponseValidator()

let request = try builder.buildRequest(
    endpoint: "/custom",
    method: .post,
    parameters: ["foo": "bar"],
    headers: nil
)

let (data, response) = try await URLSession.shared.data(for: request)
let decoded: MyDecodableType = try validator.validateAndDecode(data: data, response: response)
```

---

## Package Structure

```
SwiftAgentKit/
├── Sources/
│   ├── SwiftAgentKit/           # Core functionality
│   ├── SwiftAgentKitA2A/        # Agent-to-Agent communication
│   ├── SwiftAgentKitMCP/        # Model Context Protocol
│   └── SwiftAgentKitIntercom/   # Inter-agent communication
├── Tests/
│   ├── SwiftAgentKitTests/
│   ├── SwiftAgentKitA2ATests/
│   ├── SwiftAgentKitMCPTests/
│   └── SwiftAgentKitIntercomTests/
└── Package.swift
```

## Dependencies

- **Core**: No external dependencies
- **A2A**: Vapor, EasyJSON
- **MCP**: SwiftNIO
- **Intercom**: Vapor, SwiftNIO

## Requirements

- macOS 13.0+
- iOS 16.0+
- visionOS 1.0+
- Swift 6.0+

## License

[Add your license information here]

## Contributing

[Add contribution guidelines here]
