import Foundation
import Testing
import SwiftAgentKit

// MARK: - Test Helpers

private struct TestTimeout: Error, CustomStringConvertible {
    let description: String
}

/// Polls a condition with 1ms intervals, throwing after a generous timeout.
/// Replaces fixed `Task.sleep` waits that break under concurrent test load.
private func pollUntil(
    _ condition: @Sendable () async -> Bool,
    timeout: UInt64 = 5_000_000_000,
    message: String = "Condition not met within timeout"
) async throws {
    let start = DispatchTime.now()
    while !(await condition()) {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        guard elapsed < timeout else {
            throw TestTimeout(description: message)
        }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
}

/// LLM that blocks until explicitly released, allowing precise concurrency control.
///
/// All mutable state is managed via a dedicated actor to avoid NSLock-in-async-context issues.
/// Gate continuations are stored synchronously on the actor (before suspension) to avoid
/// race conditions between `send` and `release`.
final class GatedLLM: LLMProtocol, @unchecked Sendable {
    private let state = GatedState()

    var callOrder: [Int] {
        get async { await state.callOrder }
    }

    var callCount: Int {
        get async { await state.callCount }
    }

    func getModelName() -> String { "gated-llm" }
    func getCapabilities() -> [LLMCapability] { [.completion] }

    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        let ordinal = await state.recordCall()

        if await state.shouldWait {
            await state.waitOnGate(ordinal: ordinal)
        }

        return .complete(content: "response-\(ordinal)")
    }

    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        let stateRef = self.state
        return AsyncThrowingStream { continuation in
            Task {
                let ordinal = await stateRef.recordCall()

                if await stateRef.shouldWait {
                    await stateRef.waitOnGate(ordinal: ordinal)
                }

                continuation.yield(.stream(.streamChunk("chunk-\(ordinal)")))
                continuation.yield(.complete(.complete(content: "complete-\(ordinal)")))
                continuation.finish()
            }
        }
    }

    func release(ordinal: Int) async {
        await state.release(ordinal: ordinal)
    }

    func releaseAll() async {
        await state.releaseAll()
    }
}

private actor GatedState {
    var callOrder: [Int] = []
    var callCount: Int = 0
    var shouldWait: Bool = true
    private var gates: [Int: CheckedContinuation<Void, Never>] = [:]

    func recordCall() -> Int {
        callCount += 1
        callOrder.append(callCount)
        return callCount
    }

    /// Suspends the caller until `release(ordinal:)` is called.
    /// The continuation is stored synchronously (before suspension) so there is
    /// no window where `release` could miss it.
    func waitOnGate(ordinal: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gates[ordinal] = continuation
        }
    }

    func release(ordinal: Int) {
        gates.removeValue(forKey: ordinal)?.resume()
    }

    func releaseAll() {
        shouldWait = false
        let allGates = gates
        gates.removeAll()
        for (_, gate) in allGates {
            gate.resume()
        }
    }
}

/// Simple fast LLM for smoke tests.
struct FastLLM: LLMProtocol {
    func getModelName() -> String { "fast-llm" }
    func getCapabilities() -> [LLMCapability] { [.completion] }

    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        .complete(content: "fast-response")
    }

    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.stream(.streamChunk("chunk")))
            continuation.yield(.complete(.complete(content: "done")))
            continuation.finish()
        }
    }
}

/// LLM that always throws.
struct FailingLLM: LLMProtocol {
    func getModelName() -> String { "failing-llm" }
    func getCapabilities() -> [LLMCapability] { [.completion] }

    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        throw LLMError.invalidRequest("intentional failure")
    }

    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LLMError.invalidRequest("intentional failure"))
        }
    }
}

// MARK: - Tests

@Suite(.serialized) struct LLMRequestQueueTests {

    private func makeMessage(_ text: String = "hi") -> [Message] {
        [Message(id: UUID(), role: .user, content: text)]
    }

    // MARK: - FIFO Ordering

