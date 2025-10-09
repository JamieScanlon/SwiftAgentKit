# SwiftAgentKitMCP - MCP Server Implementation

This module provides tools for building MCP (Model Context Protocol) servers in Swift. It includes a complete server implementation that handles JSON-RPC messages, tool registration, and MCP protocol management.

## Features

- **MCPServer**: Main server class that handles JSON-RPC parsing and routing
- **MCPClient**: Client for connecting to MCP servers with built-in message filtering
- **ToolRegistry**: Server-side tool management and execution
- **MessageFilter**: Utility for filtering log messages from MCP protocol communication

- **Automatic MCP Protocol Handling**: Built-in support for MCP methods (initialize, tools/list, tools/call)
- **Message Filtering**: Prevents log interference by filtering non-JSON-RPC messages
- **Environment Variable Access**: Built-in access to environment variables for custom authentication
- **Comprehensive Error Handling**: Standard JSON-RPC error codes with extensible custom errors

## Quick Start

### Basic MCP Server

```swift
import SwiftAgentKitMCP

// Create an MCP server with default stdio transport
let server = MCPServer(name: "my-tool-server", version: "1.0.0")

// Register tools
await server.registerTool(
    name: "hello_world",
    description: "A simple greeting tool",
    inputSchema: [
        "type": "object",
        "properties": "{\"name\": {\"type\": \"string\", \"description\": \"Name to greet\"}}",
        "required": "[\"name\"]"
    ]
        ) { args in
            let name: String
            if case .string(let value) = args["name"] {
                name = value
            } else {
                name = "World"
            }
            return .success("Hello, \(name)!")
        }

// Start the server
try await server.start()

// Keep the server running
try await Task.sleep(nanoseconds: UInt64.max)
```

### Transport Configuration

The MCPServer supports different transport types for various deployment scenarios:

#### Stdio Transport (Default)
```swift
// Default stdio transport - most common for MCP servers
let server = MCPServer(name: "my-tool-server", version: "1.0.0")
// or explicitly:
let server = MCPServer(name: "my-tool-server", version: "1.0.0", transportType: .stdio)
```

#### Chunked Stdio Transport (Recommended for Large Messages)
```swift
// Chunked stdio transport - handles messages larger than 64KB
// Recommended for servers that may send/receive large data
let server = MCPServer(
    name: "my-tool-server",
    version: "1.0.0",
    transportType: .chunkedStdio
)
```

**When to use chunked stdio:**
- ✅ Messages may exceed 64KB (macOS pipe buffer limit)
- ✅ Transferring large tool results or file contents
- ✅ Working with large datasets
- ✅ Need transparent handling of large messages

See [MessageChunking.md](../../docs/MessageChunking.md) for detailed documentation.

#### HTTP Client Transport
```swift
// HTTP client transport for connecting to remote MCP servers
let server = MCPServer(
    name: "http-client-server",
    version: "1.0.0",
    transportType: .httpClient(
        endpoint: URL(string: "http://localhost:8080")!,
        streaming: true,
        sseInitializationTimeout: 10
    )
)
```

#### Network Transport
```swift
import Network

// Network transport for TCP/UDP connections
let connection = NWConnection(
    host: NWEndpoint.Host("localhost"),
    port: NWEndpoint.Port(8080)!,
    using: .tcp
)
let server = MCPServer(
    name: "network-server",
    version: "1.0.0",
    transportType: .network(connection: connection)
)
```

### Tool Registration

Tools are registered with a name, description, input schema, and handler closure:

