//
//  ACPAgentAdapterTests.swift
//  SwiftAgentKitACPTests
//

import Testing
@testable import SwiftAgentKitACP

@Suite("Echo ACP Agent Adapter")
struct EchoACPAgentAdapterTests {
    @Test("Exposes agent info and capabilities")
    func metadata() {
        let adapter = EchoACPAgentAdapter(name: "echo-bot", version: "2.0.0")
        #expect(adapter.agentInfo.name == "echo-bot")
        #expect(adapter.agentInfo.version == "2.0.0")
        #expect(adapter.agentInfo.title == "Echo ACP Agent")
        #expect(adapter.agentCapabilities.loadSession == false)
        #expect(adapter.authMethods.isEmpty)
    }

    @Test("Echoes user text via event sink")
    func echoUserText() async throws {
        let adapter = EchoACPAgentAdapter(responseText: "fallback")
        let chunks = LockBox([String]())
        let reason = try await adapter.handlePrompt(
            sessionId: "s1",
            prompt: [.text("hello"), .text("world")],
            client: ACPTestHelpers.dummyAgentClient()
        ) { update in
            if case .agentMessageChunk(_, let content) = update,
               case .text(let text) = content {
                chunks.withLock { $0.append(text) }
            }
        }
        #expect(reason == .endTurn)
        #expect(chunks.value.joined().contains("hello world"))
    }

    @Test("Uses fallback text for empty prompt")
    func fallbackText() async throws {
        let adapter = EchoACPAgentAdapter(responseText: "default response")
        let chunk = LockBox("")
        _ = try await adapter.handlePrompt(sessionId: "s1", prompt: [], client: ACPTestHelpers.dummyAgentClient()) { update in
            if case .agentMessageChunk(_, let content) = update,
               case .text(let text) = content {
                chunk.value = text
            }
        }
        #expect(chunk.value.contains("default response"))
    }
}

@Suite("ACP Agent Adapter Protocol Defaults")
struct ACPAgentAdapterDefaultsTests {
    @Test("Default authMethods is empty")
    func defaultAuthMethods() {
        struct MinimalAdapter: ACPAgentAdapter {
            let agentInfo = ACPImplementation(name: "min", version: "1.0.0")
            let agentCapabilities = ACPAgentCapabilities()
            func handlePrompt(
                sessionId: String,
                prompt: [ACPContentBlock],
                client: ACPAgentClient,
                eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
            ) async throws -> ACPStopReason { .endTurn }
        }
        #expect(MinimalAdapter().authMethods.isEmpty)
    }

    @Test("Default adapter hooks are no-op or throw as documented")
    func defaultHooks() async throws {
        struct MinimalAdapter: ACPAgentAdapter {
            let agentInfo = ACPImplementation(name: "min", version: "1.0.0")
            let agentCapabilities = ACPAgentCapabilities()
            func handlePrompt(
                sessionId: String,
                prompt: [ACPContentBlock],
                client: ACPAgentClient,
                eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
            ) async throws -> ACPStopReason { .endTurn }
        }
        let adapter = MinimalAdapter()
        try await adapter.authenticate(methodId: "token")
        try await adapter.logout()
        await adapter.cancelPrompt(sessionId: "s1")
        let setup = try await adapter.sessionSetup(sessionId: "s1", cwd: "/tmp", mcpServers: [])
        #expect(setup.configOptions == nil)
        #expect(setup.mode == nil)
        do {
            _ = try await adapter.setSessionMode(sessionId: "s1", modeId: "code")
            Issue.record("Expected methodNotSupported")
        } catch let error as ACPAgentAdapterError {
            if case .methodNotSupported(let method) = error {
                #expect(method == "session/set_mode")
            }
        }
        #expect(try await adapter.availableCommands(sessionId: "s1").isEmpty)
    }
}
