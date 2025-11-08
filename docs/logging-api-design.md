# SwiftAgentKit Unified Logging Design

Date: 2025-11-08  
Owner: Logging working group

## Goals

- Enforce exclusive usage of the Swift Logging (`swift-log`) API across all SwiftAgentKit targets.
- Allow library consumers to inject their own `Logger` instance and desired log level.
- Provide a safe, shared logging surface that every target (core, A2A, MCP, Adapters, Orchestrator, examples, tests) can rely on.
- Default to a no-op logger when the integrator does not supply one (logs go to `/dev/null`).
- Define clear semantics for the four supported levels (`debug`, `info`, `warning`, `error`) and ensure lower levels include the information from higher levels as requested.

## Summary of the Implemented API

- `Sources/SwiftAgentKit/Logging/LoggingConfiguration.swift` hosts the shared surface `SwiftAgentKitLogging`.
- Internally we keep a `LockProtected` state struct that stores:
  - the currently bootstrapped base `Logger` (defaults to the no-op logger),
  - default metadata merged into every derived logger,
  - the active `Logger.Level`.
- Public, synchronous API:
  - `SwiftAgentKitLogging.bootstrap(logger: Logger?, level: AgentLogLevel = .info, metadata: Logger.Metadata = [:])`
  - `SwiftAgentKitLogging.setLevel(_ level: AgentLogLevel)`
  - `SwiftAgentKitLogging.level() -> AgentLogLevel`
  - `SwiftAgentKitLogging.logger(for scope: LoggingScope, metadata: Logger.Metadata = [:]) -> Logger`
  - `SwiftAgentKitLogging.metadata(_: Logger.Metadata...) -> Logger.Metadata` helper for building structured payloads.
- Support types:
  - `AgentLogLevel`: maps `.debug/.info/.warning/.error` to `Logger.Level` and vice‑versa.
  - `LoggingScope`: encapsulates subsystem + component naming (`.core("Message")`, `.authentication("OAuthDiscovery")`, `.mcp("RemoteTransport")`, `.adapters("OpenAIAdapter")`, `.orchestrator`, etc.).
  - `NullLogHandler`: internal `LogHandler` that discards output while still keeping metadata slots available; used when integrators do not provide a logger.

All methods live in the core `SwiftAgentKit` target; every other target already depends on it, so no new target graph edges are needed.

## Lifecycle & Thread Safety

- All state mutations run through a private `LockProtected` wrapper, giving us a simple critical section without requiring async/await at call sites.
- `bootstrap` swaps the base logger (or installs the null logger) and updates the shared level + default metadata atomically.
- Every call to `logger(for:metadata:)` clones the base logger, reapplies the current level, and merges metadata in priority order: bootstrap defaults → scope metadata → call-site metadata.
- Returning a fresh `Logger` keeps usage `Sendable`, so callers can persist scoped loggers inside actors or classes without additional synchronisation.

## Level Semantics

| Requested Level | Includes | Required Payload |
| --- | --- | --- |
| `.debug` | debug + info + warning + error | Full request/response bodies, serialized JSON payloads, streaming chunks, and contextual metadata (`requestId`, `component`, `taskId`, etc.). |
| `.info` | info + warning + error | Operational flow messages (start/stop, key decisions), structured metadata (counts, identifiers), exclusion of full raw bodies. |
| `.warning` | warning + error | Recoverable issues, retries, unexpected-but-handled states. Must include enough metadata to trace the condition. |
| `.error` | error only | Non-recoverable failures with a human-readable reason, underlying error, and suggested next steps where applicable. |

We map `AgentLogLevel` to `Logger.Level` as follows: `.debug → .debug`, `.info → .info`, `.warning → .warning`, `.error → .error`. `SwiftAgentKitLogging` ensures the underlying handler is never configured to emit levels below the requested minimum.

## Component Responsibilities (Status 2025‑11‑08)

