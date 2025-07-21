# Tool-Aware Adapter Architecture

This document describes the composable architecture for building adapters with A2A and MCP tool calling capabilities.

## Overview

The tool-aware architecture allows you to easily assemble adapters with different tool capabilities without modifying the core A2AServer or AgentAdapter protocol. The architecture is designed to be:

- **Composable**: Mix and match A2A agents and MCP tools as needed
- **Extensible**: Easy to add new tool providers
- **Simple**: Basic setup requires minimal code
- **Flexible**: Can use any LLM adapter with any combination of tools
- **Backward Compatible**: Existing adapters work unchanged

## Architecture Components

### 1. ToolProvider Protocol

```swift
public protocol ToolProvider: Sendable {
    var name: String { get }
    var availableTools: [ToolDefinition] { get }
    func executeTool(_ toolCall: ToolCall) async throws -> ToolResult
}
```

**Status**: ✅ Implemented

### 2. ToolManager

Coordinates multiple tool providers and handles tool execution.

**Status**: ✅ Implemented

### 3. A2AToolProvider

Wraps A2A clients to provide them as tools.

**Status**: ✅ Implemented
- ✅ Basic structure
- ✅ Moved to SwiftAgentKitAdapters package
- ✅ agentCard accessible from A2AClient
- ✅ Implemented proper tool execution with error handling

### 4. MCPToolProvider

Wraps MCP clients to provide them as tools.

**Status**: ✅ Implemented
- ✅ Basic structure
- ✅ Moved to SwiftAgentKitAdapters package
- ✅ tools accessible from MCPClient
- ✅ Implemented proper argument conversion from [String: Sendable] to MCP Value

### 5. ToolAwareAdapter

Enhanced adapter that can use tools while keeping the base adapter unchanged.

**Status**: ✅ Implemented
- ✅ Basic structure
- ✅ Moved to SwiftAgentKitAdapters package
- ✅ Implemented actual tool integration with LLM
- ✅ Implemented streaming tool support
- ✅ Tool call detection and parsing
- ✅ Tool execution and result integration
- ✅ Comprehensive error handling and logging

### 6. AdapterBuilder

Builder pattern for easily assembling adapters with different tool capabilities.

**Status**: ✅ Implemented
- ✅ Moved to SwiftAgentKitAdapters package

## Usage Examples

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
// Initialize MCP clients
let mcpClient = MCPClient(bootCall: mcpBootCall, version: "1.0")
try await mcpClient.initializeMCPClient(config: mcpConfig)

let adapter = AdapterBuilder()
    .withLLM(GeminiAdapter(apiKey: "your-key"))
    .withMCPClient(mcpClient)
    .build()
```

### With Both A2A and MCP

```swift
let adapter = AdapterBuilder()
    .withLLM(OpenAIAdapter(apiKey: "your-key"))
    .withA2AClient(a2aClient)
    .withMCPClient(mcpClient)
    .build()
```

### Custom Tool Provider

```swift
struct CustomToolProvider: ToolProvider {
    public var name: String { "Custom Tools" }
    
    public var availableTools: [ToolDefinition] {
        [ToolDefinition(name: "custom_function", description: "A custom function", type: .function)]
    }
    
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        // Your custom implementation
    }
}

let adapter = AdapterBuilder()
    .withLLM(OpenAIAdapter(apiKey: "your-key"))
    .withToolProvider(CustomToolProvider())
    .build()
```

## Implementation Status

### ✅ Completed Features

1. **A2AClient.agentCard accessibility**
   - File: `Sources/SwiftAgentKitA2A/A2AClient.swift`
   - Status: ✅ Done (made public)

2. **MCPClient.tools accessibility**
   - File: `Sources/SwiftAgentKitMCP/MCPClient.swift`
   - Status: ✅ Done (made public)

3. **Tool execution in A2AToolProvider**
   - File: `Sources/SwiftAgentKitAdapters/A2AToolProvider.swift`
   - Status: ✅ Done (handles different message types and error cases)

4. **Argument conversion in MCPToolProvider**
   - File: `Sources/SwiftAgentKitMCP/MCPManager.swift`
   - Status: ✅ Done (converts [String: Sendable] to MCP Value type)

5. **LLM tool integration in ToolAwareAdapter**
   - File: `Sources/SwiftAgentKitAdapters/ToolAwareAdapter.swift`
   - Status: ✅ Done (integrates with LLM's tool calling capabilities)
   - Status: ✅ Done (handles tool call detection and execution)

6. **Streaming tool support**
   - File: `Sources/SwiftAgentKitAdapters/ToolAwareAdapter.swift`
   - Status: ✅ Done (supports tool calls in streaming mode)

7. **Error handling and logging**
   - Status: ✅ Done (comprehensive error messages and logging throughout)

### 🔮 Future Enhancements

8. **Tool validation**
   - TODO: Validate tool definitions and parameters

9. **Tool caching**
   - TODO: Cache tool results for performance

10. **Tool metrics**
    - TODO: Track tool usage and performance

## Swift 6 Structured Concurrency Compliance

The implementation uses:

- ✅ `Sendable` protocol for all types
- ✅ `EasyJSON` instead of `[String: Any]` for metadata
- ✅ `async/await` for all asynchronous operations
- ✅ Proper actor isolation

## Testing

The tool-aware architecture is fully implemented and tested. Run the example to see it in action:

```bash
swift run ToolAwareExample
```

The example demonstrates:
- Basic adapter creation without tools
- Tool-aware adapter creation with custom tool providers  
- Tool execution and parsing
- Custom tool provider integration
- Streaming tool support

## Future Enhancements

1. **Enhanced LLM Integration**: Further integrate with LLM tool calling APIs (OpenAI function calling, Anthropic tool use, etc.)
2. **Tool Discovery**: Automatic tool discovery and registration
3. **Tool Composition**: Allow tools to call other tools
4. **Tool Versioning**: Support for different versions of tools
5. **Tool Security**: Add security and access control for tools
6. **Tool Validation**: Validate tool definitions and parameters
7. **Tool Caching**: Cache tool results for performance
8. **Tool Metrics**: Track tool usage and performance

## Contributing

When contributing to the tool-aware architecture:

1. Follow Swift 6 structured concurrency best practices
2. Use EasyJSON for all metadata to ensure Sendable compliance
3. Add comprehensive logging
4. Add tests for new functionality
5. Update this documentation 