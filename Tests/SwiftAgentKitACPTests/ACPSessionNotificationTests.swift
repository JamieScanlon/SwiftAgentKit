//
//  ACPSessionNotificationTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import SwiftAgentKit
import Testing
@testable import SwiftAgentKitACP

private struct CommandsTestAdapter: ACPAgentAdapter {
    let agentInfo: ACPImplementation
    let agentCapabilities: ACPAgentCapabilities
    let commands: [ACPAvailableCommand]
    let promptUpdates: [ACPSessionUpdate]

    init(
        commands: [ACPAvailableCommand] = [],
        promptUpdates: [ACPSessionUpdate] = []
    ) {
        self.agentInfo = ACPImplementation(name: "commands-agent", version: "1.0.0")
        self.agentCapabilities = ACPAgentCapabilities()
        self.commands = commands
        self.promptUpdates = promptUpdates
    }

    func availableCommands(sessionId: String) async throws -> [ACPAvailableCommand] {
        commands
    }

    func handlePrompt(
        sessionId: String,
        prompt: [ACPContentBlock],
        client: ACPAgentClient,
        eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
    ) async throws -> ACPStopReason {
        for update in promptUpdates {
            try await eventSink(update)
        }
        return .endTurn
    }
}

@Suite("ACP Slash Command Support")
struct ACPSlashCommandSupportTests {
    @Test("format and parse round-trip")
    func formatParseRoundTrip() {
        let prompt = ACPSlashCommand.format(name: "web", input: "ACP spec")
        #expect(prompt == "/web ACP spec")

        let parsed = ACPSlashCommand.parse(text: prompt)
        #expect(parsed?.name == "web")
        #expect(parsed?.input == "ACP spec")
    }

    @Test("format without input")
    func formatWithoutInput() {
        #expect(ACPSlashCommand.format(name: "test") == "/test")
        let parsed = ACPSlashCommand.parse(text: "/test")
        #expect(parsed?.name == "test")
        #expect(parsed?.input == nil)
    }

    @Test("available command matches prompt")
    func commandMatchesPrompt() {
        let command = ACPAvailableCommand(name: "web", description: "Search the web")
        #expect(command.matches(prompt: "/web ACP spec"))
        #expect(!command.matches(prompt: "hello"))
        #expect(!command.matches(prompt: "/test"))
    }
}

@Suite("ACP Session Notification Delivery")
struct ACPSessionNotificationDeliveryTests {
    @Test("available_commands_update populates client without prompt")
    func availableCommandsAfterNewSession() async throws {
        let commands = [
            ACPAvailableCommand(name: "web", description: "Search the web"),
            ACPAvailableCommand(name: "test", description: "Run tests")
        ]
        let adapter = CommandsTestAdapter(commands: commands)
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: adapter, transport: agentTransport)
        let client = ACPClient(name: "test-client", transport: clientTransport)

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        _ = try await client.newSession(cwd: "/project")

        // `available_commands_update` is published asynchronously after session/new.
        var stored: [ACPAvailableCommand] = []
        for _ in 0..<50 {
            stored = await client.availableCommands
            if stored.count == 2 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(stored.count == 2)
        #expect(stored.map(\.name) == ["web", "test"])

        await client.shutdown()
        await agent.stop()
        _ = try await agentRun
    }

    @Test("prompt stream receives user, thought, and agent message chunks")
    func mixedChunkTypesInPromptStream() async throws {
        let updates: [ACPSessionUpdate] = [
            .userMessageChunk(messageId: "u1", content: .text("prior user turn")),
            .agentThoughtChunk(messageId: "t1", content: .text("thinking")),
            .agentMessageChunk(messageId: "m1", content: .text("answer"))
        ]
        let adapter = CommandsTestAdapter(promptUpdates: updates)
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: adapter, transport: agentTransport)
        let client = ACPClient(name: "test-client", transport: clientTransport)

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        _ = try await client.newSession(cwd: "/project")

        let (stream, responseTask) = try await client.promptStream("hello")
        var received: [ACPSessionUpdate] = []
        for await update in stream {
            received.append(update)
        }
        _ = try await responseTask.value

        #expect(received.count == 3)
        if case .userMessageChunk = received[0] {} else {
            Issue.record("Expected userMessageChunk first")
        }
        if case .agentThoughtChunk = received[1] {} else {
            Issue.record("Expected agentThoughtChunk second")
        }
        if case .agentMessageChunk = received[2] {} else {
            Issue.record("Expected agentMessageChunk third")
        }

        await client.shutdown()
        await agent.stop()
        _ = try await agentRun
    }

    @Test("promptCollectingText ignores user and thought chunks")
    func promptCollectingTextIgnoresNonAgentChunks() async throws {
        let updates: [ACPSessionUpdate] = [
            .userMessageChunk(messageId: "u1", content: .text("user")),
            .agentThoughtChunk(messageId: "t1", content: .text("thought")),
            .agentMessageChunk(messageId: "m1", content: .text("visible"))
        ]
        let adapter = CommandsTestAdapter(promptUpdates: updates)
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: adapter, transport: agentTransport)
        let client = ACPClient(name: "test-client", transport: clientTransport)

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        _ = try await client.newSession(cwd: "/project")

        let collected = try await client.promptCollectingText("hello")
        #expect(collected == "visible")

        await client.shutdown()
        await agent.stop()
        _ = try await agentRun
    }

    @Test("echo adapter emits thought chunk when configured")
    func echoAdapterThoughtChunk() async throws {
        let adapter = EchoACPAgentAdapter(emitThought: true)
        let kinds = LockBox([String]())
        _ = try await adapter.handlePrompt(
            sessionId: "s1",
            prompt: [.text("hi")],
            client: ACPTestHelpers.dummyAgentClient()
        ) { update in
            switch update {
            case .agentThoughtChunk: kinds.withLock { $0.append("thought") }
            case .agentMessageChunk: kinds.withLock { $0.append("message") }
            default: kinds.withLock { $0.append("other") }
            }
        }
        #expect(kinds.value == ["thought", "message"])
    }
}
