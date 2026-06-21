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
    private let updatesToYield: [ACPSessionUpdate]
    private let stopReason: ACPStopReason
    private let hangsAfterUpdates: Bool
    private let shouldFail: Bool
    private(set) var didShutdown = false
    let timeout: TimeInterval?
    let mockSessionId: String?

    init(
        name: String,
        responseText: String = "",
        updates: [ACPSessionUpdate]? = nil,
        stopReason: ACPStopReason = .endTurn,
        hangsAfterUpdates: Bool = false,
        shouldFail: Bool = false,
        timeout: TimeInterval? = nil,
        sessionId: String? = nil
    ) {
        self.info = ACPImplementation(name: name, version: "1.0.0")
        self.stopReason = stopReason
        self.hangsAfterUpdates = hangsAfterUpdates
        self.shouldFail = shouldFail
        self.timeout = timeout
        self.mockSessionId = sessionId
        if let updates {
            self.updatesToYield = updates
        } else if !responseText.isEmpty {
            self.updatesToYield = [.agentMessageChunk(messageId: "1", content: .text(responseText))]
        } else {
            self.updatesToYield = []
        }
    }

    var agentInfo: ACPImplementation? { info }
    var sessionId: String? { mockSessionId }
    var toolCallTimeout: TimeInterval? { timeout }

    func promptStream(_ instructions: String) async throws -> (
        updates: AsyncStream<ACPSessionUpdate>,
        response: Task<ACPPromptResponse, Error>
    ) {
        let updatesToYield = self.updatesToYield
        let hangsAfterUpdates = self.hangsAfterUpdates
        let shouldFail = self.shouldFail
        let stopReason = self.stopReason

        let updates = AsyncStream<ACPSessionUpdate> { continuation in
            let producer = Task {
                if hangsAfterUpdates {
                    for update in updatesToYield {
                        continuation.yield(update)
                    }
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                    continuation.finish()
                } else {
                    for update in updatesToYield {
                        continuation.yield(update)
                    }
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable _ in
                producer.cancel()
            }
        }

        let response = Task<ACPPromptResponse, Error> {
            if hangsAfterUpdates {
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                throw CancellationError()
            }
            if shouldFail {
                throw ACPClient.ACPClientError.noSession
            }
            return ACPPromptResponse(stopReason: stopReason)
        }

        return (updates, response)
    }

    func shutdown() async { didShutdown = true }
}

private actor MockCancellableACPStreamClient: ACPPromptLifecycleClient {
    let info: ACPImplementation
    private let initialUpdates: [ACPSessionUpdate]
    private(set) var cancelPromptCallCount = 0
    let mockSessionId: String

    init(name: String, sessionId: String, initialUpdates: [ACPSessionUpdate] = []) {
        self.info = ACPImplementation(name: name, version: "1.0.0")
        self.mockSessionId = sessionId
        self.initialUpdates = initialUpdates
    }

    var agentInfo: ACPImplementation? { info }
    var sessionId: String? { mockSessionId }
    var toolCallTimeout: TimeInterval? { nil }

    func promptStream(_ instructions: String) async throws -> (
        updates: AsyncStream<ACPSessionUpdate>,
        response: Task<ACPPromptResponse, Error>
    ) {
        let initialUpdates = self.initialUpdates
        let updates = AsyncStream<ACPSessionUpdate> { continuation in
            let producer = Task {
                for update in initialUpdates {
                    continuation.yield(update)
                }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                producer.cancel()
            }
        }

        let response = Task<ACPPromptResponse, Error> {
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            throw CancellationError()
        }

        return (updates, response)
    }

    func cancelPrompt() async throws {
        cancelPromptCallCount += 1
    }

    func shutdown() async {}
}

@Suite("ACP Manager")
struct ACPManagerTests {
    private func createToolCall(name: String, instructions: String, id: String? = nil) -> ToolCall {
        ToolCall(
            name: name,
            arguments: .object(["instructions": .string(instructions)]),
            id: id
        )
    }

