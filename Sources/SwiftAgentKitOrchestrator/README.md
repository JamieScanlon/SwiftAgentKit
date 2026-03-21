# SwiftAgentKitOrchestrator

Building blocks for LLM orchestrators that can:

- Use tools through **MCP** (Model Context Protocol)
- Communicate with other agents through **A2A** (Agent-to-Agent)
- Execute local function tools via **`ToolManager`**
- Observe **instance**, **per-call**, and **agentic** state (see full doc below)

**Full documentation:** [`docs/SwiftAgentKitOrchestrator.md`](../../docs/SwiftAgentKitOrchestrator.md) (state streams, `updateConversation`, tool dispatch).

## Dependencies

- `SwiftAgentKit`
- `SwiftAgentKitA2A`
- `SwiftAgentKitMCP`
- `SwiftAgentKitAdapters`
- `swift-log`

## Quick start

```swift
import SwiftAgentKitOrchestrator
import SwiftAgentKit

let config = OrchestratorConfig(
    streamingEnabled: true,
    mcpEnabled: false,
    a2aEnabled: false
)

let orchestrator = SwiftAgentKitOrchestrator(llm: myLLM, config: config)

// Subscribe to complete messages (create the stream before updateConversation)
let messageStream = await orchestrator.messageStream
Task {
    for await message in messageStream {
        print("Message:", message.role, message.content.prefix(80))
    }
}

// Optional: agentic tool-loop progress (one session id per top-level updateConversation)
let agenticLoop = await orchestrator.agenticLoopUpdates
Task {
    for await (_, state) in agenticLoop {
        print("Agentic:", state)
    }
}

let messages = [
    Message(id: UUID(), role: .user, content: "Hello!")
]

try await orchestrator.updateConversation(messages, availableTools: [])
```

### API reminders

- `SwiftAgentKitOrchestrator` is an **`actor`** — use `await` to access properties and methods.
- Public surface: `llm`, `config`, `logger`, `mcpManager`, `a2aManager`, `toolManager`, `allAvailableTools`, `messageStream`, `partialContentStream`, `llmCurrentState`, `llmStateUpdates`, **`agenticLoopUpdates`**, `updateConversation`, `endMessageStream`.
- **`updateConversation`** is `async throws` and returns **`Void`** (it pushes to streams).

## Configuration

`OrchestratorConfig` includes:

| Flag / field | Meaning |
|----------------|--------|
| `streamingEnabled` | `stream` vs `send` for LLM calls |
| `mcpEnabled` / `a2aEnabled` | Enable those subsystems |
| `mcpConnectionTimeout` | When the orchestrator creates `MCPManager` |
| `maxTokens`, `temperature`, `topP`, `additionalParameters` | Passed to each `LLMRequestConfig` |

## Features

- Recursive agentic loop with tool results fed back to the LLM
- **Partial** streaming chunks (`partialContentStream`) when streaming is enabled
- **LLM runtime** visibility via `llmStateUpdates`
- **Agentic** visibility via `agenticLoopUpdates` (`AgenticLoopID.orchestratorSession`, `AgenticLoopState`)
- Per-call **`LLMRequestState`** (including **`queued`**) only if you wrap the LLM with `StatefulLLM` / `QueuedLLM` yourself — see [`docs/SwiftAgentKitOrchestrator.md`](../../docs/SwiftAgentKitOrchestrator.md)

## Examples

See **`Examples/OrchestratorExample/`**.
