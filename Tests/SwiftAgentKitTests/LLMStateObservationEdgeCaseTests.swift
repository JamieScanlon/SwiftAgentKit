import Foundation
import Testing
import SwiftAgentKit

// MARK: - Test doubles

/// Completes the stream immediately without yielding any `StreamResult` (models an empty / malformed upstream).
private struct EmptyFinishingStreamLLM: LLMProtocol {
    func getModelName() -> String { "empty-stream" }
    func getCapabilities() -> [LLMCapability] { [.completion] }
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        .complete(content: "unused")
    }
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

/// `send` sleeps until cancelled (models a hung network call).
private struct SlowSendLLM: LLMProtocol {
    func getModelName() -> String { "slow-send" }
    func getCapabilities() -> [LLMCapability] { [.completion] }
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        try await Task.sleep(for: .seconds(3600))
        return .complete(content: "never")
    }
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// Yields a few stream chunks then **blocks** until the stream’s async iterator is torn down (simulates a long-lived HTTP body).
private struct LongLivedStreamThenHangLLM: LLMProtocol {
    func getModelName() -> String { "long-stream" }
    func getCapabilities() -> [LLMCapability] { [.completion] }
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        .complete(content: "unused")
    }
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.stream(.streamChunk("a")))
                continuation.yield(.stream(.streamChunk("b")))
                // Block until this producer task is cancelled (via StatefulLLM stream teardown).
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }
}

private struct MinimalSyncLLM: LLMProtocol {
    func getModelName() -> String { "minimal" }
    func getCapabilities() -> [LLMCapability] { [.completion] }
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        .complete(content: "ok")
    }
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

// MARK: - Suites

@Suite("LLM state hubs — edge cases")
struct LLMStateHubEdgeCaseTests {
    @Test("Multiple hub subscribers each receive publishes (fan-out)")
    func testHubBroadcastsToAllSubscribers() async {
        let hub = LLMRequestStateHub()
        let id = LLMRequestID()
        let sa = hub.makeStream()
        let sb = hub.makeStream()
        var ia = sa.makeAsyncIterator()
        var ib = sb.makeAsyncIterator()
        async let firstA = ia.next()
        async let firstB = ib.next()
        await Task.yield()
        hub.publish(id, .generating(.reasoning))
        let a = await firstA
        let b = await firstB
        #expect(a?.1 == .generating(.reasoning))
        #expect(b?.1 == .generating(.reasoning))
    }

    @Test("Publishing overwrites prior state for the same request id")
    func testHubLastWriteWinsPerID() {
        let hub = LLMRequestStateHub()
        let id = LLMRequestID()
        hub.publish(id, .generating(.reasoning))
        hub.publish(id, .completed)
        #expect(hub.currentState(for: id) == .completed)
        #expect(hub.currentStates.count == 1)
    }

    @Test("Agentic hub retains completed state until a new publish for the same id")
    func testAgenticHubRetentionUntilOverwrite() {
        let hub = AgenticLoopStateHub()
        let id = AgenticLoopID.orchestratorSession(UUID())
        hub.publish(id, .completed)
        #expect(hub.currentState(for: id) == .completed)
        hub.publish(id, .started)
        #expect(hub.currentState(for: id) == .started)
    }
}

@Suite("OrchestrationSnapshot reconciliation — edge cases")
struct OrchestrationReconciliationEdgeCaseTests {
    @Test("Idle runtime does not rewrite .queued (FIFO wait is still valid while model is idle)")
    func testReconcilePreservesQueuedWhenRuntimeIdle() {
        let rid = LLMRequestID()
        let snap = OrchestrationSnapshot(
            llmRuntime: .idle(.ready),
            perRequestStates: [rid: .queued],
            agenticLoopStates: [:]
        ).reconcilingStaleInFlightPhases()
        #expect(snap.perRequestStates[rid] == .queued)
    }

    @Test("Idle runtime preserves explicit .cancelled per-request state")
    func testReconcilePreservesCancelled() {
        let rid = LLMRequestID()
        let snap = OrchestrationSnapshot(
            llmRuntime: .idle(.ready),
            perRequestStates: [rid: .cancelled],
            agenticLoopStates: [:]
        ).reconcilingStaleInFlightPhases()
        #expect(snap.perRequestStates[rid] == .cancelled)
    }

    @Test("Failed runtime maps stale generating per-request to failed with same message")
    func testReconcileFailedRuntimePropagatesToRequest() {
        let rid = LLMRequestID()
        let snap = OrchestrationSnapshot(
            llmRuntime: .failed("boom"),
            perRequestStates: [rid: .generating(.reasoning)],
            agenticLoopStates: [:]
        ).reconcilingStaleInFlightPhases()
        #expect(snap.perRequestStates[rid] == .failed("boom"))
    }