```swift
await server.registerTool(
    name: "calculate",
    description: "Perform mathematical calculations",
    inputSchema: [
        "type": "object",
        "properties": "{\"operation\": {\"type\": \"string\", \"description\": \"Math operation\"}, \"values\": {\"type\": \"array\", \"description\": \"Values to operate on\"}}",
        "required": "[\"operation\", \"values\"]"
    ]
        ) { args in
            let operation: String
            let values: [Double]
            
            if case .string(let value) = args["operation"] {
                operation = value
            } else {
                operation = "add"
            }
            
            if case .array(let array) = args["values"] {
                values = array.compactMap { value in
                    if case .double(let double) = value {
                        return double
                    } else if case .int(let int) = value {
                        return Double(int)
                    }
                    return nil
                }
            } else {
                values = [0, 0]
            }
            
            let result: Double
            switch operation {
            case "add":
                result = values.reduce(0, +)
            case "multiply":
                result = values.reduce(1, *)
            default:
                return .error("INVALID_OPERATION", "Unknown operation: \(operation)")
            }
            
            return .success("Result: \(result)")
        }
```

### Input Schema Format

The `inputSchema` parameter uses a simplified JSON schema format where complex objects are represented as JSON strings:

```swift
inputSchema: [
    "type": "object",
    "properties": "{\"param1\": {\"type\": \"string\"}, \"param2\": {\"type\": \"number\"}}",
    "required": "[\"param1\"]"
]
```

### Tool Results

Tools return `MCPToolResult` which can be either:

```swift
.success("Operation completed successfully")
.error("ERROR_CODE", "Error message")
```

### Tool Arguments

Tool handlers receive arguments as `[String: SendableValue]` where `SendableValue` is a type-safe, Sendable enum:

```swift
public enum SendableValue: Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(Data)
    case array([SendableValue])
    case object([String: SendableValue])
}
```

This ensures thread safety and eliminates the need for type casting:

```swift
await server.registerTool(
    name: "process_data",
    description: "Process data with type safety",
    inputSchema: [
        "type": "object",
        "properties": "{\"text\": {\"type\": \"string\"}, \"count\": {\"type\": \"number\"}}",
        "required": "[\"text\", \"count\"]"
    ]
) { args in
    // Type-safe argument extraction
    let text: String
    let count: Int
    
    if case .string(let value) = args["text"] {
        text = value
    } else {
        return .error("INVALID_TEXT", "Text must be a string")
    }
    
    if case .int(let value) = args["count"] {
        count = value
    } else if case .double(let value) = args["count"] {
        count = Int(value)
    } else {
        return .error("INVALID_COUNT", "Count must be a number")
    }
    
    return .success("Processed '\(text)' \(count) times")
}
```

### Environment Variables

Access environment variables for custom authentication or configuration:

```swift
let env = server.environmentVariables
let apiKey = env["API_KEY"]
let model = env["MODEL_NAME"]
```

## Server Lifecycle

### Starting the Server

```swift
try await server.start()
```

The server will:
1. Initialize the transport layer (stdio)
2. Start listening for incoming JSON-RPC messages
3. Handle MCP protocol methods automatically

### Stopping the Server

```swift
await server.stop()
```

## MCP Protocol Support

The server automatically handles these MCP methods:

- **`initialize`**: Returns server capabilities and information
- **`tools/list`**: Returns list of registered tools
- **`tools/call`**: Executes a registered tool

### Capabilities

Server capabilities are automatically determined based on registered components:
- **Tools**: Available when tools are registered
- **Prompts**: Available when prompts are registered (future)
- **Resources**: Available when resources are registered (future)

## Error Handling

The server provides standard JSON-RPC error codes:

- `-32700`: Parse error
- `-32600`: Invalid request
- `-32601`: Method not found
- `-32602`: Invalid params
- `-32603`: Internal error
- `-32000`: Custom errors

Custom error codes can be used for application-specific errors:

```swift
return .error("AUTH_FAILED", "Invalid credentials")
return .error("RATE_LIMITED", "Too many requests")
```

## Message Filtering

The MCPClient includes built-in message filtering to prevent log interference issues. Many MCP servers output log messages to stdout, which can interfere with JSON-RPC protocol communication.

### Problem