    private func collectEvents(from stream: AsyncStream<ACPDelegateStreamEvent>) async -> [ACPDelegateStreamEvent] {
        var events: [ACPDelegateStreamEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    @Test("Agent call dispatches to matching client")
    func agentCall() async throws {
        let manager = ACPManager()
        let mock = MockACPStreamClient(name: "mock-agent", responseText: "Result")
        try await manager.initialize(clients: [mock])

        let toolCall = createToolCall(name: "mock-agent", instructions: "do work", id: "call-1")
        let responses = try await manager.agentCall(toolCall)
        #expect(responses?.count == 1)
        #expect(responses?.first?.content.contains("Result") == true)
    }

    @Test("Agent call returns nil for unknown agent")
    func unknownAgent() async throws {
        let manager = ACPManager()
        try await manager.initialize(clients: [MockACPStreamClient(name: "known")])

        let toolCall = createToolCall(name: "unknown", instructions: "x", id: "call-2")
        let responses = try await manager.agentCall(toolCall)
        #expect(responses == nil)
    }

    @Test("Agent call returns nil without instructions argument")
    func missingInstructions() async throws {
        let manager = ACPManager()
        try await manager.initialize(clients: [MockACPStreamClient(name: "mock-agent")])

        let toolCall = ToolCall(name: "mock-agent", arguments: .object([:]), id: "call-3")
        let responses = try await manager.agentCall(toolCall)
        #expect(responses == nil)
    }

    @Test("Available tools from clients")
    func availableTools() async throws {
        let manager = ACPManager()
        try await manager.initialize(clients: [MockACPStreamClient(name: "agent-a")])
        let tools = await manager.availableTools()
        #expect(tools.count == 1)
        #expect(tools[0].name == "agent-a")
        #expect(tools[0].type == .acpAgent)
    }

    @Test("Registered tool descriptors")
    func registeredDescriptors() async throws {
        let manager = ACPManager()
        try await manager.initialize(clients: [MockACPStreamClient(name: "agent-b")])
        let descriptors = await manager.registeredToolDescriptors()
        #expect(descriptors.count == 1)
        #expect(descriptors[0].source == .acp)
        #expect(descriptors[0].definition.name == "agent-b")
    }

    @Test("Initialize sets state and tools JSON")
    func initializeState() async throws {
        let manager = ACPManager()
        try await manager.initialize(clients: [MockACPStreamClient(name: "agent-c")])
        #expect(await manager.state == .initialized)
        let tools = await manager.availableTools()
        #expect(tools.count == 1)
        #expect(await manager.toolCallsJsonString?.contains("agent-c") == true)
    }

    @Test("Shutdown resets state and shuts down clients")
    func shutdown() async throws {
        let manager = ACPManager()
        let mock = MockACPStreamClient(name: "agent-d")
        try await manager.initialize(clients: [mock])
        await manager.shutdown()
        #expect(await manager.state == .notReady)
        #expect(await mock.didShutdown == true)
    }

    @Test("Empty prompt response uses stop reason fallback text")
    func emptyStreamFallback() async throws {
        let manager = ACPManager()
        try await manager.initialize(clients: [MockACPStreamClient(name: "silent", updates: [])])
        let toolCall = createToolCall(name: "silent", instructions: "go", id: "call-4")
        let responses = try await manager.agentCall(toolCall)
        #expect(responses?.first?.content.contains("end_turn") == true)
    }

    // MARK: - streamAgentCall() Tests

    @Test("streamAgentCall excludes thought chunks from completed content")
    func testStreamAgentCallExcludesThoughtFromCompleted() async throws {
        let agentName = "ThoughtAgent"
        let updates: [ACPSessionUpdate] = [
            .agentThoughtChunk(messageId: "t1", content: .text("secret reasoning")),
            .agentMessageChunk(messageId: "m1", content: .text("visible answer"))
        ]

        let manager = ACPManager()
        let mock = MockACPStreamClient(name: agentName, updates: updates, sessionId: "s1")
        try await manager.initialize(clients: [mock])

        let toolCall = createToolCall(name: agentName, instructions: "think", id: "tool-call-thought")
        let (_, events) = try await manager.streamAgentCall(toolCall, invocationID: UUID().uuidString)
        let collected = await collectEvents(from: events)

        let thoughtEvents = collected.compactMap { event -> String? in
            if case .thoughtChunk(_, let text) = event { return text }
            return nil
        }
        #expect(thoughtEvents == ["secret reasoning"])

        let terminalEvents = collected.filter {
            if case .completed = $0 { return true }
            return false
        }
        #expect(terminalEvents.count == 1)
        if case .completed(let content, _, _) = terminalEvents[0] {
            #expect(content == "visible answer")
            #expect(!content.contains("secret reasoning"))
        } else {
            Issue.record("Expected completed terminal event")
        }
    }

    @Test("streamAgentCall emits expected event sequence")
    func testStreamAgentCallEventSequence() async throws {
        let agentName = "StreamAgent"
        let sessionID = "session-stream-1"
        let updates: [ACPSessionUpdate] = [
            .agentMessageChunk(messageId: "m1", content: .text("Hello ")),
            .plan(entries: [ACPPlanEntry(content: "Step 1", priority: "high", status: "pending")]),
            .toolCall(ACPToolCallUpdate(toolCallId: "tc-1", title: "Run", kind: .execute, status: .pending)),
            .toolCallUpdate(ACPToolCallUpdate(toolCallId: "tc-1", status: .inProgress, content: [.content(.text("working"))])),
            .agentMessageChunk(messageId: "m2", content: .text("world"))
        ]

        let manager = ACPManager()
        let mock = MockACPStreamClient(name: agentName, updates: updates, sessionId: sessionID)
        try await manager.initialize(clients: [mock])

        let invocationID = UUID().uuidString
        let toolCall = createToolCall(name: agentName, instructions: "Stream", id: "tool-call-1")
        let (handle, events) = try await manager.streamAgentCall(toolCall, invocationID: invocationID)
        let collected = await collectEvents(from: events)

        #expect(handle.invocationID == invocationID)
        #expect(handle.toolCallID == "tool-call-1")
        #expect(handle.agentName == agentName)

        #expect(collected.count >= 6)

        if case .connecting(let name) = collected[0] {
            #expect(name == agentName)
        } else {
            Issue.record("Expected connecting as first event")
        }

        if case .messageChunk(let text) = collected[1] {
            #expect(text == "Hello ")
        } else {
            Issue.record("Expected messageChunk as second event")
        }

        if case .plan(let entries) = collected[2] {
            #expect(entries.count == 1)
            #expect(entries[0].content == "Step 1")
        } else {
            Issue.record("Expected plan as third event")
        }

        if case .toolCall(let toolCall) = collected[3] {
            #expect(toolCall.toolCallId == "tc-1")
            #expect(toolCall.title == "Run")
        } else {
            Issue.record("Expected toolCall as fourth event")
        }

        if case .toolCallUpdate(let toolCall) = collected[4] {
            #expect(toolCall.toolCallId == "tc-1")
            #expect(toolCall.status == .inProgress)
        } else {
            Issue.record("Expected toolCallUpdate as fifth event")
        }

        let terminalEvents = collected.filter {
            if case .completed = $0 { return true }
            if case .failed = $0 { return true }
            return false
        }
        #expect(terminalEvents.count == 1)
        if case .completed(let content, let stopReason, let sid) = terminalEvents[0] {
            #expect(content == "Hello world")
            #expect(stopReason == .endTurn)
            #expect(sid == sessionID)
        } else {
            Issue.record("Expected completed terminal event")
        }
    }

    @Test("streamAgentCall emits failed terminal event on prompt failure")
    func testStreamAgentCallTerminalFailure() async throws {
        let manager = ACPManager()
        let mock = MockACPStreamClient(name: "FailAgent", shouldFail: true)
        try await manager.initialize(clients: [mock])

        let toolCall = createToolCall(name: "FailAgent", instructions: "fail", id: "tool-call-fail")
        let (_, events) = try await manager.streamAgentCall(toolCall, invocationID: UUID().uuidString)
        let collected = await collectEvents(from: events)

        let terminalEvents = collected.filter {
            if case .failed = $0 { return true }
            return false
        }
        #expect(terminalEvents.count == 1)
        if case .failed(let error, _) = terminalEvents[0] {
            #expect(!error.isEmpty)
        } else {
            Issue.record("Expected failed terminal event")
        }
    }

    @Test("streamAgentCall throws agentNotFound for unknown agent")
    func testStreamAgentCallThrowsAgentNotFound() async throws {
        let manager = ACPManager()
        try await manager.initialize(clients: [MockACPStreamClient(name: "KnownAgent")])

        let toolCall = createToolCall(name: "MissingAgent", instructions: "x", id: "tool-call-missing")
        await #expect(throws: ACPManagerError.agentNotFound("MissingAgent")) {
            _ = try await manager.streamAgentCall(toolCall, invocationID: UUID().uuidString)
        }
    }

    @Test("streamAgentCall throws invalidArguments for bad tool call args")
    func testStreamAgentCallThrowsInvalidArguments() async throws {
        let manager = ACPManager()
        try await manager.initialize(clients: [MockACPStreamClient(name: "AgentA")])

        let toolCall = ToolCall(name: "AgentA", arguments: .object([:]), id: "tool-call-bad")
        await #expect(throws: ACPManagerError.invalidArguments) {
            _ = try await manager.streamAgentCall(toolCall, invocationID: UUID().uuidString)
        }
    }

