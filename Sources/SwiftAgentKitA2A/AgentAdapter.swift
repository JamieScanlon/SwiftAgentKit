// MARK: - Adapter Response Types

/// Response type that adapters will return for a given request
public enum AdapterResponseType: Sendable {
    /// Return a simple message response (no task tracking)
    /// Use for quick, synchronous responses that don't need progress tracking
    case message
    
    /// Return a tracked task (with full tracking)
    /// Use for longer operations that need status updates, artifacts, or can be queried later
    case task
}

// MARK: - Generic Adapter Layer

/// Contract every model‑specific adapter must fulfil.
public protocol AgentAdapter: Sendable {
    // MARK: metadata used to auto‑build AgentCard
    var agentName: String { get }
    var agentDescription: String { get }
    var cardCapabilities: AgentCard.AgentCapabilities { get }
    var skills: [AgentCard.AgentSkill]                { get }
    var defaultInputModes: [String]         { get }
    var defaultOutputModes: [String]        { get }
    
    // MARK: required handlers
    
    /// Determines what type of response this adapter will return for the given request
    /// - Parameter params: The message send parameters from the client
    /// - Returns: The type of response (message or task)
    ///
    /// Return `.message` for quick, synchronous responses that don't need task tracking.
    /// Return `.task` for long-running operations that need progress tracking and artifacts.
    func responseType(for params: MessageSendParams) -> AdapterResponseType
    
    /// Handles a message/send request that will return a simple message (no task tracking)
    /// - Parameter params: The message send parameters from the client
    /// - Returns: An A2AMessage to return to the client
    ///
    /// This is called when `responseType(for:)` returns `.message`
    func handleMessageSend(_ params: MessageSendParams) async throws -> A2AMessage
    
    /// Handles a message/send request that will return a tracked task
    /// - Parameters:
    ///   - params: The message send parameters from the client
    ///   - taskId: The ID of the task created by the server
    ///   - contextId: The context ID for this interaction
    ///   - store: The task store for updating task state
    ///
    /// This is called when `responseType(for:)` returns `.task`
    /// Update the task via `store.updateTaskStatus()` and `store.updateTaskArtifacts()`
    func handleTaskSend(_ params: MessageSendParams, taskId: String, contextId: String, store: TaskStore) async throws
    
    /// Handles a message/stream request
    /// - Parameters:
    ///   - params: The message send parameters from the client
    ///   - taskId: The ID of the task (nil for message-based streaming)
    ///   - contextId: The context ID for this interaction (nil for message-based streaming)
    ///   - store: The task store for updating task state (nil for message-based streaming)
    ///   - eventSink: Closure to send streaming events to the client
    ///
    /// When responseType returns `.message`, taskId, contextId, and store will be nil.
    /// When responseType returns `.task`, all parameters will be provided.
    func handleStream(_ params: MessageSendParams, taskId: String?, contextId: String?, store: TaskStore?, eventSink: @escaping (Encodable) -> Void) async throws
}