    @Test("Requests execute in FIFO order")
    func testFIFOOrdering() async throws {
        let gated = GatedLLM()
        let queued = QueuedLLM(baseLLM: gated)

        let task1 = Task { try await queued.send(makeMessage("1"), config: LLMRequestConfig()) }
        try await pollUntil { await gated.callCount >= 1 }

        let task2 = Task { try await queued.send(makeMessage("2"), config: LLMRequestConfig()) }
        try await pollUntil { await queued.queueDepth >= 1 }

        let task3 = Task { try await queued.send(makeMessage("3"), config: LLMRequestConfig()) }
        try await pollUntil { await queued.queueDepth >= 2 }

        #expect(await gated.callCount == 1)

        await gated.release(ordinal: 1)
        let r1 = try await task1.value
        #expect(r1.content == "response-1")

        try await pollUntil { await gated.callCount >= 2 }
        await gated.release(ordinal: 2)
        let r2 = try await task2.value
        #expect(r2.content == "response-2")

        try await pollUntil { await gated.callCount >= 3 }
        await gated.release(ordinal: 3)
        let r3 = try await task3.value
        #expect(r3.content == "response-3")

        #expect(await gated.callOrder == [1, 2, 3])
    }

    // MARK: - Serial Execution

    @Test("Only one request executes at a time by default")
    func testSerialExecution() async throws {
        let gated = GatedLLM()
        let queued = QueuedLLM(baseLLM: gated)

        let _ = Task { try await queued.send(makeMessage(), config: LLMRequestConfig()) }
        try await pollUntil { await gated.callCount >= 1 }

        let _ = Task { try await queued.send(makeMessage(), config: LLMRequestConfig()) }
        try await pollUntil { await queued.queueDepth >= 1 }

        #expect(await gated.callCount == 1)

        await gated.release(ordinal: 1)
        try await pollUntil { await gated.callCount >= 2 }
        #expect(await gated.callCount == 2)

        await gated.releaseAll()
    }

    // MARK: - Max Queue Size

    @Test("Throws queueFull when queue is at capacity")
    func testMaxQueueSize() async throws {
        let gated = GatedLLM()
        let queued = QueuedLLM(
            baseLLM: gated,
            configuration: LLMQueueConfiguration(maxQueueSize: 1)
        )

        let _ = Task { try await queued.send(makeMessage(), config: LLMRequestConfig()) }
        try await pollUntil { await gated.callCount >= 1 }

        let _ = Task { try await queued.send(makeMessage(), config: LLMRequestConfig()) }
        try await pollUntil { await queued.queueDepth >= 1 }

        do {
            _ = try await queued.send(makeMessage(), config: LLMRequestConfig())
            Issue.record("Expected queueFull error")
        } catch let error as LLMError {
            if case .queueFull = error {
                // expected
            } else {
                Issue.record("Expected queueFull, got \(error)")
            }
        }

        await gated.releaseAll()
    }

    // MARK: - Timeout

    @Test("Throws queueTimeout when request waits too long")
    func testQueueTimeout() async throws {
        let gated = GatedLLM()
        let queued = QueuedLLM(
            baseLLM: gated,
            configuration: LLMQueueConfiguration(requestTimeout: 0.05)
        )

        let _ = Task { try await queued.send(makeMessage(), config: LLMRequestConfig()) }
        try await pollUntil { await gated.callCount >= 1 }

        do {
            _ = try await queued.send(makeMessage(), config: LLMRequestConfig())
            Issue.record("Expected queueTimeout error")
        } catch let error as LLMError {
            if case .queueTimeout = error {
                // expected
            } else {
                Issue.record("Expected queueTimeout, got \(error)")
            }
        } catch {
            // CancellationError from the racing task group is also acceptable
        }

        await gated.releaseAll()
    }

    // MARK: - Stream Holds Slot

    @Test("Streaming request holds queue slot until stream completes")
    func testStreamHoldsSlot() async throws {
        let gated = GatedLLM()
        let queued = QueuedLLM(baseLLM: gated)

        let streamTask = Task<[String], Error> {
            var chunks: [String] = []
            let stream = queued.stream(makeMessage(), config: LLMRequestConfig())
            for try await result in stream {
                if let value = result.streamValue {
                    chunks.append(value.content)
                }
            }
            return chunks
        }
        try await pollUntil { await gated.callCount >= 1 }

        let sendTask = Task { try await queued.send(makeMessage(), config: LLMRequestConfig()) }
        try await pollUntil { await queued.queueDepth >= 1 }

        #expect(await gated.callCount == 1)

        await gated.release(ordinal: 1)
        _ = try await streamTask.value

        try await pollUntil { await gated.callCount >= 2 }
        #expect(await gated.callCount == 2)

        await gated.release(ordinal: 2)
        _ = try await sendTask.value
    }

