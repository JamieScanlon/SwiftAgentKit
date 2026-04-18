import Foundation

// MARK: - Snapshot types

/// A single point-in-time view of LLM runtime state, per-request states, and agentic-loop states
/// for one orchestration or adapter instance.
///
/// Prefer ``OrchestrationObservationCoordinator/currentSnapshot()`` or
/// ``OrchestrationObservationCoordinator/snapshotUpdates()`` over reading
/// ``LLMProtocol/currentState``, per-request maps, and ``AgenticLoopStateHub/currentStates``
/// separately so clients avoid torn reads when correlating UI.
public struct OrchestrationSnapshot: Sendable, Equatable {
    /// Shared instance / model phase from the underlying ``LLMProtocol``.
    public var llmRuntime: LLMRuntimeState
    /// Latest published state per ``LLMRequestID`` (empty when the LLM is not a
    /// ``LLMPerRequestStateSource`` such as ``StatefulLLM`` or ``QueuedLLM``).
    public var perRequestStates: [LLMRequestID: LLMRequestState]
    /// Latest published state per ``AgenticLoopID`` for this orchestrator or adapter hub.
    public var agenticLoopStates: [AgenticLoopID: AgenticLoopState]

    public init(
        llmRuntime: LLMRuntimeState,
        perRequestStates: [LLMRequestID: LLMRequestState],
        agenticLoopStates: [AgenticLoopID: AgenticLoopState]
    ) {
        self.llmRuntime = llmRuntime
        self.perRequestStates = perRequestStates
        self.agenticLoopStates = agenticLoopStates
    }

    /// Returns a copy where per-request and agentic-loop entries that still look in-flight are
    /// reconciled with ``llmRuntime`` when the model is not in ``LLMRuntimeState/generating(_:)``.
    ///
    /// This masks torn reads between the runtime store, per-request hubs, and agentic hub (e.g. after a
    /// turn completes or work is abandoned) so UI does not show “generating” for a call that has already
    /// finished while the instance is idle. Legitimate non-LLM phases such as
    /// ``AgenticLoopState/waitingForToolExecution`` / ``AgenticLoopState/executingTools`` are preserved.
    public func reconcilingStaleInFlightPhases() -> OrchestrationSnapshot {
        guard !llmRuntime.isGeneratingTokens else { return self }
        let requests = Dictionary(uniqueKeysWithValues: perRequestStates.map { id, state in
            (id, Self.reconciledRequestState(llmRuntime: llmRuntime, state: state))
        })
        let loops = Dictionary(uniqueKeysWithValues: agenticLoopStates.map { id, state in
            (id, Self.reconciledAgenticState(llmRuntime: llmRuntime, state: state))
        })
        return OrchestrationSnapshot(
            llmRuntime: llmRuntime,
            perRequestStates: requests,
            agenticLoopStates: loops
        )
    }

    private static func reconciledRequestState(
        llmRuntime: LLMRuntimeState,
        state: LLMRequestState
    ) -> LLMRequestState {
        switch state {
        case .active, .generating, .streaming:
            switch llmRuntime {
            case .failed(let message):
                return .failed(message)
            default:
                return .completed
            }
        default:
            return state
        }
    }

    private static func reconciledAgenticState(
        llmRuntime: LLMRuntimeState,
        state: AgenticLoopState
    ) -> AgenticLoopState {
        switch state {
        case .waitingForToolExecution, .executingTools,
             .completed, .failed, .maxIterationsReached,
             .llmGenerationCompleted:
            return state
        case .started, .llmCall, .betweenIterations:
            switch llmRuntime {
            case .failed(let message):
                return .failed(message)
            default:
                return .completed
            }
        }
    }
}

/// One emission from ``OrchestrationObservationCoordinator/snapshotUpdates()`` with a monotonic
/// ``generation`` so hosts can coalesce or drop stale UI updates.
public struct OrchestrationSnapshotEvent: Sendable, Equatable {
    /// Increments by one for each emitted event on a given coordinator (starting at `1` for the
    /// first emission after the first subscriber attaches).
    public var generation: UInt64
    public var snapshot: OrchestrationSnapshot

    public init(generation: UInt64, snapshot: OrchestrationSnapshot) {
        self.generation = generation
        self.snapshot = snapshot
    }
}

// MARK: - Per-request source

