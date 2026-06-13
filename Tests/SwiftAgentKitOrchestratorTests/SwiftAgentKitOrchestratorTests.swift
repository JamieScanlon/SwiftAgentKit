import Foundation
import Testing
import SwiftAgentKitOrchestrator
import SwiftAgentKit
import SwiftAgentKitMCP
import SwiftAgentKitA2A
import SwiftAgentKitACP
import Logging
import EasyJSON

/*
 Why this suite used to “hang” the test runner

 `SwiftAgentKitOrchestrator.messageStream` (and similar hub-backed streams such as `agenticLoopUpdates`)
 are long-lived `AsyncStream`s: the library yields updates but does not call `finish()` during normal use.

 Anti-patterns that leave work running after a test returns:
 • `_ = Task { for await _ in messageStream {} }` — the drain never ends, so the runner can stall.
 • The same with a collector: `Task { for await message in messageStream { await collector.append(message) } }` without cancellation.

 What we do instead:
 • Use `drainPublishedMessagesWhileRunning` to run `updateConversation` (or similar) while a background task
   consumes the stream, then cancel that task in `defer` when the operation completes.
 • After the operation, sleep briefly (`try? await Task.sleep`) so buffered yields are drained before cancel.
 • For a second subscriber (e.g. agentic state collection), use `defer { collectTask.cancel() }` so teardown runs on throw too.
 • Prefer bounded iteration or `collectLLMRuntimeStatesAfter` when you only need a finite prefix.

 Other modules: adapter tests that subscribe to `agenticLoopUpdates` may need `await Task.yield()` before the producer runs
 so the `for await` has registered; see `LLMProtocolAdapterTests`.

 For product semantics of runtime vs request vs agentic state, see `docs/LLMStateAndObservation.md`.
 */

/// Collects ``AgenticLoopState`` from an async stream without non-Sendable shared mutable state in `Task` closures.
fileprivate actor AgenticLoopStateCollector {
    private var states: [AgenticLoopState] = []
    func append(_ state: AgenticLoopState) {
        states.append(state)
    }
    func snapshot() -> [AgenticLoopState] { states }
}

/// Subscribes to `stream` (iterator created before `body`), runs `body`, then drains until a terminal `.idle(.ready)`.
fileprivate func collectLLMRuntimeStatesAfter(
    stream: AsyncStream<LLMRuntimeState>,
    body: () async throws -> Void
) async rethrows -> [LLMRuntimeState] {
    var iterator = stream.makeAsyncIterator()
    try await body()
    var observed: [LLMRuntimeState] = []
    while let state = await iterator.next() {
        observed.append(state)
        if observed.count > 1 && state == .idle(.ready) {
            break
        }
    }
    return observed
}

/// Drains `messageStream` in the background so `publishMessage` does not stall on a full buffer.
/// Cancels the drain task after `operation` completes and a short yield so buffered messages are consumed.
fileprivate func drainPublishedMessagesWhileRunning(
    _ messageStream: AsyncStream<Message>,
    operation: () async throws -> Void
) async rethrows {
    let drain = Task {
        for await _ in messageStream {
            if Task.isCancelled { break }
        }
    }
    defer { drain.cancel() }
    try await operation()
    // Let the concurrent drain task run past the producer finishing (yields may still be in flight).
    _ = try? await Task.sleep(nanoseconds: 15_000_000)
}

/// Holds a per-message handler so the drain `Task` does not capture a non-`Sendable` closure (Swift 6).
private final class UncheckedMessageDrainHandler: @unchecked Sendable {
    let onMessage: (Message) async -> Void
    init(_ onMessage: @escaping (Message) async -> Void) {
        self.onMessage = onMessage
    }
}

/// Like ``drainPublishedMessagesWhileRunning(_:operation:)`` but forwards each message to `processMessage` (e.g. for collectors).
fileprivate func drainPublishedMessagesWhileRunning(
    _ messageStream: AsyncStream<Message>,
    processMessage: @escaping (Message) async -> Void,
    operation: () async throws -> Void
) async rethrows {
    let handler = UncheckedMessageDrainHandler(processMessage)
    let drain = Task {
        for await message in messageStream {
            if Task.isCancelled { break }
            await handler.onMessage(message)
        }
    }
    defer { drain.cancel() }
    try await operation()
    _ = try? await Task.sleep(nanoseconds: 15_000_000)
}

// Mock LLM for testing
struct MockLLM: LLMProtocol {
    let model: String
    let logger: Logger
    var toolCallsToReturn: [ToolCall] = []
    var shouldReturnToolCalls: Bool = false
    
    init(model: String = "mock-gpt-4", logger: Logger, toolCallsToReturn: [ToolCall] = [], shouldReturnToolCalls: Bool = false) {
        self.model = model
        self.logger = logger
        self.toolCallsToReturn = toolCallsToReturn
        self.shouldReturnToolCalls = shouldReturnToolCalls
    }
    
    func getModelName() -> String {
        return model
    }
    
    func getCapabilities() -> [LLMCapability] {
        return [.completion, .tools]
    }
    
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        if shouldReturnToolCalls {
            return LLMResponse.withToolCalls(
                content: "",
                toolCalls: toolCallsToReturn
            )
        }
        return LLMResponse.complete(content: "Mock response")
    }
    
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                // Simulate streaming response with multiple chunks
                let chunks = ["Mock", " streaming", " response"]
                
                // Send streaming chunks
                for chunk in chunks {
                    continuation.yield(StreamResult.stream(LLMResponse.streamChunk(chunk)))
                }
                
                // Send the complete response
                if shouldReturnToolCalls {
                    continuation.yield(StreamResult.complete(LLMResponse.withToolCalls(
                        content: "",
                        toolCalls: toolCallsToReturn
                    )))
                } else {
                    continuation.yield(StreamResult.complete(LLMResponse.complete(content: "Mock streaming response")))
                }
                continuation.finish()
            }
        }
    }
}

/// Yields streaming chunks with explicit ``LLMResponse/streamingFragment`` for partial-stream tests.
struct FragmentStreamingMockLLM: LLMProtocol {
    let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func getModelName() -> String { "fragment-mock" }

    func getCapabilities() -> [LLMCapability] { [.completion] }

    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        LLMResponse.complete(content: "Hello")
    }

    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.stream(LLMResponse(
                    content: "",
                    toolCalls: [],
                    metadata: nil,
                    isComplete: false,
                    toolCallId: nil,
                    streamingFragment: .reasoning("step")
                )))
                continuation.yield(.stream(LLMResponse.streamChunk("Hello")))
                continuation.yield(.stream(LLMResponse(
                    content: "",
                    toolCalls: [],
                    metadata: nil,
                    isComplete: false,
                    toolCallId: nil,
                    streamingFragment: .toolCall(id: "call_x", name: "todo", argumentsFragment: "{\"q\":")
                )))
                continuation.yield(.complete(LLMResponse.complete(content: "Hello")))
                continuation.finish()
            }
        }
    }
}

struct SlowStreamingCancelMockLLM: LLMProtocol {
    let logger: Logger
    let sleepNanos: UInt64

    init(logger: Logger, sleepNanos: UInt64 = 50_000_000) {
        self.logger = logger
        self.sleepNanos = sleepNanos
    }

    func getModelName() -> String { "slow-streaming-cancel-mock" }
    func getCapabilities() -> [LLMCapability] { [.completion] }

    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        LLMResponse.complete(content: "sync")
    }

    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        let sleepNanos = sleepNanos
        return AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.stream(LLMResponse.streamChunk("part-1")))
                try? await Task.sleep(nanoseconds: sleepNanos)
                continuation.yield(.stream(LLMResponse.streamChunk("part-2")))
                try? await Task.sleep(nanoseconds: sleepNanos)
                continuation.yield(.complete(LLMResponse.complete(content: "final")))
                continuation.finish()
            }
        }
    }
}

// MARK: - Config capture (records LLMRequestConfig for assertions)

actor ConfigCapture {
    private(set) var configs: [LLMRequestConfig] = []
    func append(_ config: LLMRequestConfig) {
        configs.append(config)
    }
    func getConfigs() -> [LLMRequestConfig] {
        configs
    }
}

// MARK: - Capturing Mock LLM (records messages sent for assertions)

actor SendCapture {
    private(set) var invocations: [[Message]] = []
    func append(_ messages: [Message]) {
        invocations.append(messages)
    }
    func getInvocations() -> [[Message]] {
        invocations
    }
}

struct CapturingMockLLM: LLMProtocol {
    let model: String
    let logger: Logger
    let toolCallsToReturn: [ToolCall]
    let capture: SendCapture
    let configCapture: ConfigCapture?
    
    init(model: String = "capturing-model", logger: Logger, toolCallsToReturn: [ToolCall], capture: SendCapture = SendCapture(), configCapture: ConfigCapture? = nil) {
        self.model = model
        self.logger = logger
        self.toolCallsToReturn = toolCallsToReturn
        self.capture = capture
        self.configCapture = configCapture
    }
    
    func getModelName() -> String { model }
    func getCapabilities() -> [LLMCapability] { [.completion, .tools] }
    
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        await capture.append(messages)
        if let configCapture {
            await configCapture.append(config)
        }
        let hasToolMessage = messages.contains { $0.role == .tool }
        if hasToolMessage {
            return LLMResponse.complete(content: "Done after tool response")
        }
        return LLMResponse.withToolCalls(content: "", toolCalls: toolCallsToReturn)
    }
    
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        let capture = capture
        let configCapture = configCapture
        let toolCallsToReturn = toolCallsToReturn
        return AsyncThrowingStream { continuation in
            Task {
                await capture.append(messages)
                if let configCapture {
                    await configCapture.append(config)
                }
                let hasToolMessage = messages.contains { $0.role == .tool }
                if hasToolMessage {
                    continuation.yield(.complete(LLMResponse.complete(content: "Done after tool response")))
                } else {
                    continuation.yield(.complete(LLMResponse.withToolCalls(content: "", toolCalls: toolCallsToReturn)))
                }
                continuation.finish()
            }
        }
    }
    
    func generateImage(_ config: ImageGenerationRequestConfig) async throws -> ImageGenerationResponse {
        throw LLMError.invalidRequest("Not implemented")
    }
}

// MARK: - Mock A2A stream client (returns responses with images/files for orchestrator tests)