    @Test("Failed runtime maps stale in-flight agentic to failed when not in tool execution")
    func testReconcileFailedRuntimePropagatesToAgentic() {
        let id = AgenticLoopID.orchestratorSession(UUID())
        let snap = OrchestrationSnapshot(
            llmRuntime: .failed("oops"),
            perRequestStates: [:],
            agenticLoopStates: [id: .llmCall(iteration: 1)]
        ).reconcilingStaleInFlightPhases()
        #expect(snap.agenticLoopStates[id] == .failed("oops"))
    }
}

@Suite("StatefulLLM — cancellation and stream lifecycle")
struct StatefulLLMEdgeCaseTests {
    @Test("Cancelled send publishes per-request .cancelled and returns runtime to idle(.ready)")
    func testSendCancellationPublishesCancelled() async throws {
        let llm = StatefulLLM(baseLLM: SlowSendLLM())
        let rid = LLMRequestID()
        let task = Task {
            try await LLMRequestID.$current.withValue(rid) {
                try await llm.send([], config: LLMRequestConfig())
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(llm.currentState == .idle(.ready))
        #expect(llm.currentRequestState(for: rid) == .cancelled)
    }

    @Test("Stream that finishes without any result leaves runtime idle and request terminal (not stuck generating)")
    func testEmptyUpstreamStreamDoesNotLeaveGenerating() async throws {
        let llm = StatefulLLM(baseLLM: EmptyFinishingStreamLLM())
        let rid = LLMRequestID()
        let stream = LLMRequestID.$current.withValue(rid) {
            llm.stream([], config: LLMRequestConfig(stream: true))
        }
        var iterator = stream.makeAsyncIterator()
        while try await iterator.next() != nil {}
        #expect(llm.currentState == .idle(.ready))
        let terminal = llm.currentRequestState(for: rid)
        switch terminal {
        case .failed, .cancelled, .completed:
            #expect(Bool(true))
        default:
            Issue.record("Expected terminal per-request state after empty stream; got \(String(describing: terminal))")
        }
    }

    @Test("When AsyncThrowingStream consumer is torn down, StatefulLLM cancels work and publishes cancelled")
    func testStreamConsumerDisconnectCancelsWork() async throws {
        let llm = StatefulLLM(baseLLM: LongLivedStreamThenHangLLM())
        let rid = LLMRequestID()
        try await LLMRequestID.$current.withValue(rid) {
            do {
                let stream = llm.stream([], config: LLMRequestConfig(stream: true))
                var iterator = stream.makeAsyncIterator()
                _ = try await iterator.next()
                _ = try await iterator.next()
                // `iterator` deallocates here — should trigger stream termination and cancel the producer task.
            }
            try await Task.sleep(nanoseconds: 350_000_000)
        }
        #expect(llm.currentState == .idle(.ready))
        #expect(llm.currentRequestState(for: rid) == .cancelled)
    }
}

@Suite("OrchestrationObservationCoordinator — subscriber lifecycle")
struct OrchestrationCoordinatorLifecycleTests {
    @Test("currentSnapshot works with zero snapshot subscribers (no merge task required)")
    func testSnapshotWithoutSubscribers() {
        let llm = StatefulLLM(baseLLM: MinimalSyncLLM())
        let hub = AgenticLoopStateHub()
        let coord = OrchestrationObservationCoordinator(llm: llm, agenticLoopStateHub: hub)
        hub.publish(AgenticLoopID.orchestratorSession(UUID()), .started)
        let snap = coord.currentSnapshot()
        #expect(snap.agenticLoopStates.count >= 1)
    }

    @Test("Subscribing after all prior subscribers terminated still receives new events")
    func testResubscribeAfterDrain() async throws {
        let llm = StatefulLLM(baseLLM: MinimalSyncLLM())
        let hub = AgenticLoopStateHub()
        let coord = OrchestrationObservationCoordinator(llm: llm, agenticLoopStateHub: hub)
        let loopID = AgenticLoopID.orchestratorSession(UUID())

        var firstGen: UInt64 = 0
        do {
            let stream = coord.snapshotUpdates()
            var it = stream.makeAsyncIterator()
            _ = await it.next()
            hub.publish(loopID, .completed)
            if let ev = await it.next() { firstGen = ev.generation }
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        let stream2 = coord.snapshotUpdates()
        var it2 = stream2.makeAsyncIterator()
        _ = await it2.next()
        try await Task.sleep(nanoseconds: 50_000_000)
        hub.publish(loopID, .failed("x"))
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(coord.currentSnapshot().agenticLoopStates[loopID] == .failed("x"))
        var sawFailedPush: OrchestrationSnapshotEvent?
        for _ in 0..<12 {
            guard let ev = await it2.next() else { break }
            if ev.snapshot.agenticLoopStates[loopID] == .failed("x") {
                sawFailedPush = ev
                break
            }
        }
        guard let ev2 = sawFailedPush else {
            Issue.record("Push stream never surfaced agentic .failed after resubscribe")
            return
        }
        #expect(ev2.generation > firstGen)
    }
}