/// Conformed to by LLM wrappers that publish ``LLMRequestState`` (``StatefulLLM``, ``QueuedLLM``).
public protocol LLMPerRequestStateSource: LLMProtocol {
    var requestStateUpdates: AsyncStream<(LLMRequestID, LLMRequestState)> { get }
    var currentRequestStates: [LLMRequestID: LLMRequestState] { get }
}

extension StatefulLLM: LLMPerRequestStateSource {}

extension QueuedLLM: LLMPerRequestStateSource {}

// MARK: - Coordinator

/// Merges LLM runtime, per-request, and agentic-loop observations into one stream and pull API.
///
/// The coordinator reads all three sources in one ``emitSnapshot()`` pass whenever any underlying
/// stream yields, so values in ``OrchestrationSnapshot`` match as closely as the underlying hubs allow.
public final class OrchestrationObservationCoordinator: @unchecked Sendable {
    private let llm: LLMProtocol
    private let agenticLoopStateHub: AgenticLoopStateHub

    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var continuations: [UUID: AsyncStream<OrchestrationSnapshotEvent>.Continuation] = [:]
    private var subscriberCount = 0
    private var mergeTask: Task<Void, Never>?

    public init(llm: LLMProtocol, agenticLoopStateHub: AgenticLoopStateHub) {
        self.llm = llm
        self.agenticLoopStateHub = agenticLoopStateHub
    }

    /// Latest combined snapshot without incrementing ``OrchestrationSnapshotEvent/generation``.
    public func currentSnapshot() -> OrchestrationSnapshot {
        captureUnlocked()
    }

    /// Unified stream: emits whenever the LLM runtime stream, per-request stream (if available), or
    /// agentic-loop stream delivers an element, plus an initial event when the first subscriber attaches.
    public func snapshotUpdates() -> AsyncStream<OrchestrationSnapshotEvent> {
        AsyncStream { continuation in
            let id = UUID()
            self.lock.lock()
            self.continuations[id] = continuation
            let wasIdle = self.subscriberCount == 0
            self.subscriberCount += 1
            self.lock.unlock()

            if wasIdle {
                self.startMergeIfNeeded()
            }

            self.emitSnapshot()

            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: id)
            }
        }
    }

    private func captureUnlocked() -> OrchestrationSnapshot {
        let requests: [LLMRequestID: LLMRequestState]
        if let source = llm as? any LLMPerRequestStateSource {
            requests = source.currentRequestStates
        } else {
            requests = [:]
        }
        return OrchestrationSnapshot(
            llmRuntime: llm.currentState,
            perRequestStates: requests,
            agenticLoopStates: agenticLoopStateHub.currentStates
        )
        .reconcilingStaleInFlightPhases()
    }

    private func emitSnapshot() {
        let snapshot = captureUnlocked()
        lock.lock()
        generation += 1
        let gen = generation
        let recipients = Array(continuations.values)
        lock.unlock()
        let event = OrchestrationSnapshotEvent(generation: gen, snapshot: snapshot)
        for continuation in recipients {
            continuation.yield(event)
        }
    }

    private func removeContinuation(id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        subscriberCount -= 1
        let cancelMerge = subscriberCount == 0
        lock.unlock()
        if cancelMerge {
            mergeTask?.cancel()
            mergeTask = nil
        }
    }

    private func startMergeIfNeeded() {
        lock.lock()
        let alreadyRunning = mergeTask != nil
        lock.unlock()
        guard !alreadyRunning else { return }

        mergeTask = Task { [weak self] in
            guard let self else { return }
            await self.runMergedObservers()
        }
    }

    /// Subscribes to all observation streams **once** per merge task so `hub.publish` cannot be missed
    /// before `AsyncStream` registration (see tests: resubscribe + rapid publish).
    private func runMergedObservers() async {
        let llmStream = llm.stateUpdates
        let agenticStream = agenticLoopStateHub.makeStream()
        let requestStream = (llm as? any LLMPerRequestStateSource).map { $0.requestStateUpdates }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in llmStream {
                    if Task.isCancelled { return }
                    self.emitSnapshot()
                }
            }
            group.addTask {
                for await _ in agenticStream {
                    if Task.isCancelled { return }
                    self.emitSnapshot()
                }
            }
            if let requestStream {
                group.addTask {
                    for await _ in requestStream {
                        if Task.isCancelled { return }
                        self.emitSnapshot()
                    }
                }
            }
        }
    }
}
