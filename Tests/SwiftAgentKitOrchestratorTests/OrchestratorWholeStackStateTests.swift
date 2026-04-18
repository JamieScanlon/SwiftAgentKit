import Foundation
import Logging
import Testing
import SwiftAgentKit
import SwiftAgentKitOrchestrator

/// Shared with ``SwiftAgentKitOrchestratorTests`` helpers in the main orchestrator test file.
fileprivate func drainPublishedMessagesWhileRunning(
    _ messageStream: AsyncStream<Message>,
    operation: () async throws -> Void
) async rethrows {
    let drain = Task {
        for await _ in messageStream {
            if Task.isCancelled { break }
        }
    }
    defer { drain.cancel() }
    try await operation()
    _ = try? await Task.sleep(nanoseconds: 15_000_000)
}

fileprivate func assertSnapshotIdleConsistent(_ snap: OrchestrationSnapshot) {
    #expect(!snap.llmRuntime.isGeneratingTokens)
    #expect(!snap.perRequestStates.values.contains {
        switch $0 {
        case .active, .generating, .streaming: return true
        default: return false
        }
    })
    #expect(!snap.agenticLoopStates.values.contains {
        switch $0 {
        case .started, .llmCall, .betweenIterations: return true
        default: return false
        }
    })
}

@Suite("Orchestrator — whole-stack orchestration snapshots")
struct OrchestratorWholeStackStateTests {
    @Test("currentOrchestrationSnapshot is consistent after streaming updateConversation")
    func testSnapshotAfterStreamingUpdate() async throws {
        let baseLLM = MockLLM(model: "m", logger: Logger(label: "MockLLM"))
        let tracked = StatefulLLM(baseLLM: baseLLM)
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: tracked,
            config: OrchestratorConfig(streamingEnabled: true)
        )
        let messages = [Message(id: UUID(), role: .user, content: "Hi")]
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(messages)
        }
        let snap = await orchestrator.currentOrchestrationSnapshot()
        assertSnapshotIdleConsistent(snap)
    }

    @Test("currentOrchestrationSnapshot is consistent with QueuedLLM(StatefulLLM(MockLLM)) stack")
    func testSnapshotWithQueuedStatefulWrapper() async throws {
        let baseLLM = MockLLM(model: "m", logger: Logger(label: "MockLLM"))
        let tracked = StatefulLLM(baseLLM: baseLLM)
        let queued = QueuedLLM(baseLLM: tracked)
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: queued,
            config: OrchestratorConfig(streamingEnabled: false)
        )
        let messages = [Message(id: UUID(), role: .user, content: "Hello")]
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(messages)
        }
        let snap = await orchestrator.currentOrchestrationSnapshot()
        assertSnapshotIdleConsistent(snap)
    }
}
