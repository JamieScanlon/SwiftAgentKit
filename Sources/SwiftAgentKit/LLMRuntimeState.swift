import Foundation

/// Fine-grained idle phases for an LLM.
public enum LLMIdleState: String, Codable, Sendable {
    /// No request is actively being processed.
    case ready
    /// The model is paused while external tool calls execute.
    case waitingForToolResult
    /// A final response was produced for the latest request.
    case completed
}

/// Fine-grained generation phases for an LLM.
public enum LLMGenerationState: String, Codable, Sendable {
    /// The model is reasoning/thinking before emitting user-facing output.
    case reasoning
    /// The model is actively generating user-facing output.
    case responding
}

/// Observable runtime state for an LLM.
public enum LLMRuntimeState: Sendable, Codable, Equatable {
    /// Idle states, including ready, waiting for tools, and completed.
    case idle(LLMIdleState)
    /// Active generation states.
    case generating(LLMGenerationState)
    /// Terminal failure for the current request.
    case failed(String?)
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

    public init(
        baseLLM: any LLMProtocol,
        runtimeStateStore: LLMRuntimeStateStore = LLMRuntimeStateStore()
    ) {
        self.baseLLM = baseLLM
        self.runtimeStateStore = runtimeStateStore
    }

    public var currentState: LLMRuntimeState {
        runtimeStateStore.currentState
    }

    public var stateUpdates: AsyncStream<LLMRuntimeState> {
        runtimeStateStore.makeStream()
    }

    public func transition(to state: LLMRuntimeState) {
        runtimeStateStore.transition(to: state)
    }

    public func getModelName() -> String {
        baseLLM.getModelName()
    }

    public func getCapabilities() -> [LLMCapability] {
        baseLLM.getCapabilities()
    }

    public func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        transition(to: .generating(.reasoning))

        do {
            let response = try await baseLLM.send(messages, config: config)
            transition(to: response.hasToolCalls ? .idle(.waitingForToolResult) : .idle(.completed))
            return response
        } catch {
            transition(to: .failed(error.localizedDescription))
            transition(to: .idle(.ready))
            throw error
        }
    }

    public func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        transition(to: .generating(.reasoning))

        let upstream = baseLLM.stream(messages, config: config)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await result in upstream {
                        switch result {
                        case .stream:
                            transition(to: .generating(.responding))
                        case .complete(let response):
                            transition(to: response.hasToolCalls ? .idle(.waitingForToolResult) : .idle(.completed))
                        }
                        continuation.yield(result)
                    }
                    continuation.finish()
                } catch {
                    transition(to: .failed(error.localizedDescription))
                    transition(to: .idle(.ready))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func generateImage(_ config: ImageGenerationRequestConfig) async throws -> ImageGenerationResponse {
        transition(to: .generating(.responding))

        do {
            let response = try await baseLLM.generateImage(config)
            transition(to: .idle(.completed))
            return response
        } catch {
            transition(to: .failed(error.localizedDescription))
            transition(to: .idle(.ready))
            throw error
        }
    }
}