    @Test("agentCall and streamAgentCall produce equivalent responses for multi-chunk stream")
    func testAgentCallMatchesStreamAgentCallForMultiChunk() async throws {
        let agentName = "ChunkAgent"
        let updates: [ACPSessionUpdate] = [
            .agentMessageChunk(messageId: "1", content: .text("Part1 ")),
            .agentMessageChunk(messageId: "2", content: .text("Part2"))
        ]

        let managerDirect = ACPManager()
        let managerStream = ACPManager()
        let mockDirect = MockACPStreamClient(name: agentName, updates: updates)
        let mockStream = MockACPStreamClient(name: agentName, updates: updates)
        try await managerDirect.initialize(clients: [mockDirect])
        try await managerStream.initialize(clients: [mockStream])

        let toolCall = createToolCall(name: agentName, instructions: "Chunk", id: UUID().uuidString)

        let directResponses = try await managerDirect.agentCall(toolCall)
        let (_, stream) = try await managerStream.streamAgentCall(toolCall, invocationID: UUID().uuidString)
        var streamResponses: [LLMResponse] = []
        for await event in stream {
            if case .messageChunk(let text) = event {
                streamResponses.append(LLMResponse.complete(content: text))
            }
            if case .completed(let content, _, _) = event {
                streamResponses = [LLMResponse.complete(content: content)]
            }
        }

        #expect(directResponses?.last?.content == streamResponses.last?.content)
        #expect(directResponses?.last?.content == "Part1 Part2")
    }

