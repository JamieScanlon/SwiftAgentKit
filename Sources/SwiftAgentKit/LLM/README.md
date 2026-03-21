# LLM (`Sources/SwiftAgentKit/LLM/`)

Swift source files for the **LLM surface area** of SwiftAgentKit: protocol, per-call and agentic state, queueing, and streaming results.

**User-facing documentation:** [`docs/LLMStateAndObservation.md`](../../../docs/LLMStateAndObservation.md) (StatefulLLM, QueuedLLM, observation APIs).

| File | Role |
|------|------|
| `LLMProtocol.swift` | `LLMProtocol`, `LLMRequestConfig`, defaults |
| `LLMResponse.swift` | Responses, errors, streaming chunks |
| `StreamResult.swift` | `StreamResult` for `stream` APIs |
| `LLMRuntimeState.swift` | Instance/runtime state, `StatefulLLM` |
| `LLMRequestState.swift` | `LLMRequestID`, per-call `LLMRequestState`, `LLMRequestStateHub` |
| `AgenticLoopState.swift` | `AgenticLoopID`, `AgenticLoopState`, `AgenticLoopStateHub` |
| `LLMRequestQueue.swift` | FIFO queue for `QueuedLLM` |
| `QueuedLLM.swift` | Serialize concurrent LLM calls |

Related types that stay at the package root include `Message`, `ToolCall`, `DynamicPrompt`, and `ToolProvider` (shared with MCP/A2A and adapters).
