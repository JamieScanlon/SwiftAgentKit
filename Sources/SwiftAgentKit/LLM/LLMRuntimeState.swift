import Foundation

/// Fine-grained idle phases for an LLM.
///
/// These describe what the LLM itself is doing when it is not actively
/// generating tokens. They are not request-level states — concepts like
/// "queued", "pending", or "waiting for tool results" belong to the
/// request or the infrastructure around the LLM, not the model itself.
public enum LLMIdleState: String, Codable, Sendable {
    /// The model is available and not processing any request.
    case ready
    /// The model produced a final response for the most recent request.
    case completed
}

/// Fine-grained generation phases for an LLM.
///
/// These describe what the model is doing while it is actively working
/// on a request.
public enum LLMGenerationState: String, Codable, Sendable {
    /// The model is reasoning/thinking before emitting user-facing output.
    case reasoning
    /// The model is actively generating user-facing output.
    case responding
}

/// The observable runtime state of an LLM instance.
///
/// This represents what the model itself is doing right now — idle,
/// actively generating, or in a failure state. It intentionally does not
/// include request-lifecycle concerns (queued, retrying, etc.) because
/// those belong to the infrastructure around the LLM, not the LLM itself.
public enum LLMRuntimeState: Sendable, Codable, Equatable {
    /// The model is not actively generating tokens.
    case idle(LLMIdleState)
    /// The model is actively generating tokens.
    case generating(LLMGenerationState)
    /// The most recent request ended in failure.
    case failed(String?)

    /// `true` while the shared instance is in ``generating(_:)`` (actively generating tokens).
    public var isGeneratingTokens: Bool {
        if case .generating = self { return true }
        return false
    }
}

/// Optional protocol for actively publishing runtime state transitions.
public protocol LLMRuntimeStateControllable: Sendable {
    /// Publish a new runtime state value.
    func transition(to state: LLMRuntimeState)
}

/// Thread-safe runtime state container with broadcast stream support.
public final class LLMRuntimeStateStore: @unchecked Sendable {
    private let lock = NSLock()
    private var state: LLMRuntimeState
    private var continuations: [UUID: AsyncStream<LLMRuntimeState>.Continuation] = [:]

    public init(initialState: LLMRuntimeState = .idle(.ready)) {
        self.state = initialState
    }

    /// The current state snapshot.
    public var currentState: LLMRuntimeState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    /// Publish a state transition and notify subscribers.
    public func transition(to newState: LLMRuntimeState) {
        let activeContinuations: [AsyncStream<LLMRuntimeState>.Continuation]
        lock.lock()
        state = newState
        activeContinuations = Array(continuations.values)
        lock.unlock()

        for continuation in activeContinuations {
            continuation.yield(newState)
        }
    }

    /// Create a stream of state updates, beginning with the current snapshot.
    public func makeStream(includeCurrentState: Bool = true) -> AsyncStream<LLMRuntimeState> {
        AsyncStream { continuation in
            let id = UUID()
            let initialState: LLMRuntimeState?

            lock.lock()
            continuations[id] = continuation
            initialState = includeCurrentState ? state : nil
            lock.unlock()

            if let initialState {
                continuation.yield(initialState)
            }

            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: id)
            }
        }
    }

    private func removeContinuation(id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}

/// Wrapper that adds observable runtime state to any LLMProtocol implementation.
public struct StatefulLLM: LLMProtocol, LLMRuntimeStateControllable {
    private let baseLLM: any LLMProtocol
    private let runtimeStateStore: LLMRuntimeStateStore
    private let requestStateHub: LLMRequestStateHub

    public init(baseLLM: any LLMProtocol) {
        self.init(baseLLM: baseLLM, runtimeStateStore: LLMRuntimeStateStore(), requestStateHub: LLMRequestStateHub())
    }

    public init(baseLLM: any LLMProtocol, runtimeStateStore: LLMRuntimeStateStore) {
        self.init(baseLLM: baseLLM, runtimeStateStore: runtimeStateStore, requestStateHub: LLMRequestStateHub())
    }

    public init(baseLLM: any LLMProtocol, runtimeStateStore: LLMRuntimeStateStore, requestStateHub: LLMRequestStateHub) {
        self.baseLLM = baseLLM
        self.runtimeStateStore = runtimeStateStore
        self.requestStateHub = requestStateHub
    }

    public var currentState: LLMRuntimeState {
        runtimeStateStore.currentState
    }

    public var stateUpdates: AsyncStream<LLMRuntimeState> {
        runtimeStateStore.makeStream()
    }

