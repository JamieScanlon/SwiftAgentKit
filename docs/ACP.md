# Agent Client Protocol (ACP)

The ACP module provides support for the [Agent Client Protocol](https://agentclientprotocol.com), enabling SwiftAgentKit applications to communicate with ACP-compliant coding agents as **Clients**, or expose custom agents as ACP **Agents** over stdio, WebSocket, or Streamable HTTP JSON-RPC.

## Overview

ACP standardizes editor-to-agent communication:

- **JSON-RPC 2.0** over newline-delimited **stdio** (primary local transport), **WebSocket**, or **Streamable HTTP** (remote, draft RFD)
- **Bidirectional**: agents call client methods for filesystem, terminal, and permission flows
- **Session-based** prompt turns with streaming `session/update` notifications
- **Extensible**: `_`-prefixed custom methods and `_meta` capability advertisement

## Shared JSON-RPC infrastructure

ACP uses shared JSON-RPC and stdio transport types from **SwiftAgentKit** (`JSONRPCConnection`, `PipeStdioTransport`, `ProcessStdioTransport`, `JSONRPCMessageFilter`). Protocol-specific models and error codes (`ACPErrorCode`) remain in SwiftAgentKitACP.

## Key Types

- `ACPClient` — Client role; connects to external ACP agent subprocesses
- `ACPAgent` — Agent role; handles client requests via `ACPAgentAdapter`
- `ACPAgentClient` — Typed Agent→Client RPC surface passed into `handlePrompt`
- `ACPManager` — Multi-agent orchestration (mirrors `MCPManager` / `A2AManager`)
- `ACPConfig` / `ACPConfigHelper` — JSON configuration for agent boot calls
- `ACPToolProvider` — `ToolProvider` bridge in `SwiftAgentKitAdapters`
- `EchoACPAgentAdapter` — Simple test/example agent adapter

## Quick Start

```swift
import SwiftAgentKit
import SwiftAgentKitACP

SwiftAgentKitLogging.bootstrap()

// In-process demo (memory transport)
let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
let agent = ACPAgent(adapter: EchoACPAgentAdapter(), transport: agentTransport)
let client = ACPClient(name: "demo", transport: clientTransport)

async let agentRun = try await agent.run()
try await client.connect()
try await client.newSession(cwd: FileManager.default.currentDirectoryPath)
let response = try await client.promptCollectingText("Hello")
await client.shutdown()
await agent.stop()
```

## Boot External Agent

```swift
let client = try await ACPClient.boot(
    name: "my-agent",
    command: "my-acp-agent",
    arguments: ["--acp"],
    environment: ["API_KEY": "secret"]
)
```

## Connect Remote Agent

```swift
// WebSocket (draft RFD profile)
let wsClient = try await ACPClient.connectWebSocket(
    name: "remote-agent",
    url: URL(string: "wss://agent.example.com/acp")!
)

// Streamable HTTP (draft RFD profile)
let httpClient = try await ACPClient.connectStreamableHTTP(
    name: "remote-agent",
    url: URL(string: "https://agent.example.com/acp")!
)
```

## Host Agent Server

```swift
let server = ACPAgentServer(
    adapter: EchoACPAgentAdapter(),
    configuration: .init(host: "0.0.0.0", port: 8080, path: "acp")
)
try await server.run()
```

## Extension Methods

Custom `_`-prefixed methods follow the [extensibility spec](https://agentclientprotocol.com/protocol/v1/extensibility):

```swift
// Client → Agent
let stats = try await client.extMethod(
    method: "_example.com/get_stats",
    params: .object([:])
)

// Agent adapter hook
func extMethod(method: String, params: JSON) async throws -> JSON {
    if method == "_example.com/get_stats" {
        return .object(["uptime": .integer(42)])
    }
    throw JSONRPCConnectionError.methodNotFound(method)
}
```

Advertise extensions in capability `_meta` via `ACPExtensionSupport.withExtensionMeta(on:namespace:features:)`.

## Configuration

```json
{
  "toolCallTimeout": 300,
  "globalEnvironment": {},
  "agentBootCalls": [
    {
      "name": "my-agent",
      "command": "my-acp-agent",
      "arguments": ["--acp"],
      "environment": {}
    },
    {
      "name": "remote-agent",
      "url": "wss://agent.example.com/acp",
      "transport": "websocket",
      "auth": { "bearerToken": "secret" }
    }
  ]
}
```

## Orchestrator Integration

```swift
let orchestrator = SwiftAgentKitOrchestrator(
    llm: myLLM,
    config: OrchestratorConfig(acpEnabled: true)
)
try await orchestrator.acpManager?.initialize(configFileURL: configURL)
```

## Session configuration

When the agent advertises `setMode` / `setConfigOption` capabilities, hosts can change session state after `newSession`:

```swift
try await client.connect()
let session = try await client.newSession(cwd: "/project")

if session.mode != nil {
    _ = try await client.setSessionMode(sessionId: session.sessionId, modeId: "code")
}

if session.configOptions?.isEmpty == false {
    _ = try await client.setSessionConfigOption(
        sessionId: session.sessionId,
        configId: "mode",
        value: "code"
    )
}
```

For agents requiring auth, call `authenticate(methodId:)` explicitly via `connect(autoAuthenticate: false)` when multiple `authMethods` are advertised.

## Agent-side client calls

During a prompt turn, `ACPAgent` supplies an `ACPAgentClient` to your adapter. Use it to read/write files, request permission, or manage terminals (when capabilities were negotiated at `initialize`):

```swift
func handlePrompt(
    sessionId: String,
    prompt: [ACPContentBlock],
    client: ACPAgentClient,
    eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
) async throws -> ACPStopReason {
    let file = try await client.readTextFile(sessionId: sessionId, path: "/project/README.md")
    try await eventSink(.agentMessageChunk(messageId: nil, content: .text(file.content)))
    return .endTurn
}
```

`ACPAgentClient` throws `capabilityUnavailable` when the host client did not advertise the required capability (for example `fs.readTextFile` or `terminal`).

## Session update notifications

Agents stream progress via `session/update` notifications. SwiftAgentKitACP models these as `ACPSessionUpdate`:

| Discriminator | Purpose |
|---------------|---------|
| `user_message_chunk` | Replay or stream user message content (history via `session/load`) |
| `agent_message_chunk` | Stream agent response text |
| `agent_thought_chunk` | Stream internal reasoning separately from the final answer |
| `available_commands_update` | Advertise slash commands for the current session |

`ACPManager.streamAgentCall` maps chunks to `ACPDelegateStreamEvent` but only accumulates `agent_message_chunk` text into the orchestrator completion payload. Thought and user chunks are surfaced as separate events.

## Slash commands

Agents advertise commands with `available_commands_update` (automatically sent after `session/new` when `ACPAgentAdapter.availableCommands(sessionId:)` returns a non-empty list). The client stores the latest list on `ACPClient.availableCommands`.

Invoke a command as regular prompt text:

```swift
try await client.newSession(cwd: "/project")
// availableCommands populated after session/new when the adapter advertises commands

let prompt = ACPSlashCommand.format(name: "web", input: "ACP spec")
let answer = try await client.promptCollectingText(prompt)

if let parsed = ACPSlashCommand.parse(text: prompt) {
    print(parsed.name, parsed.input ?? "")
}
```

Agents may also emit `.availableCommandsUpdate` mid-turn via `eventSink` when command availability changes.

## See Also

- [ACPImplementation.md](ACPImplementation.md) — implementation tracker and spec coverage
- [Agent Client Protocol specification](https://agentclientprotocol.com)
