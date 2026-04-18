import Foundation
import Testing
import SwiftAgentKit

// MARK: - Local test doubles

private struct SlowSendNoStateLLM: LLMProtocol {
    func getModelName() -> String { "raw-slow" }
    func getCapabilities() -> [LLMCapability] { [.completion] }
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        try await Task.sleep(for: .seconds(3600))
        return .complete(content: "no")
    }
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private struct SlowGenerateImageLLM: LLMProtocol {
    func getModelName() -> String { "img-slow" }
    func getCapabilities() -> [LLMCapability] { [.completion, .imageGeneration] }
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        .complete(content: "x")
    }
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func generateImage(_ config: ImageGenerationRequestConfig) async throws -> ImageGenerationResponse {
        try await Task.sleep(for: .seconds(3600))
        return ImageGenerationResponse(images: [URL(fileURLWithPath: "/tmp/x.png")])
    }
}

private struct TinyOKLLM: LLMProtocol {
    func getModelName() -> String { "tiny" }
    func getCapabilities() -> [LLMCapability] { [.completion] }
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        .complete(content: "ok")
    }
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

// MARK: - Assertions

private func assertOrchestrationSnapshotIdleConsistent(_ snap: OrchestrationSnapshot) {
    #expect(!snap.llmRuntime.isGeneratingTokens)
    let badReq = snap.perRequestStates.values.contains {
        switch $0 {
        case .active, .generating, .streaming: return true
        default: return false
        }
    }
    #expect(!badReq)
    let badLoop = snap.agenticLoopStates.values.contains {
        switch $0 {
        case .started, .llmCall, .betweenIterations: return true
        default: return false
        }
    }
    #expect(!badLoop)
}

// MARK: - Suites

@Suite("Whole-stack state — QueuedLLM + raw base")
struct QueuedLLMRawBaseStateTests {
    @Test("QueuedLLM over a non-StatefulLLM maps cancelled send to per-request .cancelled")
    func testQueuedRawSendCancellation() async throws {
        let queued = QueuedLLM(baseLLM: SlowSendNoStateLLM())
        let task = Task {
            try await queued.send([], config: LLMRequestConfig())
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        let terminals = queued.currentRequestStates.values.filter { $0 == .cancelled }
        #expect(terminals.count >= 1)
    }
}

@Suite("Whole-stack state — StatefulLLM generateImage")
struct StatefulLLMGenerateImageStateTests {
    @Test("Cancelled generateImage publishes .cancelled and idles runtime")
    func testGenerateImageCancellation() async throws {
        let llm = StatefulLLM(baseLLM: SlowGenerateImageLLM())
        let rid = LLMRequestID()
        let task = Task {
            try await LLMRequestID.$current.withValue(rid) {
                try await llm.generateImage(ImageGenerationRequestConfig(prompt: "x"))
            }
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(llm.currentState == .idle(.ready))
        #expect(llm.currentRequestState(for: rid) == .cancelled)
    }
}

@Suite("Whole-stack state — QueuedLLM(StatefulLLM) + orchestration snapshot")
struct QueuedStatefulOrchestrationSnapshotTests {
    @Test("OrchestrationObservationCoordinator snapshot is idle-consistent for QueuedLLM wrapping StatefulLLM")
    func testCoordinatorSnapshotWithQueuedStateful() {
        let inner = StatefulLLM(baseLLM: TinyOKLLM())
        let queued = QueuedLLM(baseLLM: inner)
        let hub = AgenticLoopStateHub()
        let coord = OrchestrationObservationCoordinator(llm: queued, agenticLoopStateHub: hub)
        let loop = AgenticLoopID.orchestratorSession(UUID())
        hub.publish(loop, .completed)
        let snap = coord.currentSnapshot()
        assertOrchestrationSnapshotIdleConsistent(snap)
        #expect(snap.agenticLoopStates[loop] == .completed)
    }
}
