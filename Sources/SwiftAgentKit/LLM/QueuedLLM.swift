import Foundation

/// A wrapper that serializes access to any `LLMProtocol` implementation through a FIFO queue.
///
/// Use `QueuedLLM` when a single LLM instance is shared across multiple conversations
/// or agents to prevent concurrent overlapping requests.
///
/// Composes naturally with `StatefulLLM`:
/// ```swift
/// let provider = MyOpenAIProvider(...)
/// let llm = QueuedLLM(baseLLM: StatefulLLM(baseLLM: provider))
/// ```
///
/// Per-call [`LLMRequestState`](LLMRequestState.swift) updates include ``LLMRequestState/queued`` while waiting;
/// use [`StatefulLLM.requestStateUpdates`](StatefulLLM) (or this type's ``requestStateUpdates``) for the full timeline.
public struct QueuedLLM: LLMProtocol {
    private let baseLLM: any LLMProtocol
    private let queue: LLMRequestQueue
    private let requestStateHub: LLMRequestStateHub

    public init(
        baseLLM: any LLMProtocol,
        configuration: LLMQueueConfiguration = LLMQueueConfiguration()
    ) {
        self.baseLLM = baseLLM
        self.queue = LLMRequestQueue(configuration: configuration)
        self.requestStateHub = LLMRequestStateHub()
    }

    /// Number of requests currently waiting in the queue.
    public var queueDepth: Int {
        get async { await queue.queueDepth }
    }

    /// Multiplexed per-call request states (includes ``LLMRequestState/queued`` for this wrapper).
    public var requestStateUpdates: AsyncStream<(LLMRequestID, LLMRequestState)> {
        requestStateHub.makeStream()
    }

    /// Latest published per-request state for the given id (this wrapper’s hub).
    public func currentRequestState(for id: LLMRequestID) -> LLMRequestState? {
        requestStateHub.currentState(for: id)
    }

    /// Snapshot of latest per-request states on this wrapper’s hub.
    public var currentRequestStates: [LLMRequestID: LLMRequestState] {
        requestStateHub.currentStates
    }

    // MARK: - LLMProtocol delegation

    public var currentState: LLMRuntimeState {
        baseLLM.currentState
    }

    public var stateUpdates: AsyncStream<LLMRuntimeState> {
        baseLLM.stateUpdates
    }

    public func getModelName() -> String {
        baseLLM.getModelName()
    }

    public func getCapabilities() -> [LLMCapability] {
        baseLLM.getCapabilities()
    }

    // MARK: - Queued operations

    public func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        let rid = LLMRequestID()
        return try await LLMRequestStateHub.$current.withValue(requestStateHub) {
            try await LLMRequestID.$current.withValue(rid) {
                requestStateHub.publish(rid, .queued)
                do {
                    let slot = try await queue.acquire(priority: LLMQueuePriority.current)
                    requestStateHub.publish(rid, .active)
                    do {
                        let response = try await baseLLM.send(messages, config: config)
                        if !Self.baseEmitsRequestTerminals(baseLLM) {
                            requestStateHub.publish(rid, .completed)
                        }
                        await queue.release(slot)
                        return response
                    } catch {
                        if !Self.baseEmitsRequestTerminals(baseLLM) {
                            Self.publishHubTerminal(for: error, hub: requestStateHub, requestID: rid)
                        }
                        await queue.release(slot)
                        throw error
                    }
                } catch {
                    Self.publishHubTerminal(for: error, hub: requestStateHub, requestID: rid)
                    throw error
                }
            }
        }
    }

    public func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        AsyncThrowingStream { continuation in
            let rid = LLMRequestID()
            let work = Task {
                do {
                    try await LLMRequestStateHub.$current.withValue(requestStateHub) {
                        try await LLMRequestID.$current.withValue(rid) {
                            requestStateHub.publish(rid, .queued)
                            let slot = try await queue.acquire(priority: LLMQueuePriority.current)
                            requestStateHub.publish(rid, .active)
                            let upstream = baseLLM.stream(messages, config: config)
                            do {
                                for try await result in upstream {
                                    continuation.yield(result)
                                }
                                continuation.finish()
                                if !Self.baseEmitsRequestTerminals(baseLLM) {
                                    requestStateHub.publish(rid, .completed)
                                }
                                await queue.release(slot)
                            } catch {
                                continuation.finish(throwing: error)
                                if !Self.baseEmitsRequestTerminals(baseLLM) {
                                    Self.publishHubTerminal(for: error, hub: requestStateHub, requestID: rid)
                                }
                                await queue.release(slot)
                            }
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                    Self.publishHubTerminal(for: error, hub: requestStateHub, requestID: rid)
                }
            }
            continuation.onTermination = { @Sendable _ in
                work.cancel()
            }
        }
    }

    /// When the base does not publish per-request terminals (e.g. raw provider), map cancellation distinctly from failures.
    private static func publishHubTerminal(for error: Error, hub: LLMRequestStateHub, requestID: LLMRequestID) {
        if error is CancellationError {
            hub.publish(requestID, .cancelled)
        } else if (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled {
            hub.publish(requestID, .cancelled)
        } else {
            hub.publish(requestID, .failed(error.localizedDescription))
        }
    }

    public func generateImage(_ config: ImageGenerationRequestConfig) async throws -> ImageGenerationResponse {
        let rid = LLMRequestID()
        return try await LLMRequestStateHub.$current.withValue(requestStateHub) {
            try await LLMRequestID.$current.withValue(rid) {
                requestStateHub.publish(rid, .queued)
                do {
                    let slot = try await queue.acquire(priority: LLMQueuePriority.current)
                    requestStateHub.publish(rid, .active)
                    do {
                        let response = try await baseLLM.generateImage(config)
                        if !Self.baseEmitsRequestTerminals(baseLLM) {
                            requestStateHub.publish(rid, .completed)
                        }
                        await queue.release(slot)
                        return response
                    } catch {
                        if !Self.baseEmitsRequestTerminals(baseLLM) {
                            Self.publishHubTerminal(for: error, hub: requestStateHub, requestID: rid)
                        }
                        await queue.release(slot)
                        throw error
                    }
                } catch {
                    Self.publishHubTerminal(for: error, hub: requestStateHub, requestID: rid)
                    throw error
                }
            }
        }
    }

    /// `StatefulLLM` publishes terminal per-call phases; other bases do not.
    private static func baseEmitsRequestTerminals(_ base: any LLMProtocol) -> Bool {
        base is StatefulLLM
    }
}
