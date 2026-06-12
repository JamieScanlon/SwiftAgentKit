//
//  ACPManagerTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import Testing
import SwiftAgentKit
@testable import SwiftAgentKitACP

private actor MockACPStreamClient: ACPAgentStreamClient {
    let info: ACPImplementation
    let responseText: String
    private(set) var didShutdown = false
    let timeout: TimeInterval?

    init(name: String, responseText: String, timeout: TimeInterval? = nil) {
        self.info = ACPImplementation(name: name, version: "1.0.0")
        self.responseText = responseText
        self.timeout = timeout
    }

    var agentInfo: ACPImplementation? { info }

    var toolCallTimeout: TimeInterval? { timeout }

    func promptStream(_ instructions: String) async throws -> (ACPPromptResponse, AsyncStream<ACPSessionUpdate>) {
        let stream = AsyncStream<ACPSessionUpdate> { continuation in
            continuation.yield(.agentMessageChunk(messageId: "1", content: .text("\(responseText): \(instructions)")))
            continuation.finish()
        }
        return (ACPPromptResponse(stopReason: .endTurn), stream)
    }

    func shutdown() async { didShutdown = true }
}

@Suite("ACP Manager")
struct ACPManagerTests {
    @Test("Agent call dispatches to matching client")
    func agentCall() async throws {
        let manager = ACPManager()
        let mock = MockACPStreamClient(name: "mock-agent", responseText: "Result")
        try await manager.initialize(clients: [mock])

        let toolCall = ToolCall(
            name: "mock-agent",
            arguments: .object(["instructions": .string("do work")]),
            id: "call-1"
        )
        let responses = try await manager.agentCall(toolCall)
        #expect(responses?.count == 1)
        #expect(responses?.first?.content.contains("Result") == true)
    }

    @Test("Agent call returns nil for unknown agent")
    func unknownAgent() async throws {
        let manager = ACPManager()
        try await manager.initialize(clients: [MockACPStreamClient(name: "known", responseText: "")])

        let toolCall = ToolCall(
            name: "unknown",
            arguments: .object(["instructions": .string("x")]),
            id: "call-2"
        )
        let responses = try await manager.agentCall(toolCall)
        #expect(responses == nil)
    }

    @Test("Agent call returns nil without instructions argument")
    func missingInstructions() async throws {
        let manager = ACPManager()
        try await manager.initialize(clients: [MockACPStreamClient(name: "mock-agent", responseText: "")])

        let toolCall = ToolCall(name: "mock-agent", arguments: .object([:]), id: "call-3")
        let responses = try await manager.agentCall(toolCall)
        #expect(responses == nil)
    }

    @Test("Available tools from clients")
    func availableTools() async throws {
        let manager = ACPManager()
        try await manager.initialize(clients: [MockACPStreamClient(name: "agent-a", responseText: "")])
        let tools = await manager.availableTools()
        #expect(tools.count == 1)
        #expect(tools[0].name == "agent-a")
        #expect(tools[0].type == .acpAgent)
    }

    @Test("Registered tool descriptors")
    func registeredDescriptors() async throws {
        let manager = ACPManager()
        try await manager.initialize(clients: [MockACPStreamClient(name: "agent-b", responseText: "")])
        let descriptors = await manager.registeredToolDescriptors()
        #expect(descriptors.count == 1)
        #expect(descriptors[0].source == .acp)
        #expect(descriptors[0].definition.name == "agent-b")
    }

    @Test("Initialize sets state and tools JSON")
    func initializeState() async throws {
        let manager = ACPManager()
        try await manager.initialize(clients: [MockACPStreamClient(name: "agent-c", responseText: "")])
        #expect(await manager.state == .initialized)
        let tools = await manager.availableTools()
        #expect(tools.count == 1)
        #expect(await manager.toolCallsJsonString?.contains("agent-c") == true)
    }

    @Test("Shutdown resets state and shuts down clients")
    func shutdown() async throws {
        let manager = ACPManager()
        let mock = MockACPStreamClient(name: "agent-d", responseText: "")
        try await manager.initialize(clients: [mock])
        await manager.shutdown()
        #expect(await manager.state == .notReady)
        #expect(await mock.didShutdown == true)
    }

    @Test("Empty prompt response uses stop reason fallback text")
    func emptyStreamFallback() async throws {
        struct SilentClient: ACPAgentStreamClient {
            var agentInfo: ACPImplementation? { ACPImplementation(name: "silent", version: "1.0.0") }
            func promptStream(_ instructions: String) async throws -> (ACPPromptResponse, AsyncStream<ACPSessionUpdate>) {
                (ACPPromptResponse(stopReason: .endTurn), AsyncStream { $0.finish() })
            }
            func shutdown() async {}
        }

        let manager = ACPManager()
        try await manager.initialize(clients: [SilentClient()])
        let toolCall = ToolCall(
            name: "silent",
            arguments: .object(["instructions": .string("go")]),
            id: "call-4"
        )
        let responses = try await manager.agentCall(toolCall)
        #expect(responses?.first?.content.contains("end_turn") == true)
    }
}