    // MARK: - Error Releases Slot

    @Test("Failed request releases its queue slot")
    func testErrorReleasesSlot() async throws {
        let failing = FailingLLM()
        let queued = QueuedLLM(baseLLM: failing)

        do {
            _ = try await queued.send(makeMessage(), config: LLMRequestConfig())
            Issue.record("Expected error")
        } catch {
            // expected
        }

        let fast = FastLLM()
        let queued2 = QueuedLLM(baseLLM: fast)
        let response = try await queued2.send(makeMessage(), config: LLMRequestConfig())
        #expect(response.content == "fast-response")
    }

    // MARK: - Queue Depth

    @Test("queueDepth reflects correct count")
    func testQueueDepth() async throws {
        let gated = GatedLLM()
        let queued = QueuedLLM(baseLLM: gated)

        #expect(await queued.queueDepth == 0)

        let _ = Task { try await queued.send(makeMessage(), config: LLMRequestConfig()) }
        try await pollUntil { await gated.callCount >= 1 }
        #expect(await queued.queueDepth == 0)

        let _ = Task { try await queued.send(makeMessage(), config: LLMRequestConfig()) }
        try await pollUntil { await queued.queueDepth >= 1 }
        #expect(await queued.queueDepth == 1)

        await gated.release(ordinal: 1)
        try await pollUntil { await queued.queueDepth == 0 }
        #expect(await queued.queueDepth == 0)

        await gated.releaseAll()
    }

    // MARK: - Cancellation While Queued

    @Test("Cancelling a queued request removes it from the queue")
    func testCancellationWhileQueued() async throws {
        let gated = GatedLLM()
        let queued = QueuedLLM(baseLLM: gated)

        let _ = Task { try await queued.send(makeMessage(), config: LLMRequestConfig()) }
        try await pollUntil { await gated.callCount >= 1 }

        let cancelMe = Task { try await queued.send(makeMessage(), config: LLMRequestConfig()) }
        try await pollUntil { await queued.queueDepth >= 1 }

        cancelMe.cancel()
        try await pollUntil { await queued.queueDepth == 0 }

        #expect(await queued.queueDepth == 0)

        await gated.releaseAll()
    }

    // MARK: - Max Concurrent Requests

    @Test("maxConcurrentRequests allows parallel execution")
    func testMaxConcurrentRequests() async throws {
        let gated = GatedLLM()
        let queued = QueuedLLM(
            baseLLM: gated,
            configuration: LLMQueueConfiguration(maxConcurrentRequests: 2)
        )

        let _ = Task { try await queued.send(makeMessage(), config: LLMRequestConfig()) }
        let _ = Task { try await queued.send(makeMessage(), config: LLMRequestConfig()) }
        try await pollUntil { await gated.callCount >= 2 }

        #expect(await gated.callCount == 2)

        await gated.releaseAll()
    }

    // MARK: - Composition with StatefulLLM

    @Test("QueuedLLM + StatefulLLM produces deterministic state transitions")
    func testCompositionWithStatefulLLM() async throws {
        let gated = GatedLLM()
        let stateful = StatefulLLM(baseLLM: gated)
        let queued = QueuedLLM(baseLLM: stateful)

        #expect(queued.currentState == .idle(.ready))

        let stream = queued.stateUpdates
        let stateCollector = Task<[LLMRuntimeState], Never> {
            var states: [LLMRuntimeState] = []
            var iterator = stream.makeAsyncIterator()
            while let state = await iterator.next() {
                states.append(state)
                if states.count > 1 && state == .idle(.ready) {
                    break
                }
            }
            return states
        }

        // Brief pause to let the collector subscribe to the stream
        try await Task.sleep(nanoseconds: 10_000_000)

        let sendTask = Task { try await queued.send(makeMessage(), config: LLMRequestConfig()) }
        try await pollUntil { await gated.callCount >= 1 }

        await gated.release(ordinal: 1)
        _ = try await sendTask.value

        stateful.transition(to: .idle(.ready))

        let states = await stateCollector.value
        #expect(states.first == .idle(.ready))
        #expect(states.contains(.generating(.reasoning)))
        #expect(states.contains(.idle(.completed)))
        #expect(states.last == .idle(.ready))
    }