    // MARK: - cancelAgentCall() Tests

    @Test("cancelAgentCall by invocationID cancels stream and remote prompt")
    func testCancelAgentCallByInvocationID() async throws {
        let sessionID = "session-cancel-invocation"
        let manager = ACPManager()
        let mock = MockCancellableACPStreamClient(name: "CancelAgent", sessionId: sessionID)
        try await manager.initialize(clients: [mock])

        let invocationID = UUID().uuidString
        let toolCall = createToolCall(name: "CancelAgent", instructions: "hang", id: "tool-call-cancel-1")
        let (_, events) = try await manager.streamAgentCall(toolCall, invocationID: invocationID)

        let collectTask = Task { await collectEvents(from: events) }
        try await Task.sleep(nanoseconds: 100_000_000)

        let cancelled = await manager.cancelAgentCall(invocationID: invocationID)
        #expect(cancelled == true)

        let collected = await collectTask.value
        let failedEvents = collected.filter {
            if case .failed = $0 { return true }
            return false
        }
        #expect(failedEvents.count == 1)
        if case .failed(let error, _) = failedEvents[0] {
            #expect(error == "Cancelled")
        } else {
            Issue.record("Expected failed(Cancelled)")
        }
        #expect(await mock.cancelPromptCallCount == 1)
        #expect(await manager.cancelAgentCall(invocationID: invocationID) == false)
    }