    /// Per-call request lifecycle for this wrapper (no `queued` state; use [`QueuedLLM`](QueuedLLM) for that).
    public var requestStateUpdates: AsyncStream<(LLMRequestID, LLMRequestState)> {
        requestStateHub.makeStream()
    }

    /// Latest published per-request state for the given id (from this wrapper’s hub, or ``LLMRequestStateHub/current`` when set).
    public func currentRequestState(for id: LLMRequestID) -> LLMRequestState? {
        effectiveRequestHub().currentState(for: id)
    }

    /// Snapshot of latest per-request states (same hub as ``currentRequestState(for:)``).
    public var currentRequestStates: [LLMRequestID: LLMRequestState] {
        effectiveRequestHub().currentStates
    }

    public func transition(to state: LLMRuntimeState) {
        runtimeStateStore.transition(to: state)
    }

    private func effectiveRequestHub() -> LLMRequestStateHub {
        LLMRequestStateHub.current ?? requestStateHub
    }

    private func effectiveRequestID() -> LLMRequestID {
        LLMRequestID.current ?? LLMRequestID()
    }

    private func publishRequestStart(hub: LLMRequestStateHub, rid: LLMRequestID) {
        if LLMRequestStateHub.current == nil {
            hub.publish(rid, .active)
        }
    }

    public func getModelName() -> String {
        baseLLM.getModelName()
    }

    public func getCapabilities() -> [LLMCapability] {
        baseLLM.getCapabilities()
    }

    public func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        let hub = effectiveRequestHub()
        let rid = effectiveRequestID()
        publishRequestStart(hub: hub, rid: rid)
        hub.publish(rid, .generating(.reasoning))
        transition(to: .generating(.reasoning))

        do {
            let response = try await baseLLM.send(messages, config: config)
            transition(to: .idle(.completed))
            hub.publish(rid, .completed)
            return response
        } catch {
            Self.handleInvocationError(error, hub: hub, requestID: rid, transition: { self.transition(to: $0) })
            throw error
        }
    }

    public func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        let hub = effectiveRequestHub()
        let rid = effectiveRequestID()
        publishRequestStart(hub: hub, rid: rid)
        hub.publish(rid, .generating(.reasoning))
        transition(to: .generating(.reasoning))

        let upstream = baseLLM.stream(messages, config: config)
        return AsyncThrowingStream { continuation in
            let consumeTask = Task {
                do {
                    var sawComplete = false
                    for try await result in upstream {
                        switch result {
                        case .stream:
                            transition(to: .generating(.responding))
                            hub.publish(rid, .generating(.responding))
                            hub.publish(rid, .streaming)
                        case .complete:
                            sawComplete = true
                            transition(to: .idle(.completed))
                            hub.publish(rid, .completed)
                        }
                        continuation.yield(result)
                    }
                    if !sawComplete {
                        transition(to: .idle(.ready))
                        if Task.isCancelled {
                            hub.publish(rid, .cancelled)
                        } else {
                            hub.publish(rid, .failed(Self.streamEndedWithoutComplete))
                        }
                    }
                    continuation.finish()
                } catch {
                    Self.handleInvocationError(error, hub: hub, requestID: rid, transition: { self.transition(to: $0) })
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                consumeTask.cancel()
            }
        }
    }

    public func generateImage(_ config: ImageGenerationRequestConfig) async throws -> ImageGenerationResponse {
        let hub = effectiveRequestHub()
        let rid = effectiveRequestID()
        publishRequestStart(hub: hub, rid: rid)
        hub.publish(rid, .generating(.responding))
        transition(to: .generating(.responding))

        do {
            let response = try await baseLLM.generateImage(config)
            transition(to: .idle(.completed))
            hub.publish(rid, .completed)
            return response
        } catch {
            Self.handleInvocationError(error, hub: hub, requestID: rid, transition: { self.transition(to: $0) })
            throw error
        }
    }

    /// Standard terminal handling for cancelled work vs real failures (shared by ``send``, ``stream``, ``generateImage``).
    private static func handleInvocationError(
        _ error: Error,
        hub: LLMRequestStateHub,
        requestID: LLMRequestID,
        transition: (LLMRuntimeState) -> Void
    ) {
        if isCancellation(error) {
            transition(.idle(.ready))
            hub.publish(requestID, .cancelled)
        } else {
            let message = error.localizedDescription
            transition(.failed(message))
            hub.publish(requestID, .failed(message))
            transition(.idle(.ready))
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError
            || (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled
    }

    private static let streamEndedWithoutComplete = "Stream ended without a complete response"
}

