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

**Status**: ⚠️ Partially implemented
- ✅ Basic structure
- ✅ Moved to SwiftAgentKitAdapters package
- ⚠️ TODO: Make agentCard accessible from A2AClient
- ⚠️ TODO: Implement proper tool execution

### 4. MCPToolProvider

Wraps MCP clients to provide them as tools.

**Status**: ⚠️ Partially implemented
- ✅ Basic structure
- ✅ Moved to SwiftAgentKitAdapters package
- ⚠️ TODO: Make tools accessible from MCPClient
- ⚠️ TODO: Implement proper argument conversion from [String: Any] to MCP Value

### 5. ToolAwareAdapter

Enhanced adapter that can use tools while keeping the base adapter unchanged.

**Status**: ⚠️ Partially implemented
- ✅ Basic structure
- ✅ Moved to SwiftAgentKitAdapters package
- ⚠️ TODO: Implement actual tool integration with LLM
- ⚠️ TODO: Implement streaming tool support

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
// TODO: Initialize A2A clients
// let a2aClient = A2AClient(server: a2aServer)
// try await a2aClient.initializeA2AClient()

let adapter = AdapterBuilder()
    .withLLM(AnthropicAdapter(apiKey: "your-key"))
    // .withA2AClient(a2aClient)  // Uncomment when ready
    .build()
```

### With MCP Tools

```swift
// TODO: Initialize MCP clients
// let mcpClient = MCPClient(bootCall: mcpBootCall, version: "1.0")
// try await mcpClient.initializeMCPClient(config: mcpConfig)

let adapter = AdapterBuilder()
    .withLLM(GeminiAdapter(apiKey: "your-key"))
    // .withMCPClient(mcpClient)  // Uncomment when ready
    .build()
```

### With Both A2A and MCP

```swift
let adapter = AdapterBuilder()
    .withLLM(OpenAIAdapter(apiKey: "your-key"))
    // .withA2AClient(a2aClient)
    // .withMCPClient(mcpClient)
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

## Implementation TODOs

### High Priority

1. **Make A2AClient.agentCard accessible**
   - File: `Sources/SwiftAgentKitA2A/A2AClient.swift`
   - Status: ✅ Done (made public)

2. **Make MCPClient.tools accessible**
   - File: `Sources/SwiftAgentKitMCP/MCPClient.swift`
   - Status: ✅ Done (made public)

3. **Implement proper tool execution in A2AToolProvider**
   - File: `Sources/SwiftAgentKitAdapters/A2AToolProvider.swift`
   - TODO: Handle different message types and error cases

4. **Implement argument conversion in MCPToolProvider**
   - File: `Sources/SwiftAgentKitAdapters/MCPToolProvider.swift`
   - TODO: Convert [String: Any] to MCP Value type

### Medium Priority

5. **Implement LLM tool integration in ToolAwareAdapter**
   - File: `Sources/SwiftAgentKitAdapters/ToolAwareAdapter.swift`
   - TODO: Integrate with LLM's tool calling capabilities
   - TODO: Handle tool call detection and execution

6. **Implement streaming tool support**
   - File: `Sources/SwiftAgentKitAdapters/ToolAwareAdapter.swift`
   - TODO: Support tool calls in streaming mode

7. **Add proper error handling and logging**
   - TODO: Improve error messages and logging throughout

### Low Priority

8. **Add tool validation**
   - TODO: Validate tool definitions and parameters

9. **Add tool caching**
   - TODO: Cache tool results for performance

10. **Add tool metrics**
    - TODO: Track tool usage and performance

## Swift 6 Structured Concurrency Compliance

The implementation uses:

- ✅ `Sendable` protocol for all types
- ✅ `EasyJSON` instead of `[String: Any]` for metadata
- ✅ `async/await` for all asynchronous operations
- ✅ Proper actor isolation

## Testing

Run the example to see the current implementation:

```bash
swift run ToolAwareExample
```

## Future Enhancements

1. **LLM Integration**: Integrate with LLM tool calling APIs (OpenAI function calling, Anthropic tool use, etc.)
2. **Tool Discovery**: Automatic tool discovery and registration
3. **Tool Composition**: Allow tools to call other tools
4. **Tool Versioning**: Support for different versions of tools
5. **Tool Security**: Add security and access control for tools

## Contributing

When implementing the TODOs:

1. Follow Swift 6 structured concurrency best practices
2. Use EasyJSON for all metadata to ensure Sendable compliance
3. Add comprehensive logging
4. Add tests for new functionality
5. Update this documentation 