    @Test("cancelAgentCall by toolCallID cancels in-flight stream")
    func testCancelAgentCallByToolCallID() async throws {
        let sessionID = "session-cancel-tool-call"
        let manager = ACPManager()
        let mock = MockCancellableACPStreamClient(name: "CancelAgent", sessionId: sessionID)
        try await manager.initialize(clients: [mock])

        let toolCallID = "tool-call-cancel-2"
        let toolCall = createToolCall(name: "CancelAgent", instructions: "hang", id: toolCallID)
        let (_, events) = try await manager.streamAgentCall(toolCall, invocationID: UUID().uuidString)

        let collectTask = Task { await collectEvents(from: events) }
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(await manager.cancelAgentCall(toolCallID: toolCallID) == true)
        _ = await collectTask.value
        #expect(await mock.cancelPromptCallCount == 1)
    }

    @Test("cancelAgentCall by sessionID cancels in-flight stream")
    func testCancelAgentCallBySessionID() async throws {
        let sessionID = "session-cancel-by-session"
        let manager = ACPManager()
        let mock = MockCancellableACPStreamClient(name: "CancelAgent", sessionId: sessionID)
        try await manager.initialize(clients: [mock])

        let toolCall = createToolCall(name: "CancelAgent", instructions: "hang", id: "tool-call-cancel-3")
        let (_, events) = try await manager.streamAgentCall(toolCall, invocationID: UUID().uuidString)

        let collectTask = Task { await collectEvents(from: events) }
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(await manager.cancelAgentCall(sessionID: sessionID) == true)
        _ = await collectTask.value
        #expect(await mock.cancelPromptCallCount == 1)
    }

    @Test("cancelAgentCall returns false for unknown invocation")
    func testCancelAgentCallUnknownID() async throws {
        let manager = ACPManager()
        try await manager.initialize(clients: [MockACPStreamClient(name: "AgentA")])
        #expect(await manager.cancelAgentCall(invocationID: "missing") == false)
    }

    @Test("cancelAgentCall returns false after stream completes")
    func testCancelAgentCallAfterCompletion() async throws {
        let manager = ACPManager()
        let mock = MockACPStreamClient(name: "CompleteAgent", responseText: "done")
        try await manager.initialize(clients: [mock])

        let invocationID = "complete-invocation"
        let toolCall = createToolCall(name: "CompleteAgent", instructions: "go", id: "complete-tool-call")
        let (_, events) = try await manager.streamAgentCall(toolCall, invocationID: invocationID)
        _ = await collectEvents(from: events)

        #expect(await manager.cancelAgentCall(invocationID: invocationID) == false)
        #expect(await manager.cancelAgentCall(toolCallID: "complete-tool-call") == false)
    }

    @Test("cancelAgentCall cancels local stream only when client lacks ACPPromptLifecycleClient")
    func testCancelAgentCallLocalOnlyWithoutLifecycleClient() async throws {
        let sessionID = "session-local-only"
        let manager = ACPManager()
        let mock = MockACPStreamClient(
            name: "LocalCancelAgent",
            responseText: "partial",
            hangsAfterUpdates: true,
            sessionId: sessionID
        )
        try await manager.initialize(clients: [mock])

        let toolCallID = "tool-call-local-cancel"
        let toolCall = createToolCall(name: "LocalCancelAgent", instructions: "hang", id: toolCallID)
        let (_, events) = try await manager.streamAgentCall(toolCall, invocationID: UUID().uuidString)

        let collectTask = Task { await collectEvents(from: events) }
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(await manager.cancelAgentCall(toolCallID: toolCallID) == true)

        let collected = await collectTask.value
        let failedEvents = collected.filter {
            if case .failed = $0 { return true }
            return false
        }
        #expect(failedEvents.count == 1)
        if case .failed(let error, _) = failedEvents[0] {
            #expect(error == "Cancelled")
        } else {
            Issue.record("Expected failed(Cancelled)")
        }
    }
}
