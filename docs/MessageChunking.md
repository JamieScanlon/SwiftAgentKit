# Message Chunking for MCP stdio Transport

## Overview

When using stdio pipes for MCP communication on macOS, there's a 64KB limit on the amount of data that can be written to a pipe in a single operation. This limitation can cause issues when sending large JSON-RPC messages, such as tool responses with substantial data or resource contents.

SwiftAgentKit provides transparent message chunking to work around this limitation, allowing messages of any size to be sent through stdio pipes.

## The Problem

On macOS, pipe buffers have a maximum size limit:
- **Atomic write limit**: 512 bytes (PIPE_BUF)
- **Buffer size limit**: 64KB (65,536 bytes)

When writing more than 64KB to a pipe in a single operation:
1. The write operation may block
2. The write may fail with `EAGAIN` or `EWOULDBLOCK`
3. In some cases, it can lead to broken pipe errors (`EPIPE`)

For MCP servers and clients exchanging large data (e.g., file contents, generated code, large datasets), this is a significant limitation.

## The Solution: Message Chunking

SwiftAgentKit implements a transparent message chunking layer at the transport level:

### How It Works

1. **Automatic Chunking**: When a message exceeds ~60KB, it's automatically split into multiple frames
2. **Frame Format**: Each frame has a header with metadata about the chunk
3. **Transparent Reassembly**: Frames are automatically reassembled on the receiving end
4. **Protocol Agnostic**: Works transparently with JSON-RPC and MCP protocols

### Frame Format

Each frame follows this format:
```
{messageId}:{chunkIndex}:{totalChunks}:{data}\n
```

Where:
- `messageId`: Unique UUID identifying the complete message
- `chunkIndex`: Zero-based index of this chunk (0, 1, 2, ...)
- `totalChunks`: Total number of chunks for this message
- `data`: The actual chunk data
- `\n`: Newline delimiter separating frames

**Example:**
```
a1b2c3-4d5e-6f7g-8h9i-j0k1l2m3n4o5:0:3:{"jsonrpc":"2.0","method":"too...
a1b2c3-4d5e-6f7g-8h9i-j0k1l2m3n4o5:1:3:...ls/call","id":1,"params":{"na...
a1b2c3-4d5e-6f7g-8h9i-j0k1l2m3n4o5:2:3:...me":"large_tool","arguments":{}}
```

### Configuration

The chunking system uses conservative limits to ensure reliability:
- **Max Chunk Size**: 60KB (leaving room for frame overhead)
- **Frame Overhead**: ~40 bytes for header metadata
- **Effective Payload**: ~60KB per frame

## Usage

### Server Side

To enable chunking on the server side, use the `chunkedStdio` transport type:

```swift
import SwiftAgentKitMCP

// Create MCP server with chunked stdio transport
let server = MCPServer(
    name: "my-server",
    version: "1.0.0",
    transportType: .chunkedStdio  // Enable chunking
)

// Register tools that may return large responses
await server.registerTool(toolDefinition: toolDef) { arguments in
    // Return large data without worrying about pipe limits
    let largeData = generateLargeResponse()  // Can be > 64KB
    return .success(largeData)
}

// Start the server
try await server.start()
```

### Client Side

The client-side `ClientTransport` automatically supports chunking:

```swift
import SwiftAgentKitMCP

// Create client
let client = MCPClient(name: "my-client")

// Connect using stdio pipes
let inPipe = Pipe()
let outPipe = Pipe()
try await client.connect(inPipe: inPipe, outPipe: outPipe)

// Call tools - chunking is handled automatically
let result = try await client.callTool(
    "generate_large_report",
    arguments: ["format": .string("detailed")]
)
// Result can be > 64KB, no problem!
```

### When to Use Chunked Stdio

Use chunked stdio transport when:
- ✅ Running local MCP servers via stdio
- ✅ Transferring large tool results (> 64KB)
- ✅ Working with file contents or large datasets
- ✅ On macOS systems (64KB pipe limit)
- ✅ Need transparent handling without modifying application code

Don't use chunked stdio when:
- ❌ Using HTTP or network transports (not needed)
- ❌ All messages are guaranteed to be small (< 60KB)
- ❌ Remote MCP servers (use HTTP transport instead)

## Implementation Details

### MessageChunker

The `MessageChunker` actor handles chunking and reassembly:

