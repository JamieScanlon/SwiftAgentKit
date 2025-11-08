# Logging Audit (updated 2025-11-08)

The unified logging migration is now complete for all library modules. Every target obtains loggers from `SwiftAgentKitLogging`, honours the globally configured level, and attaches consistent subsystem/component metadata.

## Status by Area

| Area | Status | Notes |
| --- | --- | --- |
| Core (`Sources/SwiftAgentKit`) | ✅ Complete | All direct `Logger(label:)` usages replaced; warnings/errors carry structured metadata. |
| Authentication & Networking | ✅ Complete | Optional logger parameters remain, defaulting to shared scopes (`.authentication`, `.networking`). |
| SwiftAgentKitA2A | ✅ Complete | `print` calls removed; boot/stream lifecycle now logged through `.a2a` scope. |
| SwiftAgentKitMCP | ✅ Complete | Transports, clients, servers, and managers adopt `.mcp` scoped loggers; injection points preserved. |
| SwiftAgentKitAdapters | ✅ Complete | Adapters, tool providers, and proxy loggers sourced from `.adapters`; include iteration and tool metadata. |
| SwiftAgentKitOrchestrator | ✅ Complete | Defaults to `.orchestrator` scope and cascades derived loggers into auto-created MCP/A2A managers. |
| Examples (`Examples/*`) | ✅ Complete | All samples bootstrap `SwiftAgentKitLogging`, use scoped loggers for diagnostics, and retain `print` for user-facing text. |
| Documentation (`docs/*`) | ✅ Complete | Developer guides refreshed to describe bootstrap flow, scopes, and integration checkpoints. |
| Tests (`Tests/*`) | ✅ Complete | Logging suites use `LogRecorder`; other suites reset shared state via helpers to avoid cross-test leakage. |

## Next Actions

1. Capture smoke-run transcripts (core, MCP, orchestrator) for release notes.
2. Schedule follow-up review after first external adopter feedback (monitor GitHub issues/Discord).

## Follow-up: Core Module Log-Level Refinement Plan

As of the post-migration audit (2025-11-08), each SwiftAgentKit core component is now instrumented, but additional work is queued to align with the agreed level semantics:

### SwiftAgentKitLogging (`Logging/LoggingConfiguration.swift`)
- **Goal**: make level reconfiguration observable.
- **Status**: ✅ `bootstrap` and `setLevel` now emit structured `debug` traces including the first call-site symbol and metadata summary. Added `withScopedOverride` test helper so suites can temporarily adjust level/metadata without leaking state.
- **Remaining Considerations**:
  - Evaluate whether additional caller-hint depth is needed (e.g. more than the first stack symbol) based on future debugging sessions.

### Message & Supporting Types (`Message.swift`)
- **Goal**: enrich diagnostics when payloads are malformed.
- **Actions**:
  - On `.warning` (missing name/invalid JSON), attach structured metadata: payload byte counts, original keys, and UUID generation flag.
  - Add complementary `debug` events when binary fields (`imageData`, `thumbData`) fail to decode, enabling downstream tracing without raising severity.

### Authentication Providers (`Authentication/*`)
- **Cleanup noise**: downgrade routine `cleanup()` logs from `info` to `debug` for `APIKeyAuthProvider`, `BasicAuthProvider`, `BearerTokenAuthProvider`, etc.
- **Challenge handling**: supplement `error`/`warning` messages with richer metadata (scheme, header, realm, server) for better triage.
- **Bearer tokens**:
  - Log `warning` when a challenge occurs without a refresh handler (today we just throw).
  - Emit `debug` before returning headers when tokens are near expiry (include expiry delta).
- **OAuth & PKCE providers**:
  - Move large request/response dumps (registration payloads, scope enumerations) from `info` → `debug`; keep a single high-level `info` summary per lifecycle stage.
  - Attach token fingerprints (masked) and endpoint metadata to `error` logs.
- **Discovery managers/clients**:
  - When switching strategies (e.g., WWW-Authenticate → well-known URI), emit `debug` explaining the fallback reason.

### AuthenticationFactory (`AuthenticationFactory.swift`)
- Reduce `info` chatter: downgrade repetitive “Creating provider …” lines to `debug`; retain one concise `info` per success summarising scheme + identifiers.
- When throwing due to invalid config, log a `warning` with offending keys/values to aid user remediation.

### Networking (`Networking/*`)
- **RequestBuilder / RestAPIManager**:
  - Add `info` summaries per request (method, endpoint); `debug` for parameters/body size.
  - On validation failures, log `warning` alongside the thrown `APIError` with response metadata (status, payload hash, retry attempt).
- **StreamClient / SSEClient**:
  - Introduce `debug` on connection start/stop and on heartbeats/backoff.
  - Promote repeated serialization failures to `warning`, capturing retry count and timing.
- **ResponseValidator**:
  - When throwing, log `warning` containing status code and a redacted payload excerpt to accelerate debugging.

### Utilities
- **Shell.swift**: replace commented `print` debug code with optional scoped logger hooks so command execution can be traced (`debug`).

### Cross-Cutting
- Ensure every `error` includes structured metadata (`serverURL`, `authType`, `retryCount`, `tokenId`); avoid plain string interpolation.
- Keep `debug` the exclusive level for full payload bodies, per logging spec.
- Investigate rate-limiting/aggregation for actor log loops to prevent flooding under load (particularly token refresh loops).

This checklist should accompany the next sprint planning session when we tackle log-level refinement across the core.

## Reference

- `SwiftAgentKitLogging` lives in `Sources/SwiftAgentKit/Logging/LoggingConfiguration.swift`.
- Use `SwiftAgentKitLogging.metadata` to attach structured context such as `taskId`, `conversationId`, or `toolName`.
- Consumers should call `SwiftAgentKitLogging.bootstrap(logger:level:metadata:)` once during application start-up and pass scoped loggers to any integration points that offer optional overrides.

