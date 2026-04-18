import Foundation
import Logging
import Testing
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitAdapters

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

@Suite("LLMProtocolAdapter — orchestration snapshot integration")
struct AdapterOrchestrationStateIntegrationTests {
    @Test("currentOrchestrationSnapshot has no stale in-flight phases after handleTaskSendWithTools (StatefulLLM + tool loop)")
    func testOrchestrationSnapshotAfterToolLoop() async throws {
        let toolCall = ToolCall(name: "text_tool", arguments: .object([:]), id: UUID().uuidString)
        let base = TestLLMWithToolCalls(model: "adapter-state", toolCalls: [toolCall])
        let llm = StatefulLLM(baseLLM: base)
        let adapter = LLMProtocolAdapter(llm: llm, model: "adapter-state")
        let toolProvider = FileResourceToolProvider(fileResources: [], textContent: "ok")

        let store = TaskStore()
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Run tool")],
            messageId: UUID().uuidString
        )
        let params = MessageSendParams(message: message)
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(state: .submitted)
        )
        await store.addTask(task: task)

        try await adapter.handleTaskSendWithTools(
            params,
            taskId: task.id,
            contextId: task.contextId,
            toolProviders: [toolProvider],
            store: store
        )
        try? await Task.sleep(nanoseconds: 80_000_000)

        let snap = adapter.currentOrchestrationSnapshot()
        assertSnapshotIdleConsistent(snap)
    }

    @Test("currentOrchestrationSnapshot is consistent when adapter uses QueuedLLM(StatefulLLM(base))")
    func testOrchestrationSnapshotWithQueuedStateful() async throws {
        let toolCall = ToolCall(name: "text_tool", arguments: .object([:]), id: UUID().uuidString)
        let base = TestLLMWithToolCalls(model: "queued-adapter", toolCalls: [toolCall])
        let wrapped = QueuedLLM(baseLLM: StatefulLLM(baseLLM: base))
        let adapter = LLMProtocolAdapter(llm: wrapped, model: "queued-adapter")
        let toolProvider = FileResourceToolProvider(fileResources: [], textContent: "done")

        let store = TaskStore()
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Go")],
            messageId: UUID().uuidString
        )
        let params = MessageSendParams(message: message)
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(state: .submitted)
        )
        await store.addTask(task: task)

        try await adapter.handleTaskSendWithTools(
            params,
            taskId: task.id,
            contextId: task.contextId,
            toolProviders: [toolProvider],
            store: store
        )
        try? await Task.sleep(nanoseconds: 80_000_000)

        let snap = adapter.currentOrchestrationSnapshot()
        assertSnapshotIdleConsistent(snap)
    }
}
