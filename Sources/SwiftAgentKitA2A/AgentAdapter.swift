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
    func handleSend(_ params: MessageSendParams, task: A2ATask, store: TaskStore) async throws
    func handleStream(_ params: MessageSendParams, task: A2ATask, store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws
}
