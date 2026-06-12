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
| `logout` | sends | handles | ⬜ |
| `session/new` | sends | handles | ✅ |
| `session/load` | sends | handles | ⬜ |
| `session/list` | sends | handles | ⬜ |
| `session/resume` | sends | handles | ⬜ |
| `session/prompt` | sends | handles | ✅ |
| `session/cancel` | notification | handles | ✅ |
| `session/close` | sends | handles | ⬜ |
| `session/delete` | sends | handles | ⬜ |
| `session/set_mode` | sends | handles | ⬜ |
| `session/set_config_option` | sends | handles | ⬜ |

### Client methods (Agent → Client)

| Method | Agent | Client | Status |
|--------|-------|--------|--------|
| `fs/read_text_file` | calls | handles | ✅ |
| `fs/write_text_file` | calls | handles | ✅ |
| `session/request_permission` | calls | handles | ✅ |
| `terminal/create` | calls | handles | 🚧 stub |
| `terminal/output` | calls | handles | 🚧 stub |
| `terminal/wait_for_exit` | calls | handles | 🚧 stub |
| `terminal/kill` | calls | handles | 🚧 stub |
| `terminal/release` | calls | handles | 🚧 stub |

### Notifications

| Method | Direction | Status |
|--------|-----------|--------|
| `session/update` | Agent → Client | ✅ |

## Open questions

- **Auth methods**: Per-agent; `authenticate` implemented but no built-in OAuth flows yet.
- **Terminal capability**: Stub handlers return `methodNotFound` unless delegate implements terminal methods.
- **mcpServers wiring**: Document follow-up to connect `SwiftAgentKitMCP` when agent requests MCP servers at session creation.

## Notes

- Property keys use `camelCase`; discriminator string values use `snake_case` per spec.
- File paths must be absolute; line numbers are 1-based.
- Reuse MCP-style stdio filtering for non-JSON log lines on stdout.
- Bidirectional `ACPConnection` is the core abstraction; test with in-memory paired transports before stdio.

## Progress log

| Date | Note |
|------|------|
| 2026-06-11 | Initial implementation: models, connection, client, agent, manager, tests, adapters, orchestrator |
