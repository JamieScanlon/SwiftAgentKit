# LLM state, wrappers, and observation

This document is the **public reference** for:

- **`StatefulLLM`** and **`QueuedLLM`** (wrappers around `LLMProtocol`)
- The three **discrete state models**: **`LLMRuntimeState`**, **`LLMRequestState`**, and **`AgenticLoopState`**
- **Where** to subscribe for each layer (instance vs per-call vs agentic session)

For the **tool-loop control flow** inside `LLMProtocolAdapter` (iterations, max iterations), see [AgenticLoopPattern](AgenticLoopPattern.md). For **A2A adapter** usage and runtime tracking, see [LLMProtocolAdapter](LLMProtocolAdapter.md). For **`SwiftAgentKitOrchestrator`**, see [SwiftAgentKitOrchestrator](SwiftAgentKitOrchestrator.md).

## Three layers (do not mix semantics)

| Layer | Meaning | Primary types | Typical observation API |
|-------|---------|-----------------|-------------------------|
| **1. LLM instance** | What the **shared model** is doing (idle vs generating vs failed). | `LLMRuntimeState`, `LLMIdleState`, `LLMGenerationState` | `llm.stateUpdates` (often via **`StatefulLLM`** wrapping your provider) |
| **2. Per-call request** | Lifecycle of **one** `send` / `stream` / `generateImage` invocation. | `LLMRequestID`, `LLMRequestState` | **`StatefulLLM.requestStateUpdates`** and/or **`QueuedLLM.requestStateUpdates`** |
| **3. Agentic session** | One **multi-call** tool loop until a final answer (or failure / max iterations). | `AgenticLoopID`, `AgenticLoopState` | **`LLMProtocolAdapter.agenticLoopUpdates`**, **`SwiftAgentKitOrchestrator.agenticLoopUpdates`** |