actor MockA2AStreamClientForOrchestrator: A2AAgentStreamClient {
    var agentCard: AgentCard?
    private let events: [SendStreamingMessageSuccessResponse<MessageResult>]
    
    init(agentCard: AgentCard?, events: [SendStreamingMessageSuccessResponse<MessageResult>]) {
        self.agentCard = agentCard
        self.events = events
    }
    
    func streamMessage(params: MessageSendParams) async throws -> AsyncStream<SendStreamingMessageSuccessResponse<MessageResult>> {
        let events = self.events
        return AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

/// Records whether inline A2A execution invoked `streamMessage`.
actor RecordingA2AStreamClient: A2AAgentStreamClient {
    var agentCard: AgentCard?
    private(set) var streamMessageCallCount = 0
    private let events: [SendStreamingMessageSuccessResponse<MessageResult>]

    init(agentCard: AgentCard?, events: [SendStreamingMessageSuccessResponse<MessageResult>] = []) {
        self.agentCard = agentCard
        self.events = events
    }

    func streamMessage(params: MessageSendParams) async throws -> AsyncStream<SendStreamingMessageSuccessResponse<MessageResult>> {
        streamMessageCallCount += 1
        let events = self.events
        return AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

func makeOrchestratorWithRecordingA2AClient(
    integration: A2AOrchestratorIntegration,
    agentName: String,
    events: [SendStreamingMessageSuccessResponse<MessageResult>] = []
) async throws -> (SwiftAgentKitOrchestrator, RecordingA2AStreamClient) {
    let card = AgentCard(
        name: agentName,
        description: "Test agent",
        url: "https://example.com/\(agentName)",
        version: "1.0",
        capabilities: AgentCard.AgentCapabilities(streaming: true),
        defaultInputModes: ["text/plain"],
        defaultOutputModes: ["text/plain"],
        skills: []
    )
    let client = RecordingA2AStreamClient(agentCard: card, events: events)
    let a2aManager = A2AManager(logger: Logger(label: "TestA2A"))
    try await a2aManager.initialize(clients: [client])
    let orchestrator = SwiftAgentKitOrchestrator(
        llm: MockLLM(model: "test-model", logger: Logger(label: "MockLLM")),
        config: OrchestratorConfig(a2aIntegration: integration),
        a2aManager: a2aManager
    )
    return (orchestrator, client)
}

/// Records whether inline ACP execution invoked `promptStream`.
actor RecordingACPStreamClient: ACPAgentStreamClient {
    let info: ACPImplementation
    private(set) var promptStreamCallCount = 0
    private let responseText: String

    init(name: String, responseText: String = "done") {
        self.info = ACPImplementation(name: name, version: "1.0.0")
        self.responseText = responseText
    }

    var agentInfo: ACPImplementation? { info }

    func promptStream(_ instructions: String) async throws -> (
        updates: AsyncStream<ACPSessionUpdate>,
        response: Task<ACPPromptResponse, Error>
    ) {
        promptStreamCallCount += 1
        let responseText = self.responseText
        let updates = AsyncStream<ACPSessionUpdate> { continuation in
            continuation.yield(.agentMessageChunk(messageId: "1", content: .text(responseText)))
            continuation.finish()
        }
        let response = Task<ACPPromptResponse, Error> { ACPPromptResponse(stopReason: .endTurn) }
        return (updates, response)
    }

    func shutdown() async {}
}

func makeOrchestratorWithRecordingACPClient(
    integration: ACPOrchestratorIntegration,
    agentName: String,
    responseText: String = "done"
) async throws -> (SwiftAgentKitOrchestrator, RecordingACPStreamClient) {
    let client = RecordingACPStreamClient(name: agentName, responseText: responseText)
    let acpManager = ACPManager(logger: Logger(label: "TestACP"))
    try await acpManager.initialize(clients: [client])
    let orchestrator = SwiftAgentKitOrchestrator(
        llm: MockLLM(model: "test-model", logger: Logger(label: "MockLLM")),
        config: OrchestratorConfig(acpIntegration: integration),
        acpManager: acpManager
    )
    return (orchestrator, client)
}

actor MockCancellableA2AStreamClientForOrchestrator: A2ATaskLifecycleClient {
    var agentCard: AgentCard?
    private let initialEvents: [SendStreamingMessageSuccessResponse<MessageResult>]
    private(set) var cancelTaskCallCount = 0
    private(set) var lastCancelledTaskID: String?

    init(agentCard: AgentCard?, initialEvents: [SendStreamingMessageSuccessResponse<MessageResult>] = []) {
        self.agentCard = agentCard
        self.initialEvents = initialEvents
    }

    func streamMessage(params: MessageSendParams) async throws -> AsyncStream<SendStreamingMessageSuccessResponse<MessageResult>> {
        let initialEvents = self.initialEvents
        return AsyncStream { continuation in
            Task {
                for event in initialEvents {
                    continuation.yield(event)
                }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                continuation.finish()
            }
        }
    }

    func cancelTask(params: TaskIdParams) async throws -> A2ATask {
        cancelTaskCallCount += 1
        lastCancelledTaskID = params.taskId
        return A2ATask(
            id: params.taskId,
            contextId: UUID().uuidString,
            status: TaskStatus(
                state: .canceled,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        )
    }

    func getTask(params: TaskQueryParams) async throws -> A2ATask {
        A2ATask(
            id: params.taskId,
            contextId: UUID().uuidString,
            status: TaskStatus(
                state: .working,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        )
    }
}

struct PendingToolProviderMatchingHandleID: ToolProvider {
    var name: String { "PendingMatchingHandle" }
    let toolName: String

    func availableTools() async -> [ToolDefinition] {
        [ToolDefinition(name: toolName, description: "pending tool", parameters: [], type: .function)]
    }

    func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        ToolResult(success: true, content: "pending", toolCallId: toolCall.id)
    }

    func executeToolOutcome(_ toolCall: ToolCall) async throws -> ToolExecutionOutcome {
        let id = toolCall.id ?? UUID().uuidString
        return .pending(PendingToolHandle(handleID: id, toolCallID: id, provider: name))
    }
}

func wrapMessageResult(_ result: MessageResult) -> SendStreamingMessageSuccessResponse<MessageResult> {
    SendStreamingMessageSuccessResponse(jsonrpc: "2.0", id: 1, result: result)
}

// MARK: - Mock ToolProvider for ToolManager orchestrator tests

struct MockFunctionToolProvider: ToolProvider {
    var name: String { "MockFunctionToolProvider" }
    
    private let toolName: String
    private let resultContent: String
    private let resultSuccess: Bool
    private let resultError: String?
    
    init(
        toolName: String = "get_current_time",
        resultContent: String = "2025-02-14T12:00:00Z",
        resultSuccess: Bool = true,
        resultError: String? = nil
    ) {
        self.toolName = toolName
        self.resultContent = resultContent
        self.resultSuccess = resultSuccess
        self.resultError = resultError
    }
    
    func availableTools() async -> [ToolDefinition] {
        [
            ToolDefinition(
                name: toolName,
                description: "Returns the current date and time",
                parameters: [],
                type: .function
            )
        ]
    }
    
    func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        guard toolCall.name == toolName else {
            return ToolResult(success: false, content: "", toolCallId: toolCall.id, error: "Unknown tool: \(toolCall.name)")
        }
        return ToolResult(
            success: resultSuccess,
            content: resultContent,
            toolCallId: toolCall.id,
            error: resultError
        )
    }
}

actor ToolExecutionOrderRecorder {
    private(set) var startedToolNames: [String] = []
    func append(_ name: String) {
        startedToolNames.append(name)
    }
}

actor ToolLifecycleCollector {
    private(set) var events: [ToolLifecycleEvent] = []
    func append(_ event: ToolLifecycleEvent) {
        events.append(event)
    }
    func snapshot() -> [ToolLifecycleEvent] { events }
}

struct RecordingPolicyToolProvider: ToolProvider {
    let toolNames: [String]
    let recorder: ToolExecutionOrderRecorder
    let safety: ToolParallelSafety

    var name: String { "RecordingPolicyToolProvider" }

    func availableTools() async -> [ToolDefinition] {
        toolNames.map {
            ToolDefinition(
                name: $0,
                description: "test tool \($0)",
                parameters: [],
                type: .function
            )
        }
    }

    func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        await recorder.append(toolCall.name)
        return ToolResult(success: true, content: "ok-\(toolCall.name)", toolCallId: toolCall.id)
    }

    func parallelSafety(for toolCall: ToolCall) async -> ToolParallelSafety {
        safety
    }
}

struct PendingMockToolProvider: ToolProvider {
    var name: String { "PendingMockToolProvider" }
    let toolName: String

    func availableTools() async -> [ToolDefinition] {
        [ToolDefinition(name: toolName, description: "pending tool", parameters: [], type: .function)]
    }

    func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        ToolResult(success: true, content: "pending", toolCallId: toolCall.id)
    }

    func executeToolOutcome(_ toolCall: ToolCall) async throws -> ToolExecutionOutcome {
        .pending(PendingToolHandle(
            handleID: "handle-\(toolCall.id ?? UUID().uuidString)",
            toolCallID: toolCall.id ?? "unknown",
            provider: name
        ))
    }
}

struct RoutingSafetyToolProvider: ToolProvider {
    var name: String { "RoutingSafetyToolProvider" }
    let safetiesByToolName: [String: ToolParallelSafety]

    func availableTools() async -> [ToolDefinition] {
        safetiesByToolName.keys.sorted().map {
            ToolDefinition(name: $0, description: "tool \($0)", parameters: [], type: .function)
        }
    }

    func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        ToolResult(success: true, content: "ok-\(toolCall.name)", toolCallId: toolCall.id)
    }

    func parallelSafety(for toolCall: ToolCall) async -> ToolParallelSafety {
        safetiesByToolName[toolCall.name] ?? .unknown
    }
}

struct StaticPreDispatchPolicyEvaluator: ToolPreDispatchPolicyEvaluating {
    let decisionByToolName: [String: ToolPreDispatchPolicyDecision]

    func decide(_ context: ToolPreDispatchPolicyContext) async -> ToolPreDispatchPolicyDecision {
        decisionByToolName[context.request.toolName]
            ?? ToolPreDispatchPolicyDecision(decision: .allow)
    }
}


@Suite struct SwiftAgentKitOrchestratorTests {
    
    @Test("SwiftAgentKitOrchestrator can be initialized with LLM")
    func testInitialization() async throws {
        let mockLLM = MockLLM(model: "test-model", logger: Logger(label: "MockLLM"))
        let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM)
        
        #expect(await orchestrator.llm is MockLLM)
        #expect(mockLLM.getModelName() == "test-model")
    }
    
    @Test("Orchestrator works with QueuedLLM wrapper")
    func testOrchestratorWithQueuedLLM() async throws {
        let mockLLM = MockLLM(model: "queued-test", logger: Logger(label: "MockLLM"))
        let queuedLLM = QueuedLLM(baseLLM: mockLLM)
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: queuedLLM,
            config: OrchestratorConfig(streamingEnabled: false)
        )

        let messages = [Message(id: UUID(), role: .user, content: "Hello")]
        try await orchestrator.updateConversation(messages)
    }

    @Test("OrchestratorConfig can be initialized with default values")
    func testOrchestratorConfigDefaultInit() throws {
        let config = OrchestratorConfig()
        
        #expect(config.streamingEnabled == false)
        #expect(config.mcpEnabled == false)
        #expect(config.a2aIntegration == .disabled)
        #expect(config.a2aEnabled == false)
        #expect(config.acpIntegration == .disabled)
        #expect(config.acpEnabled == false)
        #expect(config.maxTokens == nil)
        #expect(config.temperature == nil)
        #expect(config.topP == nil)
        #expect(config.additionalParameters == nil)
        #expect(config.maxAgenticStepsPerUpdate == nil)
        #expect(config.toolInvocationPolicy == .automatic)
        #expect(config.rejectAssistantTurnWithNoToolCallsWhenToolsAvailable == false)
        #expect(config.maxCorrectionRetries == 0)
    }
    
    @Test("OrchestratorConfig can be initialized with custom values")
    func testOrchestratorConfigCustomInit() throws {
        let config = OrchestratorConfig(
            streamingEnabled: true,
            mcpEnabled: true,
            a2aEnabled: true
        )
        
        #expect(config.streamingEnabled == true)
        #expect(config.mcpEnabled == true)
        #expect(config.a2aIntegration == .inlineExecution)
        #expect(config.a2aEnabled == true)
    }

    @Test("OrchestratorConfig a2aIntegration primary init accepts registrationOnly")
    func testOrchestratorConfigA2AIntegrationPrimaryInit() throws {
        let config = OrchestratorConfig(a2aIntegration: .registrationOnly)
        #expect(config.a2aIntegration == .registrationOnly)
        #expect(config.a2aEnabled == false)
    }

    @Test("Deprecated a2aEnabled init maps to a2aIntegration")
    func testDeprecatedA2aEnabledInitMapsToIntegration() throws {
        let enabled = OrchestratorConfig(a2aEnabled: true)
        #expect(enabled.a2aIntegration == .inlineExecution)
        #expect(enabled.a2aEnabled == true)

        let disabled = OrchestratorConfig(a2aEnabled: false)
        #expect(disabled.a2aIntegration == .disabled)
        #expect(disabled.a2aEnabled == false)
    }

    @Test("OrchestratorConfig acpIntegration primary init accepts registrationOnly")
    func testOrchestratorConfigACPIntegrationPrimaryInit() throws {
        let config = OrchestratorConfig(acpIntegration: .registrationOnly)
        #expect(config.acpIntegration == .registrationOnly)
        #expect(config.acpEnabled == false)
    }

    @Test("Deprecated acpEnabled init maps to acpIntegration")
    func testDeprecatedAcpEnabledInitMapsToIntegration() throws {
        let enabled = OrchestratorConfig(acpEnabled: true)
        #expect(enabled.acpIntegration == .inlineExecution)
        #expect(enabled.acpEnabled == true)

        let disabled = OrchestratorConfig(acpEnabled: false)
        #expect(disabled.acpIntegration == .disabled)
        #expect(disabled.acpEnabled == false)
    }

    // MARK: - A2A integration mode tests

    @Test("A2A integration disabled excludes agents from catalog")
    func testA2AIntegrationDisabledExcludesCatalog() async throws {
        let agentName = "DisabledCatalogAgent"
        let (orchestrator, _) = try await makeOrchestratorWithRecordingA2AClient(
            integration: .disabled,
            agentName: agentName
        )

        let tools = await orchestrator.allAvailableTools
        let descriptors = await orchestrator.allRegisteredTools
        #expect(tools.contains { $0.name == agentName } == false)
        #expect(descriptors.contains { $0.definition.name == agentName } == false)
    }

    @Test("A2A integration registrationOnly merges catalog without inline agentCall")
    func testA2AIntegrationRegistrationOnlyCatalogWithoutInlineExecution() async throws {
        let agentName = "RegOnlyAgent"
        let (orchestrator, client) = try await makeOrchestratorWithRecordingA2AClient(
            integration: .registrationOnly,
            agentName: agentName
        )

        let tools = await orchestrator.allAvailableTools
        let descriptors = await orchestrator.allRegisteredTools
        #expect(tools.contains { $0.name == agentName })
        #expect(descriptors.contains { $0.definition.name == agentName && $0.definition.type == .a2aAgent && $0.source == .a2a })

        let outcome = await orchestrator.invokeTool(
            ToolInvocationRequest(
                toolName: agentName,
                argumentsPayload: .object(["instructions": .string("Run task")]),
                source: .direct,
                callerProvenance: "registration-only-test"
            )
        )

        switch outcome {
        case .completed(let result, _):
            #expect(result.success == false)
            #expect(result.error?.contains("No provider handled tool") == true)
        default:
            Issue.record("Expected completed fallback outcome")
        }
        #expect(await client.streamMessageCallCount == 0)
    }

    @Test("A2A integration inlineExecution invokes agentCall")
    func testA2AIntegrationInlineExecutionInvokesAgentCall() async throws {
        let agentName = "InlineExecAgent"
        let message = A2AMessage(
            role: "agent",
            parts: [.text(text: "done")],
            messageId: UUID().uuidString
        )
        let events = [wrapMessageResult(.message(message))]
        let (orchestrator, client) = try await makeOrchestratorWithRecordingA2AClient(
            integration: .inlineExecution,
            agentName: agentName,
            events: events
        )

        let outcome = await orchestrator.invokeTool(
            ToolInvocationRequest(
                toolName: agentName,
                argumentsPayload: .object(["instructions": .string("Run task")]),
                source: .direct,
                callerProvenance: "inline-exec-test"
            )
        )

        switch outcome {
        case .completed(let result, _):
            #expect(result.success == true)
            #expect(result.content == "done")
        default:
            Issue.record("Expected completed outcome from inline A2A execution")
        }
        #expect(await client.streamMessageCallCount == 1)
    }

    // MARK: - ACP integration mode tests

    @Test("ACP integration disabled excludes agents from catalog")
    func testACPIntegrationDisabledExcludesCatalog() async throws {
        let agentName = "DisabledACPAgent"
        let (orchestrator, _) = try await makeOrchestratorWithRecordingACPClient(
            integration: .disabled,
            agentName: agentName
        )

        let tools = await orchestrator.allAvailableTools
        let descriptors = await orchestrator.allRegisteredTools
        #expect(tools.contains { $0.name == agentName } == false)
        #expect(descriptors.contains { $0.definition.name == agentName } == false)
    }

    @Test("ACP integration registrationOnly merges catalog without inline agentCall")
    func testACPIntegrationRegistrationOnlyCatalogWithoutInlineExecution() async throws {
        let agentName = "RegOnlyACPAgent"
        let (orchestrator, client) = try await makeOrchestratorWithRecordingACPClient(
            integration: .registrationOnly,
            agentName: agentName
        )

        let tools = await orchestrator.allAvailableTools
        let descriptors = await orchestrator.allRegisteredTools
        #expect(tools.contains { $0.name == agentName })
        #expect(descriptors.contains { $0.definition.name == agentName && $0.definition.type == .acpAgent && $0.source == .acp })

        let outcome = await orchestrator.invokeTool(
            ToolInvocationRequest(
                toolName: agentName,
                argumentsPayload: .object(["instructions": .string("Run task")]),
                source: .direct,
                callerProvenance: "acp-registration-only-test"
            )
        )

        switch outcome {
        case .completed(let result, _):
            #expect(result.success == false)
            #expect(result.error?.contains("No provider handled tool") == true)
        default:
            Issue.record("Expected completed fallback outcome")
        }
        #expect(await client.promptStreamCallCount == 0)
    }

    @Test("ACP integration inlineExecution invokes agentCall")
    func testACPIntegrationInlineExecutionInvokesAgentCall() async throws {
        let agentName = "InlineExecACPAgent"
        let (orchestrator, client) = try await makeOrchestratorWithRecordingACPClient(
            integration: .inlineExecution,
            agentName: agentName,
            responseText: "done"
        )

        let outcome = await orchestrator.invokeTool(
            ToolInvocationRequest(
                toolName: agentName,
                argumentsPayload: .object(["instructions": .string("Run task")]),
                source: .direct,
                callerProvenance: "acp-inline-exec-test"
            )
        )

        switch outcome {
        case .completed(let result, _):
            #expect(result.success == true)
            #expect(result.content == "done")
        default:
            Issue.record("Expected completed outcome from inline ACP execution")
        }
        #expect(await client.promptStreamCallCount == 1)
    }
    
    @Test("OrchestratorConfig can be initialized with LLM request params")
    func testOrchestratorConfigLLMRequestParams() throws {
        let extraParams = JSON.object(["frequency_penalty": .double(0.5)])
        let config = OrchestratorConfig(
            maxTokens: 4096,
            temperature: 0.7,
            topP: 0.9,
            additionalParameters: extraParams
        )
        
        #expect(config.maxTokens == 4096)
        #expect(config.temperature == 0.7)
        #expect(config.topP == 0.9)
        #expect(config.additionalParameters != nil)
        if case .object(let dict) = config.additionalParameters!,
           case .double(let val) = dict["frequency_penalty"] {
            #expect(val == 0.5)
        }
    }

    @Test("Orchestrator publishes LLM runtime states during conversation update")
    func testOrchestratorPublishesRuntimeStates() async throws {
        let baseLLM = MockLLM(model: "test-model", logger: Logger(label: "MockLLM"))
        let trackedLLM = StatefulLLM(baseLLM: baseLLM)
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: trackedLLM,
            config: OrchestratorConfig(streamingEnabled: false)
        )

        let messages = [Message(id: UUID(), role: .user, content: "Hello there")]
        let observed = try await collectLLMRuntimeStatesAfter(stream: orchestrator.llmStateUpdates) {
            try await orchestrator.updateConversation(messages)
        }

        #expect(observed.first == .idle(.ready))
        #expect(observed.contains(.generating(.reasoning)))
        // `StatefulLLM.send` does not emit `.responding`; orchestrator must not overwrite idle with a stale `.responding` after the call completes.
        #expect(observed.contains(.idle(.completed)))
        #expect(observed.last == .idle(.ready))
    }

    @Test("currentOrchestrationSnapshot has no stale in-flight request or agentic phases after updateConversation")
    func testOrchestrationSnapshotConsistentAfterUpdateConversation() async throws {
        let baseLLM = MockLLM(model: "test-model", logger: Logger(label: "MockLLM"))
        let trackedLLM = StatefulLLM(baseLLM: baseLLM)
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: trackedLLM,
            config: OrchestratorConfig(streamingEnabled: false)
        )
        let messages = [Message(id: UUID(), role: .user, content: "Hello there")]
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(messages)
        }
        let snap = await orchestrator.currentOrchestrationSnapshot()
        #expect(!snap.llmRuntime.isGeneratingTokens)
        let hasStaleRequest = snap.perRequestStates.values.contains {
            switch $0 {
            case .active, .generating, .streaming: return true
            default: return false
            }
        }
        #expect(!hasStaleRequest)
        let hasStaleAgentic = snap.agenticLoopStates.values.contains {
            switch $0 {
            case .started, .llmCall, .betweenIterations: return true
            default: return false
            }
        }
        #expect(!hasStaleAgentic)
    }
    
    @Test("updateConversation passes maxTokens, temperature, topP, and additionalParameters to LLM")
    func testUpdateConversationPassesLLMRequestParams() async throws {
        let configCapture = ConfigCapture()
        let extraParams = JSON.object(["frequency_penalty": .double(0.3)])
        let config = OrchestratorConfig(
            streamingEnabled: false,
            maxTokens: 2048,
            temperature: 0.5,
            topP: 0.95,
            additionalParameters: extraParams
        )
        let capturingLLM = CapturingMockLLM(
            logger: Logger(label: "ConfigCaptureLLM"),
            toolCallsToReturn: [],
            configCapture: configCapture
        )
        let orchestrator = SwiftAgentKitOrchestrator(llm: capturingLLM, config: config)
        
        let initialMessages = [Message(id: UUID(), role: .user, content: "Hello")]
        let messageStream = await orchestrator.messageStream
        
        actor MessageCollector {
            var messages: [Message] = []
            func append(_ message: Message) { messages.append(message) }
        }
        let collector = MessageCollector()
        try await drainPublishedMessagesWhileRunning(messageStream, processMessage: { message in
            await collector.append(message)
        }) {
            try await orchestrator.updateConversation(initialMessages, availableTools: [])
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        let configs = await configCapture.getConfigs()
        #expect(configs.count >= 1)
        let requestConfig = configs[0]
        #expect(requestConfig.maxTokens == 2048)
        #expect(requestConfig.temperature == 0.5)
        #expect(requestConfig.topP == 0.95)
        #expect(requestConfig.additionalParameters != nil)
        if case .object(let dict) = requestConfig.additionalParameters!,
           case .double(let val) = dict["frequency_penalty"] {
            #expect(val == 0.3)
        }
        #expect(requestConfig.stream == false)
    }
    
    @Test("updateConversation passes LLM request params when streaming")
    func testUpdateConversationPassesLLMRequestParamsStreaming() async throws {
        let configCapture = ConfigCapture()
        let config = OrchestratorConfig(
            streamingEnabled: true,
            maxTokens: 1024,
            temperature: 0.8,
            topP: 0.85
        )
        let capturingLLM = CapturingMockLLM(
            logger: Logger(label: "ConfigCaptureLLM"),
            toolCallsToReturn: [],
            configCapture: configCapture
        )
        let orchestrator = SwiftAgentKitOrchestrator(llm: capturingLLM, config: config)
        
        let initialMessages = [Message(id: UUID(), role: .user, content: "Hi")]
        let messageStream = await orchestrator.messageStream
        
        actor MessageCollector {
            var messages: [Message] = []
            func append(_ message: Message) { messages.append(message) }
        }
        let collector = MessageCollector()
        try await drainPublishedMessagesWhileRunning(messageStream, processMessage: { message in
            await collector.append(message)
        }) {
            try await orchestrator.updateConversation(initialMessages, availableTools: [])
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        let configs = await configCapture.getConfigs()
        #expect(configs.count >= 1)
        let requestConfig = configs[0]
        #expect(requestConfig.maxTokens == 1024)
        #expect(requestConfig.temperature == 0.8)
        #expect(requestConfig.topP == 0.85)
        #expect(requestConfig.stream == true)
    }
    
    @Test("SwiftAgentKitOrchestrator can be initialized with custom config")
    func testOrchestratorWithCustomConfig() async throws {
        let mockLLM = MockLLM(model: "test-model", logger: Logger(label: "MockLLM"))
        let config = OrchestratorConfig(
            streamingEnabled: true,
            mcpEnabled: true,
            a2aEnabled: false
        )
        let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM, config: config)
        
        #expect(await orchestrator.llm is MockLLM)
        #expect(await orchestrator.config.streamingEnabled == true)
        #expect(await orchestrator.config.mcpEnabled == true)
        #expect(await orchestrator.config.a2aIntegration == .disabled)
        #expect(await orchestrator.config.a2aEnabled == false)
    }
    
    @Test("updateConversation handles synchronous responses")
    func testUpdateConversationSync() async throws {
        let mockLLM = MockLLM(model: "test-model", logger: Logger(label: "MockLLM"))
        let config = OrchestratorConfig(streamingEnabled: false)
        let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM, config: config)
        
        let initialMessages = [
            Message(id: UUID(), role: .user, content: "Hello"),
            Message(id: UUID(), role: .assistant, content: "Hi there!")
        ]
        
        // Get the message stream
        let messageStream = await orchestrator.messageStream
        
        // Use an actor to safely track messages
        actor MessageCollector {
            var messages: [Message] = []
            func append(_ message: Message) {
                messages.append(message)
            }
        }
        let collector = MessageCollector()
        
        try await drainPublishedMessagesWhileRunning(messageStream, processMessage: { message in
            #expect(message.role == .assistant)
            await collector.append(message)
        }) {
            try await orchestrator.updateConversation(initialMessages, availableTools: [])
        }
        
        // Give a small delay to allow stream listeners to process messages
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        let finalConversation = await collector.messages
        #expect(finalConversation.count >= 1) // At least one new message
        #expect(finalConversation.last?.role == .assistant)
        #expect(finalConversation.last?.content.contains("Mock response") == true)
    }
    
    @Test("updateConversation handles streaming responses")
    func testUpdateConversationStreaming() async throws {
        let mockLLM = MockLLM(model: "test-model", logger: Logger(label: "MockLLM"))
        let config = OrchestratorConfig(streamingEnabled: true)
        let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM, config: config)
        
        let initialMessages = [
            Message(id: UUID(), role: .user, content: "Hello")
        ]
        
        // Get the message stream
        let messageStream = await orchestrator.messageStream
        
        // Use an actor to safely track messages
        actor MessageCollector {
            var count = 0
            var messages: [Message] = []
            func append(_ message: Message) {
                count += 1
                messages.append(message)
            }
        }
        let collector = MessageCollector()
        
        try await drainPublishedMessagesWhileRunning(messageStream, processMessage: { message in
            #expect(message.role == .assistant)
            await collector.append(message)
        }) {
            try await orchestrator.updateConversation(initialMessages, availableTools: [])
        }
        
        // Give a small delay to allow stream listeners to process messages
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        let streamCount = await collector.count
        let finalConversation = await collector.messages
        #expect(streamCount > 0) // Should have received some streaming chunks
        #expect(finalConversation.count >= 1) // At least one new message
        #expect(finalConversation.last?.role == .assistant)
    }

    @Test("partialFragmentsStream classifies streaming chunks; partialContentStream yields assistant text only")
    func testPartialFragmentsStreamVsLegacyTextStream() async throws {
        let logger = Logger(label: "FragmentStreamingMockLLM")
        let llm = FragmentStreamingMockLLM(logger: logger)
        let config = OrchestratorConfig(streamingEnabled: true)
        let orchestrator = SwiftAgentKitOrchestrator(llm: llm, config: config)

        let messageStream = await orchestrator.messageStream
        let fragmentsStream = await orchestrator.partialFragmentsStream
        let textStream = await orchestrator.partialContentStream

        let collectFrags = Task { () -> [PartialFragment] in
            var collected: [PartialFragment] = []
            for await fragment in fragmentsStream {
                collected.append(fragment)
            }
            return collected
        }
        let collectText = Task { () -> [String] in
            var collected: [String] = []
            for await text in textStream {
                collected.append(text)
            }
            return collected
        }

        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "Hi")],
                availableTools: []
            )
        }

        let frags = await collectFrags.value
        let texts = await collectText.value

        #expect(frags == [
            .reasoning("step"),
            .text("Hello"),
            .toolCall(id: "call_x", name: "todo", argumentsFragment: "{\"q\":")
        ])
        #expect(texts == ["Hello"])
    }
    
    @Test("updateConversation preserves original message order")
    func testUpdateConversationPreservesOrder() async throws {
        let mockLLM = MockLLM(model: "test-model", logger: Logger(label: "MockLLM"))
        let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM)
        
        let initialMessages = [
            Message(id: UUID(), role: .user, content: "First message"),
            Message(id: UUID(), role: .assistant, content: "First response"),
            Message(id: UUID(), role: .user, content: "Second message")
        ]
        
        // Get the message stream
        let messageStream = await orchestrator.messageStream
        
        // Use an actor to safely track messages
        actor MessageCollector {
            var messages: [Message] = []
            func append(_ message: Message) {
                messages.append(message)
            }
        }
        let collector = MessageCollector()
        
        try await drainPublishedMessagesWhileRunning(messageStream, processMessage: { message in
            #expect(message.role == .assistant)
            await collector.append(message)
        }) {
            try await orchestrator.updateConversation(initialMessages, availableTools: [])
        }
        
        // Give a small delay to allow stream listeners to process messages
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        let finalConversation = await collector.messages
        #expect(finalConversation.count >= 1) // At least one new message
        
        // Check that we received at least one new message
        #expect(finalConversation.last?.role == .assistant) // New response
    }
    
    @Test("updateConversation handles available tools")
    func testUpdateConversationWithTools() async throws {
        let mockLLM = MockLLM(model: "test-model", logger: Logger(label: "MockLLM"))
        let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM)
        
        let initialMessages = [
            Message(id: UUID(), role: .user, content: "Hello")
        ]
        
        let availableTools = [
            ToolDefinition(
                name: "test_tool",
                description: "A test tool",
                parameters: [
                    .init(name: "input", description: "Input parameter", type: "string", required: true)
                ],
                type: .function
            )
        ]
        
        // Get the message stream
        let messageStream = await orchestrator.messageStream
        
        // Use an actor to safely track messages
        actor MessageCollector {
            var messages: [Message] = []
            func append(_ message: Message) {
                messages.append(message)
            }
        }
        let collector = MessageCollector()
        
        try await drainPublishedMessagesWhileRunning(messageStream, processMessage: { message in
            #expect(message.role == .assistant)
            await collector.append(message)
        }) {
            try await orchestrator.updateConversation(initialMessages, availableTools: availableTools)
        }
        
        // Give a small delay to allow stream listeners to process messages
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        let finalConversation = await collector.messages
        #expect(finalConversation.count >= 1) // At least one new message
        #expect(finalConversation.last?.role == .assistant)
    }
    
    @Test("availableTools property returns empty array when no managers are configured")
    func testAvailableToolsEmpty() async throws {
        let mockLLM = MockLLM(model: "test-model", logger: Logger(label: "MockLLM"))
        let config = OrchestratorConfig(mcpEnabled: false, a2aEnabled: false)
        let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM, config: config)
        
        let tools = await orchestrator.allAvailableTools
        #expect(tools.isEmpty)
    }
    
    @Test("availableTools property respects configuration flags")
    func testAvailableToolsRespectsConfig() async throws {
        let mockLLM = MockLLM(model: "test-model", logger: Logger(label: "MockLLM"))
        
        // Test with MCP enabled but no manager provided
        let config1 = OrchestratorConfig(mcpEnabled: true, a2aEnabled: false)
        let orchestrator1 = SwiftAgentKitOrchestrator(llm: mockLLM, config: config1)
        let tools1 = await orchestrator1.allAvailableTools
        #expect(tools1.isEmpty)
        
        // Test with A2A enabled but no manager provided
        let config2 = OrchestratorConfig(mcpEnabled: false, a2aEnabled: true)
        let orchestrator2 = SwiftAgentKitOrchestrator(llm: mockLLM, config: config2)
        let tools2 = await orchestrator2.allAvailableTools
        #expect(tools2.isEmpty)
    }
    
    // MARK: - Tool Call Execution Tests
    
    @Test("Tool calls with toolCallId are handled correctly")
    func testToolCallsWithId() async throws {
        let toolCallId = "test-tool-call-1"
        let toolCall = ToolCall(
            name: "test_tool",
            arguments: try! JSON(["input": "test"]),
            id: toolCallId
        )
        
        // Create a mock LLM that returns tool calls
        let mockLLM = MockLLM(
            model: "test-model",
            logger: Logger(label: "MockLLM"),
            toolCallsToReturn: [toolCall],
            shouldReturnToolCalls: true
        )
        
        // Create mock managers that return responses
        let mcpManager = MCPManager(connectionTimeout: 5.0, logger: Logger(label: "TestMCP"))
        let a2aManager = A2AManager(logger: Logger(label: "TestA2A"))
        
        let config = OrchestratorConfig(mcpEnabled: true, a2aEnabled: true)
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: mockLLM,
            config: config,
            mcpManager: mcpManager,
            a2aManager: a2aManager
        )
        
        let initialMessages = [
            Message(id: UUID(), role: .user, content: "Use the test tool")
        ]
        
        // Collect all messages
        actor MessageCollector {
            var messages: [Message] = []
            func append(_ message: Message) {
                messages.append(message)
            }
        }
        let collector = MessageCollector()
        
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream, processMessage: { message in
            await collector.append(message)
        }) {
            try await orchestrator.updateConversation(initialMessages, availableTools: [])
        }
        
        // Give time for processing
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        
        let messages = await collector.messages
        
        // Should have at least the assistant message with tool calls
        #expect(messages.count >= 1)
        
        // Find tool response messages
        let toolMessages = messages.filter { $0.role == .tool }
        
        // If tool calls were executed, verify toolCallId is set
        if !toolMessages.isEmpty {
            for toolMessage in toolMessages {
                // Tool messages should have toolCallId matching the original tool call
                #expect(toolMessage.toolCallId == toolCallId)
            }
        }
    }
    
    @Test("LLMResponse toolCallId is preserved when creating tool response messages")
    func testLLMResponseToolCallIdPreserved() throws {
        let toolCallId = "test-call-id-123"
        let responseContent = "Tool execution result"
        
        // Create an LLMResponse with toolCallId
        let response = LLMResponse.complete(
            content: responseContent,
            toolCallId: toolCallId
        )
        
        // Verify toolCallId is set
        #expect(response.toolCallId == toolCallId)
        #expect(response.content == responseContent)
        
        // Create a Message from the response
        let message = Message(
            id: UUID(),
            role: .tool,
            content: response.content,
            toolCalls: response.toolCalls,
            toolCallId: response.toolCallId
        )
        
        // Verify the message has the correct toolCallId
        #expect(message.toolCallId == toolCallId)
        #expect(message.content == responseContent)
        #expect(message.role == .tool)
    }
    
    @Test("Multiple tool calls with different IDs are handled correctly")
    func testMultipleToolCallsWithDifferentIds() throws {
        let toolCallId1 = "call-1"
        let toolCallId2 = "call-2"
        
        // Create responses with matching toolCallIds
        let response1 = LLMResponse.complete(
            content: "Result 1",
            toolCallId: toolCallId1
        )
        let response2 = LLMResponse.complete(
            content: "Result 2",
            toolCallId: toolCallId2
        )
        
        // Verify each response has the correct toolCallId
        #expect(response1.toolCallId == toolCallId1)
        #expect(response2.toolCallId == toolCallId2)
        
        // Create messages from responses
        let message1 = Message(
            id: UUID(),
            role: .tool,
            content: response1.content,
            toolCalls: response1.toolCalls,
            toolCallId: response1.toolCallId
        )
        let message2 = Message(
            id: UUID(),
            role: .tool,
            content: response2.content,
            toolCalls: response2.toolCalls,
            toolCallId: response2.toolCallId
        )
        
        // Verify messages have correct toolCallIds
        #expect(message1.toolCallId == toolCallId1)
        #expect(message2.toolCallId == toolCallId2)
        #expect(message1.toolCallId != message2.toolCallId)
    }
    
    @Test("Tool calls with nil ID are handled correctly")
    func testToolCallsWithNilId() throws {
        // Create response with nil toolCallId
        let response = LLMResponse.complete(
            content: "Result",
            toolCallId: nil
        )
        
        // Verify nil is handled correctly
        #expect(response.toolCallId == nil)
        
        // Create message from response
        let message = Message(
            id: UUID(),
            role: .tool,
            content: response.content,
            toolCalls: response.toolCalls,
            toolCallId: response.toolCallId
        )
        
        // Verify message has nil toolCallId
        #expect(message.toolCallId == nil)
    }
    
    @Test("LLMResponse convenience methods preserve toolCallId")
    func testLLMResponseConvenienceMethodsPreserveToolCallId() throws {
        let toolCallId = "preserved-id"
        let originalResponse = LLMResponse.complete(
            content: "Original",
            toolCallId: toolCallId
        )
        
        // Test appending tool calls
        let withToolCalls = originalResponse.appending(toolCalls: [
            ToolCall(name: "test", arguments: .object([:]), id: "tc1")
        ])
        #expect(withToolCalls.toolCallId == toolCallId)
        
        // Test updating content
        let updatedContent = originalResponse.updatingContent(with: "Updated")
        #expect(updatedContent.toolCallId == toolCallId)
        
        // Test removing tool calls
        let withoutToolCalls = originalResponse.removingToolCalls()
        #expect(withoutToolCalls.toolCallId == toolCallId)
        
        // Test marking complete
        let markedComplete = originalResponse.markingComplete()
        #expect(markedComplete.toolCallId == toolCallId)
        
        // Test marking incomplete
        let markedIncomplete = originalResponse.markingIncomplete()
        #expect(markedIncomplete.toolCallId == toolCallId)
    }
    
    @Test("Tool calls without IDs get IDs generated automatically")
    func testToolCallsWithoutIdsGetGenerated() async throws {
        // Create a tool call without an ID (simulating models like llama4:scout)
        let toolCallWithoutId = ToolCall(
            name: "test_tool",
            arguments: try! JSON(["input": "test"]),
            id: nil
        )
        
        // Create a mock LLM that returns tool calls without IDs
        let mockLLM = MockLLM(
            model: "test-model",
            logger: Logger(label: "MockLLM"),
            toolCallsToReturn: [toolCallWithoutId],
            shouldReturnToolCalls: true
        )
        
        let config = OrchestratorConfig(streamingEnabled: false)
        let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM, config: config)
        
        let initialMessages = [
            Message(id: UUID(), role: .user, content: "Use the test tool")
        ]
        
        // Collect all messages
        actor MessageCollector {
            var messages: [Message] = []
            func append(_ message: Message) {
                messages.append(message)
            }
        }
        let collector = MessageCollector()
        
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream, processMessage: { message in
            await collector.append(message)
        }) {
            try await orchestrator.updateConversation(initialMessages, availableTools: [])
        }
        
        // Give time for processing
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        
        let messages = await collector.messages
        
        // Find the assistant message with tool calls
        let assistantMessages = messages.filter { $0.role == .assistant && !$0.toolCalls.isEmpty }
        #expect(!assistantMessages.isEmpty)
        
        // Verify that tool calls now have IDs
        let toolCalls = assistantMessages.first?.toolCalls ?? []
        #expect(!toolCalls.isEmpty)
        for toolCall in toolCalls {
            // All tool calls should have IDs now (even if they didn't originally)
            #expect(toolCall.id != nil)
            // Generated IDs should follow the "call_" prefix pattern
            if let id = toolCall.id {
                #expect(id.hasPrefix("call_"))
            }
        }
        
        // Find tool response messages
        let toolMessages = messages.filter { $0.role == .tool }
        
        // If tool calls were executed, verify toolCallId is set
        if !toolMessages.isEmpty {
            for toolMessage in toolMessages {
                // Tool messages should have toolCallId matching the generated tool call ID
                #expect(toolMessage.toolCallId != nil)
                if let toolCallId = toolMessage.toolCallId {
                    #expect(toolCallId.hasPrefix("call_"))
                }
            }
        }
    }
    
    // MARK: - Tool response content (images, files, data) tests
    
    func makeAgentCard(name: String) -> AgentCard {
        AgentCard(
            name: name,
            description: "Test agent",
            url: "https://example.com/\(name)",
            version: "1.0",
            capabilities: AgentCard.AgentCapabilities(streaming: true),
            defaultInputModes: ["text/plain"],
            defaultOutputModes: ["text/plain"],
            skills: []
        )
    }
    
    @Test("Tool response message includes images when A2A returns image artifact")
    func testToolResponseMessageIncludesImagesWhenA2AReturnsImages() async throws {
        let agentName = "ImageAgent"
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        guard let pngData = Data(base64Encoded: pngBase64) else { Issue.record("Bad PNG"); return }
        
        let card = makeAgentCard(name: agentName)
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [.file(data: pngData, url: nil)],
            name: "out.png"
        )
        let event = TaskArtifactUpdateEvent(
            taskId: UUID().uuidString,
            contextId: UUID().uuidString,
            artifact: artifact,
            append: false,
            lastChunk: true
        )
        let mockClient = MockA2AStreamClientForOrchestrator(agentCard: card, events: [wrapMessageResult(.taskArtifactUpdate(event))])
        
        let a2aManager = A2AManager(logger: Logger(label: "TestA2A"))
        try await a2aManager.initialize(clients: [mockClient])
        
        let toolCall = ToolCall(
            name: agentName,
            arguments: .object(["instructions": .string("Generate image")]),
            id: "call-1"
        )
        let capture = SendCapture()
        let capturingLLM = CapturingMockLLM(logger: Logger(label: "Capture"), toolCallsToReturn: [toolCall], capture: capture)
        
        let config = OrchestratorConfig(streamingEnabled: false, mcpEnabled: false, a2aEnabled: true)
        let orchestrator = SwiftAgentKitOrchestrator(llm: capturingLLM, config: config, a2aManager: a2aManager)
        
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "Generate an image")],
                availableTools: []
            )
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        let invocations = await capture.getInvocations()
        #expect(invocations.count >= 2)
        let invocationWithTool = invocations.first { $0.contains { $0.role == .tool } }
        #expect(invocationWithTool != nil)
        let toolMessage = invocationWithTool!.first { $0.role == .tool }
        #expect(toolMessage != nil)
        #expect(toolMessage!.images.count == 1)
        #expect(toolMessage!.images[0].imageData == pngData)
    }
    
    @Test("Tool response message includes file summary when A2A returns file reference")
    func testToolResponseMessageIncludesFileSummaryWhenA2AReturnsFiles() async throws {
        let agentName = "FileAgent"
        let fileURL = URL(string: "https://example.com/doc.pdf")!
        let card = makeAgentCard(name: agentName)
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [.file(data: nil, url: fileURL)],
            name: "doc.pdf"
        )
        let event = TaskArtifactUpdateEvent(
            taskId: UUID().uuidString,
            contextId: UUID().uuidString,
            artifact: artifact,
            append: false,
            lastChunk: true
        )
        let mockClient = MockA2AStreamClientForOrchestrator(agentCard: card, events: [wrapMessageResult(.taskArtifactUpdate(event))])
        
        let a2aManager = A2AManager(logger: Logger(label: "TestA2A"))
        try await a2aManager.initialize(clients: [mockClient])
        
        let toolCall = ToolCall(
            name: agentName,
            arguments: .object(["instructions": .string("Get file")]),
            id: "call-1"
        )
        let capture = SendCapture()
        let capturingLLM = CapturingMockLLM(logger: Logger(label: "Capture"), toolCallsToReturn: [toolCall], capture: capture)
        let config = OrchestratorConfig(streamingEnabled: false, mcpEnabled: false, a2aEnabled: true)
        let orchestrator = SwiftAgentKitOrchestrator(llm: capturingLLM, config: config, a2aManager: a2aManager)
        
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "Get the document")],
                availableTools: []
            )
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        let invocations = await capture.getInvocations()
        let invocationWithTool = invocations.first { $0.contains { $0.role == .tool } }
        #expect(invocationWithTool != nil)
        let toolMessage = invocationWithTool!.first { $0.role == .tool }
        #expect(toolMessage != nil)
        #expect(toolMessage!.content.contains("Attachments:") == true)
        #expect(toolMessage!.content.contains("doc.pdf") == true)
        #expect(toolMessage!.content.contains(fileURL.absoluteString) == true)
    }
    
    @Test("Tool response message includes both images and file summary when A2A returns both")
    func testToolResponseMessageIncludesImagesAndFileSummaryWhenA2AReturnsBoth() async throws {
        let agentName = "MediaAgent"
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        guard let pngData = Data(base64Encoded: pngBase64) else { Issue.record("Bad PNG"); return }
        let fileURL = URL(string: "https://example.com/ref.pdf")!
        
        let card = makeAgentCard(name: agentName)
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [
                .text(text: "Here is the result"),
                .file(data: pngData, url: nil),
                .file(data: nil, url: fileURL)
            ],
            name: "media"
        )
        let event = TaskArtifactUpdateEvent(
            taskId: UUID().uuidString,
            contextId: UUID().uuidString,
            artifact: artifact,
            append: false,
            lastChunk: true
        )
        let mockClient = MockA2AStreamClientForOrchestrator(agentCard: card, events: [wrapMessageResult(.taskArtifactUpdate(event))])
        
        let a2aManager = A2AManager(logger: Logger(label: "TestA2A"))
        try await a2aManager.initialize(clients: [mockClient])
        
        let toolCall = ToolCall(
            name: agentName,
            arguments: .object(["instructions": .string("Generate")]),
            id: "call-1"
        )
        let capture = SendCapture()
        let capturingLLM = CapturingMockLLM(logger: Logger(label: "Capture"), toolCallsToReturn: [toolCall], capture: capture)
        let config = OrchestratorConfig(streamingEnabled: false, mcpEnabled: false, a2aEnabled: true)
        let orchestrator = SwiftAgentKitOrchestrator(llm: capturingLLM, config: config, a2aManager: a2aManager)
        
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "Generate media")],
                availableTools: []
            )
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        let invocations = await capture.getInvocations()
        let invocationWithTool = invocations.first { $0.contains { $0.role == .tool } }
        #expect(invocationWithTool != nil)
        let toolMessage = invocationWithTool!.first { $0.role == .tool }
        #expect(toolMessage != nil)
        #expect(toolMessage!.content.contains("Here is the result") == true)
        #expect(toolMessage!.content.contains("Attachments:") == true)
        #expect(toolMessage!.images.count == 1)
        #expect(toolMessage!.images[0].imageData == pngData)
    }
    
    @Test("Tool response message with only images has attachment-style content when no text")
    func testToolResponseMessageOnlyImagesNoText() async throws {
        let agentName = "ImageOnlyAgent"
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        guard let pngData = Data(base64Encoded: pngBase64) else { Issue.record("Bad PNG"); return }
        
        let card = makeAgentCard(name: agentName)
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [.file(data: pngData, url: nil)],
            name: "only.png"
        )
        let event = TaskArtifactUpdateEvent(
            taskId: UUID().uuidString,
            contextId: UUID().uuidString,
            artifact: artifact,
            append: false,
            lastChunk: true
        )
        let mockClient = MockA2AStreamClientForOrchestrator(agentCard: card, events: [wrapMessageResult(.taskArtifactUpdate(event))])
        
        let a2aManager = A2AManager(logger: Logger(label: "TestA2A"))
        try await a2aManager.initialize(clients: [mockClient])
        
        let toolCall = ToolCall(
            name: agentName,
            arguments: .object(["instructions": .string("Image only")]),
            id: "call-1"
        )
        let capture = SendCapture()
        let capturingLLM = CapturingMockLLM(logger: Logger(label: "Capture"), toolCallsToReturn: [toolCall], capture: capture)
        let config = OrchestratorConfig(streamingEnabled: false, mcpEnabled: false, a2aEnabled: true)
        let orchestrator = SwiftAgentKitOrchestrator(llm: capturingLLM, config: config, a2aManager: a2aManager)
        
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "Send image only")],
                availableTools: []
            )
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        let invocations = await capture.getInvocations()
        let invocationWithTool = invocations.first { $0.contains { $0.role == .tool } }
        #expect(invocationWithTool != nil)
        let toolMessage = invocationWithTool!.first { $0.role == .tool }
        #expect(toolMessage != nil)
        #expect(toolMessage!.images.count == 1)
        #expect(toolMessage!.content.isEmpty || toolMessage!.content.contains("Attachments:") == true)
    }
    
    // MARK: - ToolManager Tests
    
    @Test("SwiftAgentKitOrchestrator can be initialized with ToolManager")
    func testOrchestratorWithToolManager() async throws {
        let mockLLM = MockLLM(model: "test-model", logger: Logger(label: "MockLLM"))
        let toolManager = ToolManager(providers: [MockFunctionToolProvider()])
        let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM, toolManager: toolManager)
        
        #expect(await orchestrator.llm is MockLLM)
        #expect(await orchestrator.toolManager != nil)
    }
    
    @Test("availableTools includes ToolManager tools when configured")
    func testAvailableToolsIncludesToolManagerTools() async throws {
        let mockLLM = MockLLM(model: "test-model", logger: Logger(label: "MockLLM"))
        let toolName = "get_current_time"
        let toolManager = ToolManager(providers: [MockFunctionToolProvider(toolName: toolName)])
        let config = OrchestratorConfig(mcpEnabled: false, a2aEnabled: false)
        let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM, config: config, toolManager: toolManager)
        
        let tools = await orchestrator.allAvailableTools
        #expect(!tools.isEmpty)
        #expect(tools.contains { $0.name == toolName })
        #expect(tools.first { $0.name == toolName }?.type == .function)
    }

    @Test("allRegisteredTools exposes canonical descriptors")
    func testAllRegisteredToolsExposesCanonicalDescriptors() async throws {
        let llm = MockLLM(model: "registered", logger: Logger(label: "registered-llm"))
        let def = ToolDefinition(
            name: "canonical_tool",
            description: "Canonical",
            parameters: [.init(name: "q", description: "query", type: "string", required: true)],
            type: .function
        )
        let toolManager = ToolManager()
            .registerReadOnlyTool(
                definition: def,
                source: .local,
                parallelHint: .parallelizable,
                policyTags: [.sensitive]
            )
        let orchestrator = SwiftAgentKitOrchestrator(llm: llm, toolManager: toolManager)
        let descriptors = await orchestrator.allRegisteredTools
        let descriptor = descriptors.first { $0.definition.name == "canonical_tool" }
        #expect(descriptor != nil)
        #expect(descriptor?.source == .local)
        #expect(descriptor?.effectClass == .readOnly)
        #expect(descriptor?.parallelHint == .parallelizable)
        #expect(descriptor?.policyTags.contains(.sensitive) == true)
        #expect(descriptor?.normalizedSchemaFingerprint.isEmpty == false)
    }
    
    @Test("ToolManager executes function tool calls and result is sent to LLM")
    func testToolManagerExecutesFunctionToolCalls() async throws {
        let toolCallId = "call-func-1"
        let expectedContent = "2025-02-14T15:30:00Z"
        let toolCall = ToolCall(
            name: "get_current_time",
            arguments: .object([:]),
            id: toolCallId
        )
        
        let capture = SendCapture()
        let mockLLM = CapturingMockLLM(
            logger: Logger(label: "Capture"),
            toolCallsToReturn: [toolCall],
            capture: capture
        )
        let toolManager = ToolManager(providers: [
            MockFunctionToolProvider(toolName: "get_current_time", resultContent: expectedContent, resultSuccess: true)
        ])
        let config = OrchestratorConfig(streamingEnabled: false, mcpEnabled: false, a2aEnabled: false)
        let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM, config: config, toolManager: toolManager)
        
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "What time is it?")],
                availableTools: []
            )
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        let invocations = await capture.getInvocations()
        #expect(invocations.count >= 2)
        let invocationWithTool = invocations.first { $0.contains { $0.role == .tool } }
        #expect(invocationWithTool != nil)
        let toolMessage = invocationWithTool!.first { $0.role == .tool }
        #expect(toolMessage != nil)
        #expect(toolMessage!.content == expectedContent)
        #expect(toolMessage!.toolCallId == toolCallId)
    }

    @Test("updateConversation publishes agentic loop states through ToolManager tool iteration")
    func testAgenticLoopUpdatesThroughToolManager() async throws {
        let toolCallId = "call-agentic-1"
        let toolCall = ToolCall(
            name: "get_current_time",
            arguments: .object([:]),
            id: toolCallId
        )

        let capture = SendCapture()
        let mockLLM = CapturingMockLLM(
            logger: Logger(label: "Capture"),
            toolCallsToReturn: [toolCall],
            capture: capture
        )
        let toolManager = ToolManager(providers: [
            MockFunctionToolProvider(toolName: "get_current_time", resultContent: "2025-02-14T15:30:00Z", resultSuccess: true)
        ])
        let config = OrchestratorConfig(streamingEnabled: false, mcpEnabled: false, a2aEnabled: false)
        let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM, config: config, toolManager: toolManager)

        let messageStream = await orchestrator.messageStream

        let agenticStream = await orchestrator.agenticLoopUpdates
        let agenticStateCollector = AgenticLoopStateCollector()
        let collectTask = Task {
            for await (_, state) in agenticStream {
                await agenticStateCollector.append(state)
            }
        }
        defer { collectTask.cancel() }

        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "What time is it?")],
                availableTools: []
            )
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        let agenticStates = await agenticStateCollector.snapshot()
        #expect(agenticStates.contains(.started))
        #expect(agenticStates.contains(.llmCall(iteration: 1)))
        #expect(agenticStates.contains(.waitingForToolExecution))
        #expect(agenticStates.contains(.executingTools))
        #expect(agenticStates.contains(.betweenIterations))
        #expect(agenticStates.contains(.llmCall(iteration: 2)))
        #expect(agenticStates.contains(.completed))
    }
    
    @Test("ToolManager passes error to LLM when tool is not found in any provider")
    func testToolManagerPassesErrorWhenToolNotFound() async throws {
        // ToolManager returns success: false when no provider handles the tool.
        // Use a provider that doesn't know the requested tool - ToolManager falls through
        // to "not found" and the error is sent to the LLM.
        let toolCallId = "call-fail-1"
        let toolCall = ToolCall(
            name: "unknown_tool",  // No provider implements this
            arguments: .object([:]),
            id: toolCallId
        )
        
        let capture = SendCapture()
        let mockLLM = CapturingMockLLM(
            logger: Logger(label: "Capture"),
            toolCallsToReturn: [toolCall],
            capture: capture
        )
        let toolManager = ToolManager(providers: [
            MockFunctionToolProvider(toolName: "get_current_time")  // Only knows get_current_time
        ])
        let config = OrchestratorConfig(streamingEnabled: false, mcpEnabled: false, a2aEnabled: false)
        let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM, config: config, toolManager: toolManager)
        
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "Use unknown_tool")],
                availableTools: []
            )
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        let invocations = await capture.getInvocations()
        let invocationWithTool = invocations.first { $0.contains { $0.role == .tool } }
        #expect(invocationWithTool != nil)
        let toolMessage = invocationWithTool!.first { $0.role == .tool }
        #expect(toolMessage != nil)
        #expect(toolMessage!.content.contains("not found") || toolMessage!.content.contains("unknown_tool"))
        #expect(toolMessage!.toolCallId == toolCallId)
    }
    
    @Test("ToolManager is used when MCP and A2A do not handle the tool")
    func testToolManagerUsedWhenMCPAndA2ADoNotHandleTool() async throws {
        // MCP and A2A managers with no clients - they won't handle any tool
        let mcpManager = MCPManager(connectionTimeout: 5.0, logger: Logger(label: "TestMCP"))
        let a2aManager = A2AManager(logger: Logger(label: "TestA2A"))
        
        let toolCall = ToolCall(
            name: "get_current_time",
            arguments: .object([:]),
            id: "call-fallback-1"
        )
        let capture = SendCapture()
        let mockLLM = CapturingMockLLM(
            logger: Logger(label: "Capture"),
            toolCallsToReturn: [toolCall],
            capture: capture
        )
        let toolManager = ToolManager(providers: [
            MockFunctionToolProvider(toolName: "get_current_time", resultContent: "fallback-success")
        ])
        let config = OrchestratorConfig(streamingEnabled: false, mcpEnabled: true, a2aEnabled: true)
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: mockLLM,
            config: config,
            mcpManager: mcpManager,
            a2aManager: a2aManager,
            toolManager: toolManager
        )
        
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "What time is it?")],
                availableTools: []
            )
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        // ToolManager should have handled it since MCP/A2A have no clients
        let invocations = await capture.getInvocations()
        let invocationWithTool = invocations.first { $0.contains { $0.role == .tool } }
        #expect(invocationWithTool != nil)
        let toolMessage = invocationWithTool!.first { $0.role == .tool }
        #expect(toolMessage != nil)
        #expect(toolMessage!.content == "fallback-success")
    }
    
    @Test("ToolManager with multiple providers aggregates tools")
    func testToolManagerMultipleProvidersAggregatesTools() async throws {
        let mockLLM = MockLLM(model: "test-model", logger: Logger(label: "MockLLM"))
        let toolManager = ToolManager(providers: [
            MockFunctionToolProvider(toolName: "get_current_time"),
            MockFunctionToolProvider(toolName: "get_weather")
        ])
        let config = OrchestratorConfig(mcpEnabled: false, a2aEnabled: false)
        let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM, config: config, toolManager: toolManager)
        
        let tools = await orchestrator.allAvailableTools
        #expect(tools.count == 2)
        #expect(tools.contains { $0.name == "get_current_time" })
        #expect(tools.contains { $0.name == "get_weather" })
    }

    @Test("OrchestratorInvocationOptions merges parameters for each LLM request")
    func testInvocationOptionsMergeParameters() async throws {
        let configCapture = ConfigCapture()
        let base = OrchestratorConfig(
            streamingEnabled: false,
            additionalParameters: .object(["fromConfig": .string("cfg")])
        )
        let capturing = CapturingMockLLM(
            logger: Logger(label: "merge"),
            toolCallsToReturn: [],
            configCapture: configCapture
        )
        let orchestrator = SwiftAgentKitOrchestrator(llm: capturing, config: base)
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "Hi")],
                availableTools: [],
                options: OrchestratorInvocationOptions(
                    additionalParameters: .object(["fromOptions": .string("opt")]),
                    systemPromptMetadata: ["plan": "step1"]
                )
            )
        }
        let configs = await configCapture.getConfigs()
        #expect(configs.count >= 1)
        guard case .object(let dict) = configs[0].additionalParameters else {
            Issue.record("Expected merged JSON object")
            return
        }
        guard case .string(let a) = dict["fromConfig"], a == "cfg" else {
            Issue.record("fromConfig")
            return
        }
        guard case .string(let b) = dict["fromOptions"], b == "opt" else {
            Issue.record("fromOptions")
            return
        }
        guard case .string(let p) = dict["plan"], p == "step1" else {
            Issue.record("plan")
            return
        }
    }

    @Test("updateConversation passes toolInvocationPolicy to LLMRequestConfig")
    func testToolInvocationPolicyForwarded() async throws {
        let configCapture = ConfigCapture()
        let capturing = CapturingMockLLM(
            logger: Logger(label: "policy"),
            toolCallsToReturn: [],
            configCapture: configCapture
        )
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: capturing,
            config: OrchestratorConfig(streamingEnabled: false, toolInvocationPolicy: .required)
        )
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "Hi")],
                availableTools: []
            )
        }
        let configs = await configCapture.getConfigs()
        #expect(configs.first?.toolInvocationPolicy == .required)
    }

    @Test("maxAgenticStepsPerUpdate stops runaway tool loops")
    func testMaxAgenticStepsPerUpdate() async throws {
        let toolCall = ToolCall(
            name: "get_current_time",
            arguments: .object([:]),
            id: "loop"
        )
        let mock = InfiniteToolMockLLM(toolCall: toolCall)
        let toolManager = ToolManager(providers: [
            MockFunctionToolProvider(toolName: "get_current_time", resultContent: "t", resultSuccess: true)
        ])
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: mock,
            config: OrchestratorConfig(
                streamingEnabled: false,
                mcpEnabled: false,
                a2aEnabled: false,
                maxAgenticStepsPerUpdate: 2
            ),
            toolManager: toolManager
        )
        let messageStream = await orchestrator.messageStream
        await #expect(throws: OrchestratorError.self) {
            try await drainPublishedMessagesWhileRunning(messageStream) {
                try await orchestrator.updateConversation(
                    [Message(id: UUID(), role: .user, content: "x")],
                    availableTools: [ToolDefinition(
                        name: "get_current_time",
                        description: "t",
                        parameters: [],
                        type: .function
                    )]
                )
            }
        }
    }

    @Test("llmGenerationCompleted is published with metadata")
    func testLlmGenerationCompletedEvent() async throws {
        let mock = MockLLM(model: "m", logger: Logger(label: "m"))
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: mock,
            config: OrchestratorConfig(streamingEnabled: false)
        )
        let agenticStream = await orchestrator.agenticLoopUpdates
        let collector = AgenticLoopStateCollector()
        let collectTask = Task {
            for await (_, state) in agenticStream {
                await collector.append(state)
            }
        }
        defer { collectTask.cancel() }
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "Hi")],
                availableTools: []
            )
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        let states = await collector.snapshot()
        let completed = states.compactMap { state -> LLMGenerationSummary? in
            if case .llmGenerationCompleted(let s) = state { return s }
            return nil
        }
        #expect(completed.count >= 1)
        #expect(completed[0].innerStepIndex == 1)
        #expect(completed[0].hadToolCalls == false)
    }

    @Test("reject prose retries then accepts tool call")
    func testAssistantTurnCorrectionRetry() async throws {
        let toolCall = ToolCall(
            name: "get_current_time",
            arguments: .object([:]),
            id: "c1"
        )
        let correctionMock = AssistantCorrectionMockLLM(toolCall: toolCall)
        let toolManager = ToolManager(providers: [
            MockFunctionToolProvider(toolName: "get_current_time", resultContent: "ok", resultSuccess: true)
        ])
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: correctionMock,
            config: OrchestratorConfig(
                streamingEnabled: false,
                rejectAssistantTurnWithNoToolCallsWhenToolsAvailable: true,
                maxCorrectionRetries: 2,
                correctionMessage: "Use a tool."
            ),
            toolManager: toolManager
        )
        let def = ToolDefinition(
            name: "get_current_time",
            description: "time",
            parameters: [],
            type: .function
        )
        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "Hey")],
                availableTools: [def]
            )
        }
        #expect(correctionMock.sendInvocationCount >= 2)
    }

    @Test("Tool dispatch policy defaults to serial when metadata missing")
    func testToolDispatchPolicyDefaultsToSerialWhenMetadataMissing() async throws {
        let call1 = ToolCall(name: "t1", arguments: .object([:]), id: "c1")
        let call2 = ToolCall(name: "t2", arguments: .object([:]), id: "c2")
        let llm = CapturingMockLLM(
            logger: Logger(label: "policy-serial"),
            toolCallsToReturn: [call1, call2]
        )
        let recorder = ToolExecutionOrderRecorder()
        let provider = RecordingPolicyToolProvider(toolNames: ["t1", "t2"], recorder: recorder, safety: .unknown)
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: llm,
            config: OrchestratorConfig(streamingEnabled: false, parallelToolDispatchEnabled: true),
            toolManager: ToolManager(providers: [provider])
        )

        let lifecycleStream = await orchestrator.toolLifecycleEvents
        actor LifecycleCollector {
            var events: [ToolLifecycleEvent] = []
            func append(_ event: ToolLifecycleEvent) { events.append(event) }
            func snapshot() -> [ToolLifecycleEvent] { events }
        }
        let collector = LifecycleCollector()
        let collectTask = Task {
            for await event in lifecycleStream {
                await collector.append(event)
            }
        }
        defer { collectTask.cancel() }

        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "run tools")],
                availableTools: []
            )
        }
        try? await Task.sleep(nanoseconds: 30_000_000)

        let started = await collector.snapshot().filter { $0.state == .started }
        #expect(started.count == 2)
        #expect(started.allSatisfy { $0.dispatchMode == .serial })
        let order = await recorder.startedToolNames
        #expect(order == ["t1", "t2"])
    }

    @Test("Tool dispatch policy runs parallel when all calls are parallel-safe")
    func testToolDispatchPolicyParallelWhenAllSafe() async throws {
        let call1 = ToolCall(name: "p1", arguments: .object([:]), id: "pc1")
        let call2 = ToolCall(name: "p2", arguments: .object([:]), id: "pc2")
        let llm = CapturingMockLLM(
            logger: Logger(label: "policy-parallel"),
            toolCallsToReturn: [call1, call2]
        )
        let provider = RecordingPolicyToolProvider(toolNames: ["p1", "p2"], recorder: ToolExecutionOrderRecorder(), safety: .parallelSafe)
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: llm,
            config: OrchestratorConfig(streamingEnabled: false, parallelToolDispatchEnabled: true),
            toolManager: ToolManager(providers: [provider])
        )

        let lifecycleStream = await orchestrator.toolLifecycleEvents
        actor LifecycleCollector {
            var events: [ToolLifecycleEvent] = []
            func append(_ event: ToolLifecycleEvent) { events.append(event) }
            func snapshot() -> [ToolLifecycleEvent] { events }
        }
        let collector = LifecycleCollector()
        let collectTask = Task {
            for await event in lifecycleStream {
                await collector.append(event)
            }
        }
        defer { collectTask.cancel() }

        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "run parallel tools")],
                availableTools: [],
                options: OrchestratorInvocationOptions(
                    toolParallelSafetyMetadata: [
                        "pc1": .parallelSafe,
                        "pc2": .parallelSafe
                    ]
                )
            )
        }
        try? await Task.sleep(nanoseconds: 30_000_000)

        let started = await collector.snapshot().filter { $0.state == .started }
        #expect(started.count == 2)
        #expect(started.allSatisfy { $0.dispatchMode == .parallel })
    }

    @Test("Pending completion stream is idempotent for duplicate submissions")
    func testPendingCompletionIdempotent() async throws {
        let toolCall = ToolCall(name: "pending_tool", arguments: .object([:]), id: "pending_call_1")
        let llm = CapturingMockLLM(
            logger: Logger(label: "pending-llm"),
            toolCallsToReturn: [toolCall]
        )
        let provider = PendingMockToolProvider(toolName: "pending_tool")
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: llm,
            config: OrchestratorConfig(streamingEnabled: false),
            toolManager: ToolManager(providers: [provider])
        )

        let pendingStream = await orchestrator.pendingToolCompletions
        actor PendingCollector {
            var completions: [PendingToolCompletion] = []
            func append(_ completion: PendingToolCompletion) { completions.append(completion) }
            func snapshot() -> [PendingToolCompletion] { completions }
        }
        let collector = PendingCollector()
        let collectTask = Task {
            for await completion in pendingStream {
                await collector.append(completion)
            }
        }
        defer { collectTask.cancel() }

        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "start pending tool")],
                availableTools: []
            )
        }

        let completion = PendingToolCompletion(
            handleID: "handle-pending_call_1",
            toolCallID: "pending_call_1",
            result: ToolResult(success: true, content: "done", toolCallId: "pending_call_1")
        )
        await orchestrator.submitPendingCompletion(completion)
        await orchestrator.submitPendingCompletion(completion)
        try? await Task.sleep(nanoseconds: 30_000_000)

        let completions = await collector.snapshot()
        #expect(completions.count == 1)
        #expect(completions[0].toolCallID == "pending_call_1")
    }

    @Test("Tool dispatch policy uses serial when any call is mutating")
    func testToolDispatchPolicyMutatingForcesSerial() async throws {
        let call1 = ToolCall(name: "m1", arguments: .object([:]), id: "mc1")
        let call2 = ToolCall(name: "m2", arguments: .object([:]), id: "mc2")
        let llm = CapturingMockLLM(
            logger: Logger(label: "policy-mutating"),
            toolCallsToReturn: [call1, call2]
        )
        let provider = RecordingPolicyToolProvider(toolNames: ["m1", "m2"], recorder: ToolExecutionOrderRecorder(), safety: .parallelSafe)
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: llm,
            config: OrchestratorConfig(streamingEnabled: false, parallelToolDispatchEnabled: true),
            toolManager: ToolManager(providers: [provider])
        )

        let lifecycleStream = await orchestrator.toolLifecycleEvents
        let collector = ToolLifecycleCollector()
        let collectTask = Task {
            for await event in lifecycleStream {
                await collector.append(event)
            }
        }
        defer { collectTask.cancel() }

        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "run mutating tools")],
                availableTools: [],
                options: OrchestratorInvocationOptions(
                    toolParallelSafetyMetadata: [
                        "mc1": .parallelSafe,
                        "mc2": .mutating
                    ]
                )
            )
        }
        try? await Task.sleep(nanoseconds: 30_000_000)

        let started = await collector.snapshot().filter { $0.state == .started }
        #expect(started.count == 2)
        #expect(started.allSatisfy { $0.dispatchMode == .serial })
    }

    @Test("Tool dispatch policy remains serial when parallel mode disabled")
    func testToolDispatchPolicyParallelSafeButParallelDisabled() async throws {
        let call1 = ToolCall(name: "d1", arguments: .object([:]), id: "dc1")
        let call2 = ToolCall(name: "d2", arguments: .object([:]), id: "dc2")
        let llm = CapturingMockLLM(
            logger: Logger(label: "policy-disabled"),
            toolCallsToReturn: [call1, call2]
        )
        let provider = RecordingPolicyToolProvider(toolNames: ["d1", "d2"], recorder: ToolExecutionOrderRecorder(), safety: .parallelSafe)
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: llm,
            config: OrchestratorConfig(streamingEnabled: false, parallelToolDispatchEnabled: false),
            toolManager: ToolManager(providers: [provider])
        )

        let lifecycleStream = await orchestrator.toolLifecycleEvents
        let collector = ToolLifecycleCollector()
        let collectTask = Task {
            for await event in lifecycleStream {
                await collector.append(event)
            }
        }
        defer { collectTask.cancel() }

        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "run tools with parallel disabled")],
                availableTools: [],
                options: OrchestratorInvocationOptions(
                    toolParallelSafetyMetadata: [
                        "dc1": .parallelSafe,
                        "dc2": .parallelSafe
                    ]
                )
            )
        }
        try? await Task.sleep(nanoseconds: 30_000_000)

        let started = await collector.snapshot().filter { $0.state == .started }
        #expect(started.count == 2)
        #expect(started.allSatisfy { $0.dispatchMode == .serial })
    }

    @Test("Pending completion publishes lifecycle completion for same toolCallID")
    func testPendingCompletionPublishesLifecycleCompletion() async throws {
        let toolCall = ToolCall(name: "pending_lifecycle_tool", arguments: .object([:]), id: "pending_lifecycle_call")
        let llm = CapturingMockLLM(
            logger: Logger(label: "pending-lifecycle"),
            toolCallsToReturn: [toolCall]
        )
        let provider = PendingMockToolProvider(toolName: "pending_lifecycle_tool")
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: llm,
            config: OrchestratorConfig(streamingEnabled: false),
            toolManager: ToolManager(providers: [provider])
        )

        let lifecycleStream = await orchestrator.toolLifecycleEvents
        let collector = ToolLifecycleCollector()
        let collectTask = Task {
            for await event in lifecycleStream {
                await collector.append(event)
            }
        }
        defer { collectTask.cancel() }

        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "start pending lifecycle tool")],
                availableTools: []
            )
        }

        let completion = PendingToolCompletion(
            handleID: "handle-pending_lifecycle_call",
            toolCallID: "pending_lifecycle_call",
            result: ToolResult(success: true, content: "done", toolCallId: "pending_lifecycle_call")
        )
        await orchestrator.submitPendingCompletion(completion)
        try? await Task.sleep(nanoseconds: 30_000_000)

        let events = await collector.snapshot().filter { $0.toolCallID == "pending_lifecycle_call" }
        #expect(events.contains(where: { $0.state == .started }))
        #expect(events.contains(where: { $0.state == .pending }))
        #expect(events.contains(where: { $0.state == .completed }))
    }

    @Test("Pending handle timeout cancels and emits terminal cancelled lifecycle state")
    func testPendingHandleTimeoutCancelsAndPublishesCancelled() async throws {
        let toolCall = ToolCall(name: "pending_timeout_tool", arguments: .object([:]), id: "pending_timeout_call")
        let llm = CapturingMockLLM(
            logger: Logger(label: "pending-timeout"),
            toolCallsToReturn: [toolCall]
        )
        let provider = PendingMockToolProvider(toolName: "pending_timeout_tool")
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: llm,
            config: OrchestratorConfig(streamingEnabled: false, pendingToolTimeout: 0.02),
            toolManager: ToolManager(providers: [provider])
        )

        let lifecycleStream = await orchestrator.toolLifecycleEvents
        let collector = ToolLifecycleCollector()
        let collectTask = Task {
            for await event in lifecycleStream {
                await collector.append(event)
            }
        }
        defer { collectTask.cancel() }

        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "start pending timeout tool")],
                availableTools: []
            )
        }
        try? await Task.sleep(nanoseconds: 80_000_000)

        let events = await collector.snapshot().filter { $0.toolCallID == "pending_timeout_call" }
        #expect(events.contains(where: { $0.state == .pending }))
        #expect(events.contains(where: { $0.state == .cancelled }))
    }

    @Test("cancelPendingTool cancels in-flight A2A stream when handleID matches toolCallID")
    func testCancelPendingToolCancelsInFlightA2AStream() async throws {
        let toolCallID = "pending_a2a_call"
        let taskID = "a2a-task-for-cancel"
        let agentName = "PendingCancelAgent"
        let pendingToolName = "pending_cancel_tool"

        let card = makeAgentCard(name: agentName)
        let mockClient = MockCancellableA2AStreamClientForOrchestrator(
            agentCard: card,
            initialEvents: [
                wrapMessageResult(.task(A2ATask(
                    id: taskID,
                    contextId: UUID().uuidString,
                    status: TaskStatus(
                        state: .working,
                        timestamp: ISO8601DateFormatter().string(from: Date())
                    )
                )))
            ]
        )
        let a2aManager = A2AManager()
        try await a2aManager.initialize(clients: [mockClient])

        let a2aToolCall = ToolCall(
            name: agentName,
            arguments: .object(["instructions": .string("Long running")]),
            id: toolCallID
        )

        let (_, events) = try await a2aManager.streamAgentCall(a2aToolCall, invocationID: "bg-invocation")
        let collectTask = Task { for await _ in events { } }

        try await Task.sleep(nanoseconds: 100_000_000)

        let pendingToolCall = ToolCall(name: pendingToolName, arguments: .object([:]), id: toolCallID)
        let llm = CapturingMockLLM(
            logger: Logger(label: "pending-a2a-cancel"),
            toolCallsToReturn: [pendingToolCall]
        )
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: llm,
            config: OrchestratorConfig(streamingEnabled: false, pendingToolTimeout: nil),
            a2aManager: a2aManager,
            toolManager: ToolManager(providers: [PendingToolProviderMatchingHandleID(toolName: pendingToolName)])
        )

        let messageStream = await orchestrator.messageStream
        try await drainPublishedMessagesWhileRunning(messageStream) {
            try await orchestrator.updateConversation(
                [Message(id: UUID(), role: .user, content: "start pending cancel tool")],
                availableTools: []
            )
        }

        await orchestrator.cancelPendingTool(handleID: toolCallID)

        await collectTask.value
        #expect(await mockClient.cancelTaskCallCount == 1)
        #expect(await mockClient.lastCancelledTaskID == taskID)
        #expect(await mockClient.cancelTaskCallCount == 1)
        #expect(await mockClient.lastCancelledTaskID == taskID)
    }

    @Test("staged assistant persistence commits exactly once on natural completion")
    func testStagedAssistantCommitOnNaturalCompletion() async throws {
        let llm = MockLLM(model: "staged-complete", logger: Logger(label: "staged-complete"))
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: llm,
            config: OrchestratorConfig(streamingEnabled: false, assistantPersistenceMode: .stagedCommit)
        )

        actor MessageCollector {
            var assistantMessages: [Message] = []
            func append(_ message: Message) {
                if message.role == .assistant { assistantMessages.append(message) }
            }
        }
        let collector = MessageCollector()
        let messageStream = await orchestrator.messageStream
        let collectTask = Task {
            for await message in messageStream {
                await collector.append(message)
            }
        }
        defer { collectTask.cancel() }

        let outcome = await orchestrator.updateConversationWithOutcome(
            [Message(id: UUID(), role: .user, content: "hello")],
            availableTools: []
        )
        try? await Task.sleep(nanoseconds: 20_000_000)
        let assistantMessages = await collector.assistantMessages

        #expect(outcome.terminalState == .completed)
        #expect(outcome.terminalReason == .naturalStop)
        #expect(outcome.assistantCommitted == true)
        #expect(assistantMessages.count == 1)
    }

    @Test("staged assistant persistence rolls back on cancellation")
    func testStagedAssistantRollbackOnCancellation() async throws {
        let llm = SlowStreamingCancelMockLLM(logger: Logger(label: "staged-cancel"))
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: llm,
            config: OrchestratorConfig(streamingEnabled: true, assistantPersistenceMode: .stagedCommit)
        )

        actor MessageCollector {
            var assistantMessages: [Message] = []
            func append(_ message: Message) {
                if message.role == .assistant { assistantMessages.append(message) }
            }
        }
        let collector = MessageCollector()
        let messageStream = await orchestrator.messageStream
        let collectTask = Task {
            for await message in messageStream {
                await collector.append(message)
            }
        }
        defer { collectTask.cancel() }

        let updateTask = Task { () -> UpdateConversationOutcome in
            await orchestrator.updateConversationWithOutcome(
                [Message(id: UUID(), role: .user, content: "stream and cancel")],
                availableTools: []
            )
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        updateTask.cancel()
        let outcome = await updateTask.value
        try? await Task.sleep(nanoseconds: 20_000_000)
        let assistantMessages = await collector.assistantMessages

        #expect(outcome.terminalState == .cancelled)
        #expect(outcome.terminalReason == .externalCancellation)
        #expect(outcome.assistantCommitted == false)
        #expect(assistantMessages.isEmpty)
    }

    @Test("cancelRun cancels pending handles and late completion is ignored")
    func testCancelRunCancelsPendingAndIgnoresLateCompletion() async throws {
        let toolCall = ToolCall(name: "pending_cancel_tool", arguments: .object([:]), id: "pending_cancel_call")
        let llm = CapturingMockLLM(
            logger: Logger(label: "pending-cancel"),
            toolCallsToReturn: [toolCall]
        )
        let provider = PendingMockToolProvider(toolName: "pending_cancel_tool")
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: llm,
            config: OrchestratorConfig(streamingEnabled: false),
            toolManager: ToolManager(providers: [provider])
        )

        let outcome = await orchestrator.updateConversationWithOutcome(
            [Message(id: UUID(), role: .user, content: "start pending and cancel run")],
            availableTools: []
        )
        let runID = outcome.runID
        let snapshot = await orchestrator.recoverableActiveRunsSnapshot()
        #expect(snapshot.contains(where: { $0.runID == runID }))

        let cancelOutcome = await orchestrator.cancelRun(runID: runID, conversationID: nil)
        #expect(cancelOutcome.terminalState == .cancelled)
        #expect(cancelOutcome.cancelledToolHandles.count == 1)

        actor PendingCollector {
            var completions: [PendingToolCompletion] = []
            func append(_ completion: PendingToolCompletion) { completions.append(completion) }
            func snapshot() -> [PendingToolCompletion] { completions }
        }
        let pendingCollector = PendingCollector()
        let pendingStream = await orchestrator.pendingToolCompletions
        let collectTask = Task {
            for await completion in pendingStream {
                await pendingCollector.append(completion)
            }
        }
        defer { collectTask.cancel() }

        await orchestrator.submitPendingCompletion(
            PendingToolCompletion(
                handleID: "handle-pending_cancel_call",
                toolCallID: "pending_cancel_call",
                result: ToolResult(success: true, content: "late", toolCallId: "pending_cancel_call")
            )
        )
        try? await Task.sleep(nanoseconds: 20_000_000)
        let completions = await pendingCollector.snapshot()
        #expect(completions.isEmpty)
    }

    @Test("invokeTool executes tool directly and returns completed outcome")
    func testInvokeToolDirectCompletedOutcome() async throws {
        let llm = MockLLM(model: "direct", logger: Logger(label: "direct"))
        let provider = MockFunctionToolProvider(toolName: "get_now", resultContent: "2026-05-16T00:00:00Z")
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: llm,
            config: OrchestratorConfig(streamingEnabled: false, mcpEnabled: false, a2aEnabled: false),
            toolManager: ToolManager(providers: [provider])
        )
        let outcome = await orchestrator.invokeTool(
            ToolInvocationRequest(
                toolName: "get_now",
                argumentsPayload: .object([:]),
                source: .command,
                callerProvenance: "unit-test"
            )
        )
        switch outcome {
        case .completed(let result, let metadata):
            #expect(result.success == true)
            #expect(result.content == "2026-05-16T00:00:00Z")
            #expect(metadata.source == .command)
            #expect(metadata.callerProvenance == "unit-test")
        default:
            Issue.record("Expected completed outcome")
        }
    }

    @Test("invokeTool returns denied outcome when pre-dispatch policy denies")
    func testInvokeToolPolicyDeny() async throws {
        let llm = MockLLM(model: "deny", logger: Logger(label: "deny"))
        let provider = MockFunctionToolProvider(toolName: "dangerous_tool", resultContent: "should-not-run")
        let policy = StaticPreDispatchPolicyEvaluator(
            decisionByToolName: [
                "dangerous_tool": ToolPreDispatchPolicyDecision(
                    decision: .deny,
                    reasonCode: "POLICY_DENY",
                    reasonText: "blocked by policy"
                )
            ]
        )
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: llm,
            config: OrchestratorConfig(
                streamingEnabled: false,
                mcpEnabled: false,
                a2aEnabled: false,
                preDispatchPolicyEvaluator: policy
            ),
            toolManager: ToolManager(providers: [provider])
        )
        let outcome = await orchestrator.invokeTool(
            ToolInvocationRequest(
                toolName: "dangerous_tool",
                source: .direct,
                callerProvenance: "policy-test"
            )
        )
        switch outcome {
        case .denied(let metadata):
            #expect(metadata.policyDecision?.decision == .deny)
            #expect(metadata.policyDecision?.reasonCode == "POLICY_DENY")
        default:
            Issue.record("Expected denied outcome")
        }
    }

    @Test("invokeTools mixedDeterministic planner returns staged diagnostics")
    func testInvokeToolsMixedDeterministicPlannerDiagnostics() async throws {
        let llm = MockLLM(model: "planner", logger: Logger(label: "planner"))
        let provider = RoutingSafetyToolProvider(
            safetiesByToolName: [
                "read_a": .parallelSafe,
                "mutate_b": .mutating,
                "read_c": .parallelSafe
            ]
        )
        let orchestrator = SwiftAgentKitOrchestrator(
            llm: llm,
            config: OrchestratorConfig(
                streamingEnabled: false,
                mcpEnabled: false,
                a2aEnabled: false,
                parallelToolDispatchEnabled: true,
                dispatchPlannerMode: .mixedDeterministic
            ),
            toolManager: ToolManager(providers: [provider])
        )
        let outcome = await orchestrator.invokeTools(
            ToolBatchInvocationRequest(
                requests: [
                    ToolInvocationRequest(toolName: "read_a"),
                    ToolInvocationRequest(toolName: "mutate_b"),
                    ToolInvocationRequest(toolName: "read_c")
                ],
                plannerMode: .mixedDeterministic
            )
        )
        #expect(outcome.outcomes.count == 3)
        #expect(outcome.diagnostics.plannerMode == ToolDispatchPlannerMode.mixedDeterministic)
        #expect(outcome.diagnostics.stages.count == 3)
        #expect(outcome.diagnostics.stages[0].mode == ToolDispatchMode.parallel)
        #expect(outcome.diagnostics.stages[1].mode == ToolDispatchMode.serial)
        #expect(outcome.diagnostics.stages[2].mode == ToolDispatchMode.parallel)
    }
}

