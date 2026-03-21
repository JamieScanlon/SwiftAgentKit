# SwiftAgentKitOrchestrator

`SwiftAgentKitOrchestrator` is an **`actor`** that wires an `LLMProtocol` implementation to optional **MCP** tools, **A2A** agents, and local **function** tools via `ToolManager`. It runs a recursive **agentic** loop: LLM response → tool execution → follow-up LLM calls until a final assistant message without pending tool calls.

> ℹ️ **Logging**  
> Use [`SwiftAgentKitLogging`](SwiftAgentKit.md) (same as other modules). The orchestrator receives a scoped logger from `SwiftAgentKitLogging.logger(for: .orchestrator, …)` if you pass `logger: nil`.

## Module dependencies

- **SwiftAgentKit** — `LLMProtocol`, `Message`, `ToolDefinition`, state types  
- **SwiftAgentKitMCP** — `MCPManager` (optional)  
- **SwiftAgentKitA2A** — `A2AManager` (optional)  
- **SwiftAgentKitAdapters** — shared adapter/tool types  

## Configuration (`OrchestratorConfig`)

| Property | Purpose |
|----------|---------|
| `streamingEnabled` | Use `llm.stream` vs `llm.send` for each LLM step |
| `mcpEnabled` | Use `mcpManager` for tool dispatch when configured |
| `a2aEnabled` | Use `a2aManager` for agent-style tool calls |
| `mcpConnectionTimeout` | Seconds for MCP connections when the orchestrator creates its own `MCPManager` |
| `maxTokens`, `temperature`, `topP`, `additionalParameters` | Passed through to `LLMRequestConfig` for every LLM call |

All feature flags default to `false` unless you opt in.

## Creating an orchestrator

```swift
import SwiftAgentKitOrchestrator
import SwiftAgentKit

let orchestrator = SwiftAgentKitOrchestrator(
    llm: myLLM,
    config: OrchestratorConfig(
        streamingEnabled: true,
        mcpEnabled: false,
        a2aEnabled: false,
        maxTokens: 4096,
        temperature: 0.7
    ),
    toolManager: ToolManager(providers: [MyToolProvider()]) // optional
)
```

- If `mcpEnabled` is `true` and you pass `mcpManager: nil`, the orchestrator constructs an `MCPManager` (optionally with `mcpOAuthHandler` for remote OAuth).  
- If `a2aEnabled` is `true` and `a2aManager` is `nil`, it constructs an `A2AManager`.  
- **`toolManager`** is optional; use it for in-process function tools that are neither MCP nor A2A.

## Conversation API

### `updateConversation(_:availableTools:)`

Processes the given message thread and:

1. Calls the LLM (streaming or sync per `config.streamingEnabled`).
2. Appends assistant messages to the internal history and publishes them on **`messageStream`**.
3. If the response includes tool calls, executes them (see **Tool dispatch** below), appends tool messages, then **recurses** with continuation queue priority so the in-flight turn can continue before unrelated work.
4. Repeats until the model returns a final answer without tool calls.

```swift
let tools = await orchestrator.allAvailableTools // MCP + A2A + ToolManager
try await orchestrator.updateConversation(
    [Message(id: UUID(), role: .user, content: "What time is it?")],
    availableTools: tools
)
```

You may pass a subset of definitions; the LLM only sees what you pass.

### `endMessageStream()`

Finishes the async stream continuations for **`messageStream`** and **`partialContentStream`**. Call when tearing down a session so consumers stop waiting.

## Output streams

| API | Content |
|-----|---------|
| **`messageStream`** | Complete `Message` values (user, assistant, tool) as the turn progresses |
| **`partialContentStream`** | Incremental text chunks while **`streamingEnabled`** is `true` |

Both are created on first access; subscribe **before** calling `updateConversation` if you need to observe every event.

```swift
let stream = await orchestrator.messageStream
Task {
    for await message in stream {
        // assistant / tool messages
    }
}
try await orchestrator.updateConversation(messages, availableTools: tools)
```

## State observation (three layers)

| Layer | Type | Orchestrator API |
|-------|------|------------------|
| **LLM instance** | `LLMRuntimeState` | `llmCurrentState`, `llmStateUpdates` (forwarded from `llm`) |
| **Single LLM call** | `LLMRequestState` | Not forwarded; observe `StatefulLLM` / `QueuedLLM` if you wrap `llm` |
| **Agentic session** | `AgenticLoopState` | **`agenticLoopUpdates`** |

### Runtime state (`LLMRuntimeState`)

Same as the underlying LLM: idle vs generating, etc.

```swift
for await state in orchestrator.llmStateUpdates {
    print(state)
}
```

### Per-call request state (`LLMRequestState`)

The orchestrator holds `any LLMProtocol` and does not expose `requestStateUpdates` on the protocol. Wrap your provider with **`StatefulLLM`** and/or **`QueuedLLM`** and subscribe on **that** wrapper. **`queued`** appears only when using **`QueuedLLM`**.

For correlating FIFO wait with the agentic loop, see [Observing when the agentic loop is waiting on the FIFO queue](LLMProtocolAdapter.md#observing-when-the-agentic-loop-is-waiting-on-the-fifo-queue) in the adapter doc (same pattern applies to the orchestrator).

### Agentic loop state (`AgenticLoopState`)

**`agenticLoopUpdates`** is an `AsyncStream<(AgenticLoopID, AgenticLoopState)>` scoped to **one top-level** `updateConversation` invocation. The id is **`AgenticLoopID.orchestratorSession(UUID)`**; recursive tool continuations reuse the same id.

Typical states (order may include repeats):

- `started` — root entry  
- `llmCall(iteration:)` — about to run an LLM step (iteration increases each recurse)  
- `waitingForToolExecution` / `executingTools` — tool batch  
- `betweenIterations` — about to call the LLM again with tool results  
- `completed` — final answer without further tool calls in this branch  
- `failed` — error surfaced from the `do`/`catch` around the turn  

Subscribe before `updateConversation`:

```swift
let agentic = await orchestrator.agenticLoopUpdates
Task {
    for await (id, state) in agentic {
        print(id, state)
    }
}
try await orchestrator.updateConversation(messages, availableTools: tools)
```

## Tool dispatch order

For each `ToolCall`, the orchestrator aggregates responses from (in order):

1. **MCP** — if `mcpManager != nil` and `mcpEnabled`  
2. **A2A** — if `a2aManager != nil` and `a2aEnabled`  
3. **`ToolManager`** — if still unresolved and `toolManager` is set  

Failures are turned into tool-role messages so the model can recover.

## Related documentation

- [SwiftAgentKit](SwiftAgentKit.md) — core types and `LLMProtocol`  
- [LLMProtocolAdapter](LLMProtocolAdapter.md) — A2A adapter; same three-layer state model and FIFO discussion  
- [MCP](MCP.md), [A2A](A2A.md) — transport details  
- Example: `Examples/OrchestratorExample/`  