MCP servers use stdio for protocol communication, but many also output log messages (info, warnings, debug) to stdout. The MCPClient receives these log messages and tries to parse them as JSON-RPC protocol messages, causing "[MCP] Unexpected message received by client" warnings.

### Solution

The MCPClient automatically filters incoming messages to only process valid JSON-RPC protocol messages:

```swift
// Create client with default message filtering (enabled)
let client = MCPClient(
    name: "my-client",
    version: "1.0.0",
    messageFilterConfig: .default
)

// Create client with verbose logging of filtered messages
let verboseClient = MCPClient(
    name: "my-client",
    version: "1.0.0",
    messageFilterConfig: .verbose
)

// Create client with filtering disabled
let unfilteredClient = MCPClient(
    name: "my-client",
    version: "1.0.0",
    messageFilterConfig: .disabled
)
```

### Message Filter Configuration

```swift
let config = MessageFilter.Configuration(
    enabled: true,                    // Enable/disable filtering
    logFilteredMessages: false,      // Log filtered messages for debugging
    filteredMessageLogLevel: .debug  // Log level for filtered messages
)
```

### Benefits

- ✅ Solves log interference at the protocol level
- ✅ Works with any MCP server regardless of logging behavior
- ✅ No need to modify server configurations
- ✅ More robust and maintainable solution
- ✅ Filters out common log patterns automatically

## Transport

### Stdio Transport

The server supports stdio transport for easy integration with MCP clients. The server reads from stdin and writes to stdout, making it compatible with standard MCP client implementations.

### Message Chunking for Large Data

On macOS, pipe buffers have a 64KB limit. For applications that need to send or receive large messages (> 64KB), SwiftAgentKit provides transparent message chunking:

**Problem:**
- macOS pipe buffer limit: 64KB
- Large JSON-RPC messages fail with `EPIPE` or `EAGAIN`
- Tool responses with large data can't be transmitted

**Solution:**
- Use `transportType: .chunkedStdio` for the server
- Client-side `ClientTransport` automatically supports chunking
- Messages are transparently split into ~60KB frames
- Frames are reassembled on the receiving end

**How it works:**
1. Messages > 60KB are automatically chunked
2. Each chunk has a header: `messageId:chunkIndex:totalChunks:data`
3. Receiving end reassembles chunks transparently
4. Application code doesn't need to change

**Example:**
```swift
// Server with chunking
let server = MCPServer(
    name: "large-data-server",
    version: "1.0.0",
    transportType: .chunkedStdio  // Enable chunking
)

await server.registerTool(toolDefinition: toolDef) { arguments in
    // Can return data > 64KB without issues
    let largeData = generateLargeReport()  // e.g., 200KB
    return .success(largeData)
}

// Client automatically handles chunking
let client = MCPClient(name: "client")
try await client.connect(inPipe: inPipe, outPipe: outPipe)
let result = try await client.callTool("generate_report")
// Works seamlessly even with 200KB response!
```

For complete documentation, see [docs/MessageChunking.md](../../docs/MessageChunking.md).

## Examples

### MCP Server Example

See `Examples/MCPServerExample/main.swift` for a complete working example that demonstrates:

- Server creation and configuration
- Tool registration with different parameter types
- Environment variable access
- Server startup and lifecycle management

### Message Filtering Example

See `Examples/MCPExample/message_filtering_example.swift` for an example that demonstrates:

- MCP client creation with message filtering
- How message filtering prevents log interference
- Different filtering configurations
- Benefits of the filtering solution

## Integration with Existing MCP Clients

The server is compatible with your existing `MCPClient` implementation. You can:

1. Start an MCPServer in one process
2. Connect to it using MCPClient in another process
3. Execute tools and receive results

## Future Enhancements

- Network transport support
- Prompt template management
- Resource management
- Advanced authentication systems
- Configuration file support
- Metrics and monitoring

## Requirements

- macOS 13.0+ / iOS 16.0+ / visionOS 1.0+
- Swift 6.0+
- MCP swift-sdk 0.9.0+