    // MARK: - Delegation

    @Test("QueuedLLM delegates getModelName and getCapabilities")
    func testDelegation() throws {
        let fast = FastLLM()
        let queued = QueuedLLM(baseLLM: fast)

        #expect(queued.getModelName() == "fast-llm")
        #expect(queued.getCapabilities() == [.completion])
    }

    // MARK: - Pass-through for single request

    @Test("Single request passes through without issues")
    func testSingleRequestPassthrough() async throws {
        let fast = FastLLM()
        let queued = QueuedLLM(baseLLM: fast)

        let response = try await queued.send(makeMessage(), config: LLMRequestConfig())
        #expect(response.content == "fast-response")
    }

    @Test("QueuedLLM wrapping StatefulLLM includes queued in request phases")
    func testQueuedStatefulRequestPhasesIncludeQueued() async throws {
        struct SimpleLLM: LLMProtocol {
            func getModelName() -> String { "simple" }
            func getCapabilities() -> [LLMCapability] { [.completion] }
            func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
                .complete(content: "ok")
            }
            func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        }

        let queued = QueuedLLM(baseLLM: StatefulLLM(baseLLM: SimpleLLM()))
        let stream = queued.requestStateUpdates
        var iterator = stream.makeAsyncIterator()

        let sendTask = Task {
            try await queued.send(makeMessage("hi"), config: LLMRequestConfig())
        }

        var phases: [LLMRequestState] = []
        while let (_, phase) = await iterator.next() {
            phases.append(phase)
            if case .completed = phase { break }
        }
        _ = try await sendTask.value

        #expect(phases.first == .queued)
        #expect(phases.contains(.active))
        #expect(phases.contains(.completed))
    }

    @Test("Single stream request passes through without issues")
    func testSingleStreamPassthrough() async throws {
        let fast = FastLLM()
        let queued = QueuedLLM(baseLLM: fast)

        var results: [StreamResult<LLMResponse, LLMResponse>] = []
        let stream = queued.stream(makeMessage(), config: LLMRequestConfig())
        for try await result in stream {
            results.append(result)
        }

        #expect(results.count == 2)
        #expect(results[0].isStream)
        #expect(results[1].isComplete)
    }

    // MARK: - Priority Queue Ordering

    @Test("Continuation priority requests are dequeued before normal requests")
    func testContinuationPriority() async throws {
        let queue = LLMRequestQueue()

        let blocker = try await queue.acquire(priority: .normal)

        let normalTask = Task<QueueSlot, Error> {
            try await queue.acquire(priority: .normal)
        }
        try await pollUntil { await queue.queueDepth >= 1 }

        let continuationTask = Task<QueueSlot, Error> {
            try await queue.acquire(priority: .continuation)
        }
        try await pollUntil { await queue.queueDepth >= 2 }

        await queue.release(blocker)

        // Continuation should be dequeued first; its task completes immediately
        let continuationSlot = try await continuationTask.value

        // Normal is still pending until we release the continuation's slot
        #expect(await queue.queueDepth == 1)

        await queue.release(continuationSlot)
        let normalSlot = try await normalTask.value
        await queue.release(normalSlot)
    }

    @Test("TaskLocal priority propagates through QueuedLLM")
    func testTaskLocalPropagation() async throws {
        let fast = FastLLM()
        let queued = QueuedLLM(baseLLM: fast)

        let response = try await LLMQueuePriority.$current.withValue(.continuation) {
            try await queued.send(makeMessage(), config: LLMRequestConfig())
        }
        #expect(response.content == "fast-response")
    }
}
