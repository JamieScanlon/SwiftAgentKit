# Agent Client Protocol (ACP)

The ACP module provides support for the [Agent Client Protocol](https://agentclientprotocol.com), enabling SwiftAgentKit applications to communicate with ACP-compliant coding agents as **Clients**, or expose custom agents as ACP **Agents** over stdio JSON-RPC.

## Overview

ACP standardizes editor-to-agent communication:

- **JSON-RPC 2.0** over newline-delimited **stdio** (primary transport)
- **Bidirectional**: agents call client methods for filesystem, terminal, and permission flows
- **Session-based** prompt turns with streaming `session/update` notifications

## Shared JSON-RPC infrastructure

ACP uses shared JSON-RPC and stdio transport types from **SwiftAgentKit** (`JSONRPCConnection`, `PipeStdioTransport`, `ProcessStdioTransport`, `JSONRPCMessageFilter`). Protocol-specific models and error codes (`ACPErrorCode`) remain in SwiftAgentKitACP.

## Key Types

- `ACPClient` — Client role; connects to external ACP agent subprocesses
- `ACPAgent` — Agent role; handles client requests via `ACPAgentAdapter`
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

## See Also

- [ACPImplementation.md](ACPImplementation.md) — implementation tracker and spec coverage
- [Agent Client Protocol specification](https://agentclientprotocol.com)