// MARK: - Harness test doubles

/// Always requests the same tool so the agentic loop continues until ``OrchestratorConfig/maxAgenticStepsPerUpdate``.
private struct InfiniteToolMockLLM: LLMProtocol {
    let toolCall: ToolCall
    init(toolCall: ToolCall) {
        self.toolCall = toolCall
    }
    func getModelName() -> String { "infinite-tools" }
    func getCapabilities() -> [LLMCapability] { [.tools] }
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        LLMResponse.withToolCalls(content: "", toolCalls: [toolCall])
    }
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.complete(LLMResponse.withToolCalls(content: "", toolCalls: [toolCall])))
            continuation.finish()
        }
    }
    func generateImage(_ config: ImageGenerationRequestConfig) async throws -> ImageGenerationResponse {
        throw LLMError.unsupportedCapability(.imageGeneration)
    }
}

/// Returns prose until the correction message appears in the transcript, then tool calls.
private final class AssistantCorrectionMockLLM: LLMProtocol, @unchecked Sendable {
    private let toolCall: ToolCall
    private let correctionSnippet: String
    private(set) var sendInvocationCount = 0
    init(toolCall: ToolCall, correctionSnippet: String = "Use a tool.") {
        self.toolCall = toolCall
        self.correctionSnippet = correctionSnippet
    }
    func getModelName() -> String { "correction-mock" }
    func getCapabilities() -> [LLMCapability] { [.tools] }
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        sendInvocationCount += 1
        let hasToolTurn = messages.contains { $0.role == .tool }
        if hasToolTurn {
            return LLMResponse.complete(content: "Done after tool.")
        }
        let sawCorrection = messages.contains { $0.content.contains(correctionSnippet) }
        if sawCorrection {
            return LLMResponse.withToolCalls(content: "", toolCalls: [toolCall])
        }
        return LLMResponse.complete(content: "I will just chat.")
    }
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func generateImage(_ config: ImageGenerationRequestConfig) async throws -> ImageGenerationResponse {
        throw LLMError.unsupportedCapability(.imageGeneration)
    }
} 