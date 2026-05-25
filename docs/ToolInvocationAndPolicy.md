# Tool Invocation, Policy, and Dispatch Planning

This document describes the direct tool invocation and policy pipeline added to `SwiftAgentKitOrchestrator`.

## Direct Invocation APIs

- `invokeTool(_ request: ToolInvocationRequest) async -> ToolInvocationOutcome`
- `invokeTools(_ request: ToolBatchInvocationRequest) async -> ToolBatchInvocationOutcome`

These APIs execute tools through the same orchestrator dispatch boundary used by model-driven tool calls, including timeout handling, pending tool support, and lifecycle events.

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

- `serial`
- `allParallel`
- `mixedDeterministic`

`mixedDeterministic` groups parallel-safe read-only calls into parallel stages and serializes mutating/unknown calls, preserving input order for replayability.

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
