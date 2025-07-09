# SwiftAgentKit

A Swift framework for building AI agents with support for Model Context Protocol (MCP) and Agent-to-Agent (A2A) communication.

## Overview

SwiftAgentKit provides a modular foundation for building AI agents that can:
- Connect to MCP-compliant model servers and tools
- Communicate with other A2A-compliant agents
- Make HTTP requests and handle streaming responses
- Execute shell commands and manage subprocesses
- Use structured logging throughout

The framework is designed with a simple, direct API - no unnecessary abstractions or configuration objects.

## Modules

| Module | Description | Documentation |
|--------|-------------|---------------|
| **SwiftAgentKitFoundation** | Core networking and utilities | [Foundation.md](docs/Foundation.md) |
| **SwiftAgentKitMCP** | Model Context Protocol support | [MCP.md](docs/MCP.md) |
| **SwiftAgentKitA2A** | Agent-to-Agent communication | [A2A.md](docs/A2A.md) |

## Quick Start

### Installation

Add SwiftAgentKit to your project:

```swift
dependencies: [
    .package(url: "https://github.com/JamieScanlon/SwiftAgentKit.git", from: "0.1.3")
]
```

### Importing Modules

Add the products you want to use to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "SwiftAgentKitFoundation", package: "SwiftAgentKit"),
        .product(name: "SwiftAgentKitA2A", package: "SwiftAgentKit"),  // Optional
        .product(name: "SwiftAgentKitMCP", package: "SwiftAgentKit"),  // Optional
    ]
)
```

### Basic Usage

```swift
import SwiftAgentKitFoundation
import SwiftAgentKitMCP
import SwiftAgentKitA2A
import Logging

// Create loggers directly
let logger = Logger(label: "MyApp")

// Use the modules as needed
let apiManager = RestAPIManager()
let mcpManager = MCPManager()
let a2aManager = A2AManager()

logger.info("SwiftAgentKit initialized")
```

## Examples

Run the examples to see SwiftAgentKit in action:

```bash
# Basic networking example
swift run BasicExample

# MCP client example
swift run MCPExample

# A2A client example
swift run A2AExample
```

## Documentation

For detailed documentation on each module, see:
- [Foundation Module](docs/Foundation.md) - Core networking and utilities
- [MCP Module](docs/MCP.md) - Model Context Protocol support
- [A2A Module](docs/A2A.md) - Agent-to-Agent communication

## Logging

All modules use Swift Logging for structured logging. View logs with:

```bash
log stream --predicate 'subsystem == "com.swiftagentkit"' --style compact
```

## Requirements

- macOS 13.0+
- Swift 5.9+

## License

MIT License - see [LICENSE](LICENSE) file for details.
