# Tool Invocation, Policy, and Dispatch Planning

This document describes the direct tool invocation and policy pipeline added to `SwiftAgentKitOrchestrator`.

## Direct Invocation APIs

- `invokeTool(_ request: ToolInvocationRequest) async -> ToolInvocationOutcome`
- `invokeTools(_ request: ToolBatchInvocationRequest) async -> ToolBatchInvocationOutcome`

These APIs execute tools through the same orchestrator dispatch boundary used by model-driven tool calls, including timeout handling, pending tool support, and lifecycle events.

`invokeTool` wraps a single request as a one-item batch and inherits orchestrator config defaults (including parallel enablement and in-flight cap) unless the batch request overrides them.

## Parallel Dispatch Controls

### Enablement

- `OrchestratorConfig.parallelToolDispatchEnabled` defaults to **`false`** (opt-in).
- `ToolBatchInvocationRequest.parallelToolDispatchEnabled` (optional) overrides config for that batch:  
  `request.parallelToolDispatchEnabled ?? config.parallelToolDispatchEnabled`
- For the agentic `updateConversation` path, `OrchestratorInvocationOptions.parallelToolDispatchEnabled` overrides config the same way.

### Bounded fan-out

- `OrchestratorConfig.maxParallelInFlightPerStage` defaults to **`10`** (clamped to at least 1).
- `ToolBatchInvocationRequest.maxParallelInFlightPerStage` and `OrchestratorInvocationOptions.maxParallelInFlightPerStage` optionally override the cap.
- Parallel stages never admit more than the resolved cap of concurrent executions; additional calls wait until an in-flight slot frees.

## Pre-Dispatch Policy Hook

Configure a structured pre-dispatch policy evaluator with:

- `OrchestratorConfig.preDispatchPolicyEvaluator`
- `OrchestratorInvocationOptions.preDispatchPolicyEvaluator`

Supported decisions:

- `allow`
- `deny`
- `requireApproval`
- `elevated`

Policy metadata (`reasonCode`, `reasonText`, optional `approvalSpec`) is attached to lifecycle events and invocation metadata.

## Descriptor Completeness Validation

`ToolManager` now supports descriptor validation modes:

- `.warning` (default): keeps descriptors and logs completeness issues once per unique `(toolName, source, issues)` fingerprint per process.
- `.strict`: rejects descriptors with incomplete canonical metadata.

Canonical completeness requires:

- explicit `effectClass` (not `unknown`)
- explicit `parallelHint` (not `unknown`)
- normalized schema fingerprint

## Metadata Hinting for Providers

Providers can declare per-tool canonical metadata in one place by conforming to `ToolDescriptorHinting` and returning `descriptorHintsByToolName`.

`ToolProvider` default implementations consult these hints for:

- `effectClass(for:)`
- `executionParallelHint(for:)`
- `policyTags(for:)`
- `parallelSafety(for:)` (derived from hint unless overridden)

This avoids repetitive per-tool `switch` statements and reduces annotation drift.

## Dispatch Planner Modes

The orchestrator supports planner modes:

- `serial` — one serial stage per tool, preserving input order
- `allParallel` — single stage containing all tools; runs parallel when enablement is on, otherwise downgrades the stage to serial execution
- `mixedDeterministic` — walks tools in input order; contiguous parallel-safe calls form a parallel stage; mutating/unknown calls become serial stages

`mixedDeterministic` groups parallel-safe read-only calls into parallel stages and serializes mutating/unknown calls, preserving input order for replayability.

When `dispatchPlannerMode` is `nil` on the agentic path, the legacy `DefaultToolDispatchPolicyEvaluator` chooses all-serial vs all-parallel for the batch.

## Commit Order vs Progress Interleaving

Within a parallel stage:

- **Lifecycle / progress events** may emit as tools complete (completion order).
- **Committed** tool results and `invokeTools` batch outcomes are always reconstructed in **call / input order** after the stage finishes.

Hosts that pair transcripts, compaction, or provider messages with `tool_use` order must rely on committed outcomes, not lifecycle arrival order.

## Deferred Context Modifiers

Tools may enqueue `ToolContextModifier` values via `ToolContextModifierQueue` during a stage (typically through a task-local collector installed by the orchestrator). Sibling tools in a parallel stage share a pre-stage `ToolDispatchSharedContext` snapshot and must not observe each other's mid-stage mutations.

After the stage completes, queued modifiers are applied to the shared context **in call order**, then the next stage runs. This keeps shared-state updates deterministic across parallel groups.

## Raw Command Envelope

Direct invocation requests support argument modes:

- `parsed`
- `raw`

When `raw`, use `RawToolCommandEnvelope` with:

- `envelopeVersion`
- `rawText`
- `commandToken`
- `commandName`
- `argsText`
- `parsedTokens`

This payload is normalized before policy evaluation and dispatch.