- ✅ **Core (`Sources/SwiftAgentKit`)** – all direct `Logger(label:)` usages now flow through scoped loggers; configuration warnings use `logger.warning`.
- ✅ **Authentication providers** – every provider accepts an optional logger parameter and falls back to `.authentication("ProviderName")` metadata enriched with contextual keys (issuer, header names, etc.).
- ✅ **Networking** – streaming clients pull `.networking` scoped loggers and honour injected instances.
- ✅ **SwiftAgentKitA2A** – all `print` statements replaced with `.a2a` scoped logging, propagating metadata such as server URL and boot command.
- ✅ **SwiftAgentKitMCP** – transports, manager, and server types default to `.mcp` scoped loggers; constructor parameters still accept overrides for host applications.
- ✅ **SwiftAgentKitAdapters** – adapters, tool providers, and proxy now adopt `.adapters` scopes and include iteration/tool metadata at `debug` level.
- ✅ **SwiftAgentKitOrchestrator** – defaults to `.orchestrator` scope and cascades scoped loggers into auto-created MCP/A2A managers.
- ✅ **Examples** – each CLI sample bootstraps `SwiftAgentKitLogging`, uses scoped loggers for diagnostics, and preserves `print` for end-user feedback.
- ✅ **Documentation** – all guides point to the unified API with concrete bootstrap/scoping snippets.
- ✅ **Tests** – suites share `LogRecorder` fixtures and reset logging state to prevent cross-test interference.

## Dev / Null Logger Strategy

- `SwiftAgentKitLogging.makeNullLogger()` returns a `Logger` backed by `NullLogHandler`, which discards all output.
- When `bootstrap` receives `nil`, we install the null logger but record the desired level so future `bootstrap` calls (or reconfiguration at runtime) preserve intent.
- Library consumers can explicitly silence logs by calling `SwiftAgentKitLogging.bootstrap(logger: nil, level: .warning)`; silent mode still attaches subsystem metadata so downstream loggers remain shape-compatible.

## API Sketch

```swift
import Logging

SwiftAgentKitLogging.bootstrap(
    logger: Logger(label: "com.example.app"),
    level: .info,
    metadata: ["deployment": .string("staging")]
)

let orchestratorLogger = SwiftAgentKitLogging.logger(
    for: .orchestrator,
    metadata: SwiftAgentKitLogging.metadata(("conversationId", .string(id.uuidString)))
)

orchestratorLogger.info("Session started")
```

Scoped loggers reuse the injected handler and merge metadata in priority order. Downstream modules (e.g. `SwiftAgentKitMCP`) call the same helper to ensure consistent subsystem/component tags without the caller needing to thread loggers manually.

## Testing Strategy

- Add Swift Testing suites under `Tests/SwiftAgentKitTests/Logging/`.
  - Verify `SwiftAgentKitLogging.logger(for:)` returns the same handler when called repeatedly (no new label creation).
  - Confirm level propagation: switching from `.info` to `.debug` emits additional messages when using a spy handler.
  - Ensure `bootstrap(logger: nil, ...)` produces silent output via the null handler.
  - Confirm metadata scoping (component names, custom metadata) is applied to captured records.
- Add integration tests in `SwiftAgentKitMCPTests` covering logger injection paths (when caller supplies logger vs defaults).

## Rollout Status & Next Steps

1. ✅ Core logging infrastructure landed with `NullLogHandler`, level management, and metadata helpers.
2. ✅ Core, A2A, MCP, Adapters, and Orchestrator modules migrated to scoped loggers.
3. ✅ Unit tests updated with a `LogRecorder` harness validating level propagation.
4. ✅ Examples gained shared bootstrap helpers so CLI apps emit both application output (`print`) and library diagnostics (`logger`).
5. ✅ Documentation references `SwiftAgentKitLogging` across the guide set (`docs/SwiftAgentKit.md`, `docs/A2A.md`, etc.).
6. ✅ Final validation completed: full test suite passes and example smoke-runs exercised scoped logging.

The staged approach keeps PRs reviewable and lets us validate behaviour at each layer while we finish examples/docs.