- **Instance** state does **not** include queue position or “waiting for tools between calls.”
- **Per-call** state can include **`queued`** only when using **`QueuedLLM`** (FIFO wait for a slot).
- **Agentic** state does **not** include **`queued`**; combine streams if you need both (see [FIFO queue + agentic](LLMProtocolAdapter.md#observing-when-the-agentic-loop-is-waiting-on-the-fifo-queue)).

Source layout: implementation files live under **`Sources/SwiftAgentKit/LLM/`** (see [`LLM/README.md`](../Sources/SwiftAgentKit/LLM/README.md)).

---

## 1. Instance state: `LLMRuntimeState` and `StatefulLLM`

**`LLMRuntimeState`** describes the **shared** LLM instance:

- `idle(LLMIdleState)` — e.g. `.ready`, `.completed`
- `generating(LLMGenerationState)` — e.g. `.reasoning`, `.responding`
- `failed(String?)`

`LLMProtocol` exposes `currentState` and `stateUpdates`. Default implementations are inert unless your provider drives state.

**`StatefulLLM`** wraps any `LLMProtocol`, owns an **`LLMRuntimeStateStore`**, and publishes transitions on **`stateUpdates`**. It implements **`LLMRuntimeStateControllable`** so adapters/orchestrators can call `transition(to:)` when they support it.

```swift
import SwiftAgentKit

let llm = StatefulLLM(baseLLM: myProvider)

Task {
    for await state in llm.stateUpdates {
        print("Runtime:", state)
    }
}
```

---

## 2. Per-call state: `LLMRequestState`, `StatefulLLM`, and `QueuedLLM`

**`LLMRequestState`** is the enum for **one** invocation:

| Case | Meaning |
|------|--------|
| `queued` | Waiting for a FIFO slot (**`QueuedLLM` only**) |
| `active` | Slot acquired; call in progress |
| `generating(LLMGenerationState)` | Generation sub-phase |
| `streaming` | Streaming chunks |
| `completed` | Call finished successfully |
| `failed(String?)` | Call failed |
| `cancelled` | Call cancelled |

**`LLMRequestID`** identifies the call; **`QueuedLLM`** and **`StatefulLLM`** set **`LLMRequestID.current`** via `TaskLocal` for correlation.

**`StatefulLLM`** publishes **`requestStateUpdates`**: `AsyncStream<(LLMRequestID, LLMRequestState)>`. It does **not** emit **`queued`** (no queue).

**`QueuedLLM`** serializes access to an inner LLM and publishes the **same** per-call timeline **plus** **`queued`** while waiting.

Recommended stack for both runtime and request timelines **and** queue visibility:

```swift
let llm = QueuedLLM(baseLLM: StatefulLLM(baseLLM: rawProvider))

Task {
    for await (requestId, state) in llm.requestStateUpdates {
        print(requestId, state)
    }
}
```

**`LLMRequestStateHub`** multicasts per-request events; **`LLMRequestStateHub.current`** allows outer wrappers to share one hub (see `QueuedLLM` + `StatefulLLM` composition).

---

## 3. Agentic session state: `AgenticLoopState` and IDs

**`AgenticLoopState`** is **coarser** than per-call state. It describes progress through the **whole** tool loop (multiple LLM calls and tool runs).

| Case | Typical meaning |
|------|-----------------|
| `started` | Agentic loop entered |
| `llmCall(iteration:)` | About to run an LLM step for this iteration |
| `waitingForToolExecution` | Model returned tool calls; about to run tools |
| `executingTools` | Tool providers running |
| `betweenIterations` | Tool results ready; about to call the LLM again |
| `completed` | Final answer (no further tool calls in this branch) |
| `failed(String?)` | Unrecoverable error |
| `maxIterationsReached` | Hit max agentic iterations (adapter path with `maxAgenticIterations`) |

**`AgenticLoopID`** identifies the session:

- **`AgenticLoopID.a2a(taskId:contextId:)`** — `LLMProtocolAdapter` tool flows keyed by A2A task + context.
- **`AgenticLoopID.orchestratorSession(UUID)`** — one id per top-level **`SwiftAgentKitOrchestrator.updateConversation`** (recursive continuations reuse it).

**Where to subscribe**

| Component | Property | Element type |
|-----------|----------|----------------|
| `LLMProtocolAdapter` | `agenticLoopUpdates` | `(AgenticLoopID, AgenticLoopState)` |
| `SwiftAgentKitOrchestrator` | `await orchestrator.agenticLoopUpdates` | `(AgenticLoopID, AgenticLoopState)` |

The adapter and orchestrator hold their own **`AgenticLoopStateHub`**; they are **not** global singletons.

**`AgenticLoopID.current`** (`TaskLocal`) may be set in future versions for nested correlation; v1 observation is stream-based.

---

## Relation to `LLMProtocolAdapter`’s agentic loop

[AgenticLoopPattern](AgenticLoopPattern.md) documents **behavior** (iterate until no tool calls, `maxAgenticIterations`). The **observable** agentic timeline for that loop is **`agenticLoopUpdates`** on **`LLMProtocolAdapter`**, using **`AgenticLoopState`** as above — not `LLMRuntimeState` alone.

---

## Logging

Library diagnostics use **`SwiftAgentKitLogging`** (see [SwiftAgentKit](SwiftAgentKit.md) § Logging). Bootstrapping is orthogonal to state streams but should be configured **before** creating adapters/orchestrators if you want structured logs from those layers.

---

## Quick reference

| Need | Use |
|------|-----|
| Idle / generating on the **model** | `StatefulLLM` + `stateUpdates` |
| **Queue** wait + per-call phases | `QueuedLLM` + `requestStateUpdates` |
| **Tool loop** progress (adapter) | `LLMProtocolAdapter.agenticLoopUpdates` |
| **Tool loop** progress (orchestrator) | `SwiftAgentKitOrchestrator.agenticLoopUpdates` |
