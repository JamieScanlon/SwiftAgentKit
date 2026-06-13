# SwiftAgentKitACP — Implementation Tracker

Living document for the [Agent Client Protocol (ACP)](https://agentclientprotocol.com) implementation in SwiftAgentKit.

## Spec references

| Topic | URL |
|-------|-----|
| Introduction | https://agentclientprotocol.com/get-started/introduction |
| Overview | https://agentclientprotocol.com/protocol/overview |
| Transports | https://agentclientprotocol.com/protocol/v1/transports |
| Initialization | https://agentclientprotocol.com/protocol/v1/initialization |
| Prompt Turn | https://agentclientprotocol.com/protocol/v1/prompt-turn |
| Schema | https://agentclientprotocol.com/protocol/v1/schema |
| Documentation index | https://agentclientprotocol.com/llms.txt |

## Decisions

| Decision | Choice |
|----------|--------|
| Implementation approach | From scratch (A2A-style); no community SDK dependency |
| Protocol version | **v1** (`protocolVersion: 1`) |
| Primary transport | **stdio** (newline-delimited JSON-RPC 2.0) |
| Roles | **Client** and **Agent** |
| MCP overlap | `session/new` accepts `mcpServers[]`; stub empty array initially — future wiring to `SwiftAgentKitMCP` |
| Remote transport | Deferred (Streamable HTTP draft) |

## Phase checklist

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Implementation doc (this file) | Done |
| 1 | Package scaffolding (`SwiftAgentKitACP` target) | Done |
| 2 | Protocol models + JSON-RPC envelopes | Done |
| 3 | Connection layer + stdio transport | Done |
| 4 | Agent role (`ACPAgent`, `ACPAgentAdapter`) | Done |
| 5 | Client role (`ACPClient`, `ACPClientDelegate`) | Done |
| 6 | Config + `ACPManager` | Done |
| 7 | Tests | Done |
| 8 | `ACPToolProvider` + orchestrator integration | Done |
| 9 | User docs + example | Done |

## Spec coverage matrix

Legend: ✅ implemented · 🚧 partial · ⬜ deferred

### Agent methods (Client → Agent)

| Method | Client | Agent | Status |
|--------|--------|-------|--------|
| `initialize` | sends | handles | ✅ |
| `authenticate` | sends | handles | ✅ |
| `logout` | sends | handles | ✅ |
| `session/new` | sends | handles | ✅ |
| `session/load` | sends | handles | ✅ |
| `session/list` | sends | handles | ✅ |
| `session/resume` | sends | handles | ✅ |
| `session/prompt` | sends | handles | ✅ |
| `session/cancel` | notification | handles | ✅ |
| `session/close` | sends | handles | ✅ |
| `session/delete` | sends | handles | ✅ |
| `session/set_mode` | sends | handles | ✅ |
| `session/set_config_option` | sends | handles | ✅ |

### Client methods (Agent → Client)

| Method | Agent | Client | Status |
|--------|-------|--------|--------|
| `fs/read_text_file` | calls | handles | ✅ |
| `fs/write_text_file` | calls | handles | ✅ |
| `session/request_permission` | calls | handles | ✅ |
| `terminal/create` | calls | handles | ✅ capability-gated |
| `terminal/output` | calls | handles | ✅ capability-gated |
| `terminal/wait_for_exit` | calls | handles | ✅ capability-gated |
| `terminal/kill` | calls | handles | ✅ capability-gated |
| `terminal/release` | calls | handles | ✅ capability-gated |

### Notifications

| Method | Direction | Status |
|--------|-----------|--------|
| `session/update` | Agent → Client | ✅ |
| `current_mode_update` / `config_option_update` (via `session/update`) | Agent → Client | ✅ decode |

## Auth and session configuration (Client → Agent)

| API | Capability gate | Adapter hook |
|-----|-----------------|--------------|
| `ACPClient.authenticate(methodId:)` | `authMethods` non-empty | `ACPAgentAdapter.authenticate(methodId:)` |
| `ACPClient.logout()` | `agentCapabilities.auth.supportsLogout` | `ACPAgentAdapter.logout()` |
| `ACPClient.setSessionMode(sessionId:modeId:)` | `sessionCapabilities.supportsSetMode` | `ACPAgentAdapter.setSessionMode` |
| `ACPClient.setSessionConfigOption(sessionId:configId:value:)` | `sessionCapabilities.supportsSetConfigOption` | `ACPAgentAdapter.setSessionConfigOption` |

`connect(autoAuthenticate:)` defaults to `true` (preserves `boot()` behavior). `session/new`, `session/load`, and `session/resume` return initial `mode` and `configOptions` from `ACPAgentAdapter.sessionSetup`.

Cooperative `session/cancel` uses concurrent JSON-RPC dispatch (requests and notifications do not block the read loop) plus in-agent cancellation tracking.

## Open questions

- **Auth methods**: Per-agent; `authenticate` / `logout` delegate to `ACPAgentAdapter`; no built-in OAuth flows yet.
- **mcpServers wiring**: Wired via `ACPSessionMcpServersProvider` and `ACPConfig.mcpBootServers`; see `SwiftAgentKitAdapters` bridge from `MCPManager.localServerBootCalls()`.

## Terminal capability (Agent → Client)

Terminal RPCs flow **agent → client**: during prompt turns the agent subprocess invokes client methods; the host (ACP client) implements them via `ACPClientDelegate`. Capability is negotiated at `initialize` through `ACPClientCapabilities.terminal` (default **`false`**).

| RPC | Purpose |
|-----|---------|
| `terminal/create` | Start a shell command; returns `terminalId` |
| `terminal/output` | Read stdout/stderr from a running terminal |
| `terminal/wait_for_exit` | Block until the process exits |
| `terminal/kill` | Send signal to terminate |
| `terminal/release` | Release terminal resources |

**Handler gating:** When `clientCapabilities.terminal == false`, `ACPClient` does not register `terminal/*` handlers. Incoming calls receive JSON-RPC `-32601 methodNotFound` at the connection layer without invoking the delegate.

**Opt-in paths:**

- `ACPClient.boot(..., clientCapabilities:)` or `ACPClient.defaultClientCapabilities(advertiseTerminal: true)`
- `ACPConfig.ServerBootCall.advertiseTerminal` (per agent boot entry; default `false`)

**Delegate guidance:** Hosts supply an `ACPClientDelegate` at boot time or swap it later via ``ACPClient/setDelegate(_:)``. For per-session policy (cwd, sandbox scope), use a wrapper delegate keyed by `sessionId` (present on all terminal request params).

**`DefaultACPClientDelegate`:** Implements filesystem and permission methods only. It does not implement terminal methods; terminal stubs in the `ACPClientDelegate` protocol extension throw `methodNotFound` if a custom delegate opts into terminal at the capability level but forgets to implement a method.

Host sandbox, tool allowlists, and permission UX are **out of scope** for SwiftAgentKit — hosts implement those inside `ACPClientDelegate`.

## Notes

- Property keys use `camelCase`; discriminator string values use `snake_case` per spec.
- File paths must be absolute; line numbers are 1-based.
- Reuse MCP-style stdio filtering for non-JSON log lines on stdout.
- Bidirectional `JSONRPCConnection` is the core abstraction; test with `JSONRPCMemoryTransport.paired()` before stdio.

## Shared infrastructure

JSON-RPC wire types, connection dispatch, message filtering, and stdio transports are hoisted to **SwiftAgentKit** so ACP, MCP, and A2A share one implementation:

| SwiftAgentKit type | Role in ACP |
|--------------------|-------------|
| `JSONRPCConnection` | Bidirectional request/response dispatcher used by `ACPClient` and `ACPAgent` |
| `JSONRPCMemoryTransport` | In-process paired transport for tests |
| `PipeStdioTransport` / `ProcessStdioTransport` | Newline-delimited stdio I/O |
| `JSONRPCMessageFilter` | Filters non-JSON log lines from stdout |
| `JSONRPCErrorCode` | Standard JSON-RPC error codes |
| `ACPErrorCode` (SwiftAgentKitACP) | ACP-specific codes only (`authRequired`, `sessionNotFound`) |

ACP does **not** replace the MCP SDK — MCP continues to use the external `MCP.Client`/`MCP.Server` types while sharing filter/validator/stdio helpers from core.

## Progress log

| Date | Note |
|------|------|
| 2026-06-11 | Initial implementation: models, connection, client, agent, manager, tests, adapters, orchestrator |
| 2026-06-13 | Session lifecycle: load, list, resume, close, delete; connect() split from session creation |
| 2026-06-13 | Client→Agent completion: logout, set_mode, set_config_option, authenticate adapter hooks, cooperative session/cancel |