```swift
public actor MessageChunker {
    /// Maximum size for a single chunk (60KB)
    public static let maxChunkSize = 60 * 1024
    
    /// Chunk a message into frames
    public func chunkMessage(_ message: Data) -> [Data]
    
    /// Process a frame and return complete message when ready
    public func processFrame(_ frameData: Data) throws -> Data?
}
```

### ChunkedStdioTransport

Server-side transport with chunking support:

```swift
public actor ChunkedStdioTransport: Transport {
    /// Wraps MCP.StdioTransport with chunking layer
    /// Automatically chunks outgoing messages
    /// Automatically reassembles incoming frames
}
```

### ClientTransport

Client-side transport with built-in chunking:

```swift
actor ClientTransport: Transport {
    /// Uses MessageChunker for transparent chunking
    /// Maintains buffer for frame reassembly
    /// Filters out non-JSON-RPC messages
}
```

## Performance Considerations

### Latency
- **Small messages (< 60KB)**: No additional latency
- **Large messages (> 60KB)**: Minimal overhead from framing
- **Chunking overhead**: < 1% for typical messages

### Memory
- **Buffering**: Temporary buffers hold incomplete messages
- **Memory usage**: Proportional to largest message size
- **Cleanup**: Buffers are cleared after reassembly

### Throughput
- **No significant impact**: Chunking adds minimal overhead
- **Streaming**: Chunks can be processed as they arrive
- **Concurrency**: Multiple messages can be in-flight

## Error Handling

The chunking layer handles various error scenarios:

### Missing Chunks
If chunks are lost or arrive out of order:
```swift
// MessageChunker tracks incomplete messages
// Throws ChunkerError.missingChunk if reassembly fails
```

### Invalid Frames
If a frame has invalid format:
```swift
// Throws ChunkerError.invalidFrame
// Application can retry or handle gracefully
```

### Buffer Cleanup
```swift
// Clear incomplete message buffers on error
await chunker.clearBuffers()
```

## Testing

SwiftAgentKit includes comprehensive tests for the chunking implementation:

```swift
// Test small messages (no chunking needed)
@Test("Small message doesn't get chunked")

// Test large messages are chunked correctly
@Test("Large message gets chunked")

// Test reassembly works
@Test("Message reassembly works correctly")

// Test large message reassembly
@Test("Large message reassembly works correctly")

// Test multiple concurrent messages
@Test("Multiple messages can be processed independently")
```

Run tests:
```bash
swift test --filter MessageChunkerTests
```

## Troubleshooting

### Pipe Errors
If you encounter `EPIPE` errors:
1. ✅ Ensure both client and server use chunked transport
2. ✅ Check that processes aren't terminating unexpectedly
3. ✅ Verify pipe file descriptors are valid

### Large Messages Not Working
If large messages still fail:
1. Check log output for chunking info
2. Verify `transportType: .chunkedStdio` is set
3. Confirm both ends support chunking
4. Check for message size limits in application code

### Performance Issues
If chunking causes slowdown:
1. Profile with Instruments
2. Check buffer sizes
3. Consider using network transport for very large data
4. Implement streaming for continuous data

## Example: End-to-End

Complete example with server and client:

```swift
// Server
let server = MCPServer(
    name: "data-server",
    version: "1.0.0",
    transportType: .chunkedStdio
)

await server.registerTool(toolDefinition: largeDataTool) { args in
    // Generate 100KB of data
    let data = String(repeating: "X", count: 100_000)
    return .success(data)
}

try await server.start()

// Client
let client = MCPClient(name: "data-client")
try await client.connect(inPipe: serverOut, outPipe: serverIn)

// Request large data - works seamlessly
let result = try await client.callTool("get_large_data")
// result contains 100KB of data, no problem!
```

## Compatibility

- ✅ **MCP Protocol**: Fully compatible
- ✅ **JSON-RPC 2.0**: Fully compatible
- ✅ **Swift Concurrency**: Actor-based for thread safety
- ✅ **Cross-platform**: Works on macOS, Linux, iOS
- ✅ **Backward Compatible**: Gracefully handles non-chunked messages

## Future Enhancements

Potential improvements for future versions:
- Compression of large chunks
- Adaptive chunk sizing based on pipe performance
- Progress callbacks for large message transfers
- Chunk priority/ordering optimization
- Out-of-order chunk support

## References

- [MCP Specification](https://modelcontextprotocol.io/)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
- [POSIX Pipes Documentation](https://pubs.opengroup.org/onlinepubs/9699919799/)
- [macOS Pipe Buffer Limits](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/pipe.2.html)

