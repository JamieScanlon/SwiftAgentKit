import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitMCP
import SwiftAgentKitACP
import SwiftAgentKitAdapters
import EasyJSON

/// Controls how the orchestrator integrates A2A agents: catalog registration vs inline execution.
public enum A2AOrchestratorIntegration: Sendable, Equatable {
    /// A2A agents are not merged into the tool catalog and are not executed inline.
    case disabled
    /// A2A agents appear in the tool catalog; inline `agentCall` is not performed by the orchestrator.
    case registrationOnly
    /// A2A agents appear in the catalog and are executed inline via `A2AManager.agentCall` (legacy default when `a2aEnabled` was true).
    case inlineExecution
}

/// Controls how the orchestrator integrates ACP agents: catalog registration vs inline execution.
public enum ACPOrchestratorIntegration: Sendable, Equatable {
    /// ACP agents are not merged into the tool catalog and are not executed inline.
    case disabled
    /// ACP agents appear in the tool catalog; inline `agentCall` is not performed by the orchestrator.
    case registrationOnly
    /// ACP agents appear in the catalog and are executed inline via `ACPManager.agentCall` (legacy default when `acpEnabled` was true).
    case inlineExecution
}

/// Configuration for the SwiftAgentKitOrchestrator
public struct OrchestratorConfig: Sendable {
    /// Whether streaming responses are enabled
    public let streamingEnabled: Bool
    /// Whether MCP (Model Context Protocol) tool usage is enabled
    public let mcpEnabled: Bool
    /// How A2A agents are registered and executed by the orchestrator.
    public let a2aIntegration: A2AOrchestratorIntegration
    /// How ACP agents are registered and executed by the orchestrator.
    public let acpIntegration: ACPOrchestratorIntegration
    /// Connection timeout for MCP servers in seconds
    public let mcpConnectionTimeout: TimeInterval
    /// Maximum wall-clock time for a single tool call (MCP, A2A, or ToolManager dispatch) in seconds
    public let toolCallTimeout: TimeInterval
    /// Maximum number of tokens to generate (passed to LLM requests)
    public let maxTokens: Int?
    /// Temperature for response randomness, 0.0 to 2.0 (passed to LLM requests)
    public let temperature: Double?
    /// Top-p sampling parameter (passed to LLM requests)
    public let topP: Double?
    /// Additional model-specific parameters (passed to LLM requests)
    public let additionalParameters: JSON?
    /// Maximum LLM invocations (including tool follow-ups) for a single `updateConversation`; `nil` means unlimited.
    public let maxAgenticStepsPerUpdate: Int?
    /// Controls when assistant messages are published/committed.
    public let assistantPersistenceMode: AssistantPersistenceMode
    /// When true, tool batches classified as parallel-safe may run concurrently.
    public let parallelToolDispatchEnabled: Bool
    /// Optional custom policy evaluator for selecting serial vs parallel mode for each tool batch.
    public let toolDispatchPolicyEvaluator: (any ToolDispatchPolicyEvaluating)?
    /// Optional explicit planner mode for tool batches (`nil` keeps legacy evaluator behavior).
    public let dispatchPlannerMode: ToolDispatchPlannerMode?
    /// Optional structured pre-dispatch policy hook invoked before every tool execution.
    public let preDispatchPolicyEvaluator: (any ToolPreDispatchPolicyEvaluating)?
    /// Optional timeout for pending tool handles. `nil` disables automatic timeout cancellation.
    public let pendingToolTimeout: TimeInterval?
    /// How tool calls are chosen when tools are passed to the orchestrator (forwarded in ``LLMRequestConfig``).
    public let toolInvocationPolicy: ToolInvocationPolicy
    /// When true and tools are non-empty, reject assistant turns with no tool calls and retry with a correction message (see correction fields).
    public let rejectAssistantTurnWithNoToolCallsWhenToolsAvailable: Bool
    /// Maximum correction messages appended after a rejected prose turn; `0` disables retry (throws if rejected).
    public let maxCorrectionRetries: Int
    public let correctionMessage: String
    public let correctionRole: MessageRole

    /// Whether A2A tools are merged into the orchestrator catalog.
    var a2aCatalogEnabled: Bool { a2aIntegration != .disabled }

    /// Whether the orchestrator executes A2A tools inline via `A2AManager.agentCall`.
    var a2aInlineExecutionEnabled: Bool { a2aIntegration == .inlineExecution }

    /// Legacy flag: `true` when integration is `.inlineExecution`.
    @available(*, deprecated, message: "Use a2aIntegration instead")
    public var a2aEnabled: Bool { a2aIntegration == .inlineExecution }

    /// Whether ACP tools are merged into the orchestrator catalog.
    var acpCatalogEnabled: Bool { acpIntegration != .disabled }

    /// Whether the orchestrator executes ACP tools inline via `ACPManager.agentCall`.
    var acpInlineExecutionEnabled: Bool { acpIntegration == .inlineExecution }

    /// Legacy flag: `true` when integration is `.inlineExecution`.
    @available(*, deprecated, message: "Use acpIntegration instead")
    public var acpEnabled: Bool { acpIntegration == .inlineExecution }
    
    public init(
        streamingEnabled: Bool = false,
        mcpEnabled: Bool = false,
        a2aIntegration: A2AOrchestratorIntegration = .disabled,
        acpIntegration: ACPOrchestratorIntegration = .disabled,
        mcpConnectionTimeout: TimeInterval = 30.0,
        toolCallTimeout: TimeInterval = 300.0,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        additionalParameters: JSON? = nil,
        maxAgenticStepsPerUpdate: Int? = nil,
        assistantPersistenceMode: AssistantPersistenceMode = .immediate,
        parallelToolDispatchEnabled: Bool = false,
        toolDispatchPolicyEvaluator: (any ToolDispatchPolicyEvaluating)? = nil,
        dispatchPlannerMode: ToolDispatchPlannerMode? = nil,
        preDispatchPolicyEvaluator: (any ToolPreDispatchPolicyEvaluating)? = nil,
        pendingToolTimeout: TimeInterval? = nil,
        toolInvocationPolicy: ToolInvocationPolicy = .automatic,
        rejectAssistantTurnWithNoToolCallsWhenToolsAvailable: Bool = false,
        maxCorrectionRetries: Int = 0,
        correctionMessage: String = "You must call a tool or indicate you are done.",
        correctionRole: MessageRole = .user
    ) {
        self.streamingEnabled = streamingEnabled
        self.mcpEnabled = mcpEnabled
        self.a2aIntegration = a2aIntegration
        self.acpIntegration = acpIntegration
        self.mcpConnectionTimeout = mcpConnectionTimeout
        self.toolCallTimeout = toolCallTimeout
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.additionalParameters = additionalParameters
        self.maxAgenticStepsPerUpdate = maxAgenticStepsPerUpdate
        self.assistantPersistenceMode = assistantPersistenceMode
        self.parallelToolDispatchEnabled = parallelToolDispatchEnabled
        self.toolDispatchPolicyEvaluator = toolDispatchPolicyEvaluator
        self.dispatchPlannerMode = dispatchPlannerMode
        self.preDispatchPolicyEvaluator = preDispatchPolicyEvaluator
        self.pendingToolTimeout = pendingToolTimeout
        self.toolInvocationPolicy = toolInvocationPolicy
        self.rejectAssistantTurnWithNoToolCallsWhenToolsAvailable = rejectAssistantTurnWithNoToolCallsWhenToolsAvailable
        self.maxCorrectionRetries = maxCorrectionRetries
        self.correctionMessage = correctionMessage
        self.correctionRole = correctionRole
    }

    @available(*, deprecated, message: "Use a2aIntegration instead")
    public init(
        streamingEnabled: Bool = false,
        mcpEnabled: Bool = false,
        a2aEnabled: Bool,
        acpEnabled: Bool = false,
        mcpConnectionTimeout: TimeInterval = 30.0,
        toolCallTimeout: TimeInterval = 300.0,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        additionalParameters: JSON? = nil,
        maxAgenticStepsPerUpdate: Int? = nil,
        assistantPersistenceMode: AssistantPersistenceMode = .immediate,
        parallelToolDispatchEnabled: Bool = false,
        toolDispatchPolicyEvaluator: (any ToolDispatchPolicyEvaluating)? = nil,
        dispatchPlannerMode: ToolDispatchPlannerMode? = nil,
        preDispatchPolicyEvaluator: (any ToolPreDispatchPolicyEvaluating)? = nil,
        pendingToolTimeout: TimeInterval? = nil,
        toolInvocationPolicy: ToolInvocationPolicy = .automatic,
        rejectAssistantTurnWithNoToolCallsWhenToolsAvailable: Bool = false,
        maxCorrectionRetries: Int = 0,
        correctionMessage: String = "You must call a tool or indicate you are done.",
        correctionRole: MessageRole = .user
    ) {
        self.init(
            streamingEnabled: streamingEnabled,
            mcpEnabled: mcpEnabled,
            a2aIntegration: a2aEnabled ? .inlineExecution : .disabled,
            acpIntegration: acpEnabled ? .inlineExecution : .disabled,
            mcpConnectionTimeout: mcpConnectionTimeout,
            toolCallTimeout: toolCallTimeout,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            additionalParameters: additionalParameters,
            maxAgenticStepsPerUpdate: maxAgenticStepsPerUpdate,
            assistantPersistenceMode: assistantPersistenceMode,
            parallelToolDispatchEnabled: parallelToolDispatchEnabled,
            toolDispatchPolicyEvaluator: toolDispatchPolicyEvaluator,
            dispatchPlannerMode: dispatchPlannerMode,
            preDispatchPolicyEvaluator: preDispatchPolicyEvaluator,
            pendingToolTimeout: pendingToolTimeout,
            toolInvocationPolicy: toolInvocationPolicy,
            rejectAssistantTurnWithNoToolCallsWhenToolsAvailable: rejectAssistantTurnWithNoToolCallsWhenToolsAvailable,
            maxCorrectionRetries: maxCorrectionRetries,
            correctionMessage: correctionMessage,
            correctionRole: correctionRole
        )
    }

    @available(*, deprecated, message: "Use acpIntegration instead")
    public init(
        streamingEnabled: Bool = false,
        mcpEnabled: Bool = false,
        a2aIntegration: A2AOrchestratorIntegration = .disabled,
        acpEnabled: Bool,
        mcpConnectionTimeout: TimeInterval = 30.0,
        toolCallTimeout: TimeInterval = 300.0,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        additionalParameters: JSON? = nil,
        maxAgenticStepsPerUpdate: Int? = nil,
        assistantPersistenceMode: AssistantPersistenceMode = .immediate,
        parallelToolDispatchEnabled: Bool = false,
        toolDispatchPolicyEvaluator: (any ToolDispatchPolicyEvaluating)? = nil,
        dispatchPlannerMode: ToolDispatchPlannerMode? = nil,
        preDispatchPolicyEvaluator: (any ToolPreDispatchPolicyEvaluating)? = nil,
        pendingToolTimeout: TimeInterval? = nil,
        toolInvocationPolicy: ToolInvocationPolicy = .automatic,
        rejectAssistantTurnWithNoToolCallsWhenToolsAvailable: Bool = false,
        maxCorrectionRetries: Int = 0,
        correctionMessage: String = "You must call a tool or indicate you are done.",
        correctionRole: MessageRole = .user
    ) {
        self.init(
            streamingEnabled: streamingEnabled,
            mcpEnabled: mcpEnabled,
            a2aIntegration: a2aIntegration,
            acpIntegration: acpEnabled ? .inlineExecution : .disabled,
            mcpConnectionTimeout: mcpConnectionTimeout,
            toolCallTimeout: toolCallTimeout,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            additionalParameters: additionalParameters,
            maxAgenticStepsPerUpdate: maxAgenticStepsPerUpdate,
            assistantPersistenceMode: assistantPersistenceMode,
            parallelToolDispatchEnabled: parallelToolDispatchEnabled,
            toolDispatchPolicyEvaluator: toolDispatchPolicyEvaluator,
            dispatchPlannerMode: dispatchPlannerMode,
            preDispatchPolicyEvaluator: preDispatchPolicyEvaluator,
            pendingToolTimeout: pendingToolTimeout,
            toolInvocationPolicy: toolInvocationPolicy,
            rejectAssistantTurnWithNoToolCallsWhenToolsAvailable: rejectAssistantTurnWithNoToolCallsWhenToolsAvailable,
            maxCorrectionRetries: maxCorrectionRetries,
            correctionMessage: correctionMessage,
            correctionRole: correctionRole
        )
    }
}

/// SwiftAgentKitOrchestrator provides building blocks for creating LLM orchestrators
/// that can use tools through MCP, communicate with other agents through A2A,
/// and execute generic function tools via a configurable ToolManager.
public actor SwiftAgentKitOrchestrator {
    /// Published as ``AgenticLoopState/failed(_:)`` when the model requested tools but no tool responses were aggregated (e.g. nothing handled the calls).
    public static let noToolResponsesAgenticFailureMessage = "No tool responses were produced for the model's tool calls."
    public let logger: Logger
    public let llm: LLMProtocol
    public let config: OrchestratorConfig
    public let mcpManager: MCPManager?
    public let a2aManager: A2AManager?
    public let acpManager: ACPManager?
    /// Optional ToolManager for executing generic function tools (non-MCP, non-A2A)
    public let toolManager: ToolManager?

    private let agenticLoopStateHub: AgenticLoopStateHub
    private let orchestrationObservation: OrchestrationObservationCoordinator
    private let toolLifecycleEventHub: ToolLifecycleEventHub
    private var pendingCompletionStreamContinuation: AsyncStream<PendingToolCompletion>.Continuation?
    private var currentPendingCompletionStream: AsyncStream<PendingToolCompletion>?
    private var pendingHandlesByID: [String: PendingToolHandle] = [:]
    private var pendingHandleRunByID: [String: AgenticLoopID] = [:]
    private var completedPendingHandleIDs: Set<String> = []
    private var pendingTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var activeRuns: [AgenticLoopID: ActiveRunState] = [:]
    private var lastRunOutcomeByID: [AgenticLoopID: UpdateConversationOutcome] = [:]
    
    /// All available tools from MCP and A2A managers
    public var allAvailableTools: [ToolDefinition] {
        get async {
            var allTools: [ToolDefinition] = []
            
            // Get tools from MCP manager if enabled
            if let mcpManager = mcpManager, config.mcpEnabled {
                allTools.append(contentsOf: await mcpManager.availableTools())
            }
            
            // Get tools from A2A manager if enabled
            if let a2aManager = a2aManager, config.a2aCatalogEnabled {
                allTools.append(contentsOf: await a2aManager.availableTools())
            }

            if let acpManager = acpManager, config.acpCatalogEnabled {
                allTools.append(contentsOf: await acpManager.availableTools())
            }
            
            // Get tools from generic ToolManager if configured
            if let toolManager = toolManager {
                allTools.append(contentsOf: await toolManager.allToolsAsync())
            }
            
            return allTools
        }
    }

    /// Canonical tool descriptors with normalized schema + execution metadata.
    public var allRegisteredTools: [RegisteredToolDescriptor] {
        get async {
            var allDescriptors: [RegisteredToolDescriptor] = []
            if let mcpManager = mcpManager, config.mcpEnabled {
                allDescriptors.append(contentsOf: await mcpManager.registeredToolDescriptors())
            }
            if let a2aManager = a2aManager, config.a2aCatalogEnabled {
                allDescriptors.append(contentsOf: await a2aManager.registeredToolDescriptors())
            }
            if let acpManager = acpManager, config.acpCatalogEnabled {
                allDescriptors.append(contentsOf: await acpManager.registeredToolDescriptors())
            }
            if let toolManager = toolManager {
                allDescriptors.append(contentsOf: await toolManager.allRegisteredToolsAsync())
            }
            return allDescriptors
        }
    }
    
    /// Stream of message updates from the orchestrator
    public var messageStream: AsyncStream<Message> {
        get async {
            return currentMessageStream ?? createMessageStream()
        }
    }
    
    /// Stream of partial content updates (streaming assistant text chunks only) from the orchestrator.
    ///
    /// Reasoning and tool-call fragments are excluded; use ``partialFragmentsStream`` for discriminated deltas.
    public var partialContentStream: AsyncStream<String> {
        get async {
            if currentPartialContentStream == nil {
                createPartialStreams()
            }
            return currentPartialContentStream!
        }
    }

    /// Discriminated partial streaming deltas (text, reasoning, tool-call argument fragments).
    ///
    /// Created together with ``partialContentStream`` on first access; subscribe before ``updateConversation``
    /// if you need every chunk.
    public var partialFragmentsStream: AsyncStream<PartialFragment> {
        get async {
            if currentPartialFragmentsStream == nil {
                createPartialStreams()
            }
            return currentPartialFragmentsStream!
        }
    }

    /// Current runtime state from the underlying LLM.
    public var llmCurrentState: LLMRuntimeState {
        llm.currentState
    }

    /// Runtime state updates from the underlying LLM.
    public var llmStateUpdates: AsyncStream<LLMRuntimeState> {
        llm.stateUpdates
    }

    /// Agentic tool-loop state for this orchestrator (multi-call session per top-level `updateConversation`).
    public var agenticLoopUpdates: AsyncStream<(AgenticLoopID, AgenticLoopState)> {
        agenticLoopStateHub.makeStream()
    }

    /// Lifecycle events for individual tool calls.
    public var toolLifecycleEvents: AsyncStream<ToolLifecycleEvent> {
        toolLifecycleEventHub.makeStream()
    }

    /// Stream of delayed pending-tool completions.
    public var pendingToolCompletions: AsyncStream<PendingToolCompletion> {
        get async {
            if let stream = currentPendingCompletionStream {
                return stream
            }
            let stream = AsyncStream<PendingToolCompletion> { continuation in
                self.pendingCompletionStreamContinuation = continuation
            }
            currentPendingCompletionStream = stream
            return stream
        }
    }

    /// Latest published agentic loop state for the given id, if any.
    public func currentAgenticLoopState(for id: AgenticLoopID) -> AgenticLoopState? {
        agenticLoopStateHub.currentState(for: id)
    }

    /// Snapshot of latest agentic loop state per id.
    public var currentAgenticLoopStates: [AgenticLoopID: AgenticLoopState] {
        agenticLoopStateHub.currentStates
    }

    /// Single call returning LLM runtime, per-request states, and agentic-loop states together (see
    /// ``OrchestrationObservationCoordinator``).
    public func currentOrchestrationSnapshot() -> OrchestrationSnapshot {
        orchestrationObservation.currentSnapshot()
    }

    /// Emits ``OrchestrationSnapshotEvent`` whenever any of the underlying observation streams
    /// advances, with a monotonic ``OrchestrationSnapshotEvent/generation`` per emission.
    public var orchestrationSnapshotUpdates: AsyncStream<OrchestrationSnapshotEvent> {
        orchestrationObservation.snapshotUpdates()
    }
    
    /// - Parameters:
    ///   - llm: The LLM protocol implementation.
    ///   - config: Orchestrator configuration (streaming, MCP, A2A, timeouts, etc.).
    ///   - mcpManager: Pre-built MCP manager; if nil and `config.mcpEnabled` is true, one is created.
    ///   - mcpOAuthHandler: Optional OAuth handler for remote MCP servers. When set and the orchestrator
    ///     creates its own MCPManager, that manager will use this handler so remote servers requiring
    ///     manual OAuth can complete the flow. Ignored if `mcpManager` is provided.
    ///   - a2aManager: Pre-built A2A manager; if nil and `config.a2aIntegration` is not `.disabled`, one is created.
    ///   - acpManager: Pre-built ACP manager; if nil and `config.acpCatalogEnabled`, one is created.
    ///   - toolManager: Optional ToolManager for generic function tools.
    ///   - logger: Optional logger; a default is created if nil.
    public init(
        llm: LLMProtocol,
        config: OrchestratorConfig = OrchestratorConfig(),
        mcpManager: MCPManager? = nil,
        mcpOAuthHandler: MCPOAuthHandler? = nil,
        a2aManager: A2AManager? = nil,
        acpManager: ACPManager? = nil,
        toolManager: ToolManager? = nil,
        logger: Logger? = nil
    ) {
        self.llm = llm
        self.config = config
        let resolvedLogger = logger ?? SwiftAgentKitLogging.logger(
            for: .orchestrator,
            metadata: SwiftAgentKitLogging.metadata(
                ("streamingEnabled", .string(config.streamingEnabled ? "true" : "false")),
                ("mcpEnabled", .string(config.mcpEnabled ? "true" : "false")),
                ("a2aIntegration", .string(String(describing: config.a2aIntegration))),
                ("acpIntegration", .string(String(describing: config.acpIntegration)))
            )
        )
        self.logger = resolvedLogger
        if let providedMCPManager = mcpManager {
            self.mcpManager = providedMCPManager
        } else if config.mcpEnabled {
            self.mcpManager = MCPManager(
                connectionTimeout: config.mcpConnectionTimeout,
                logger: SwiftAgentKitLogging.logger(
                    for: .mcp("MCPManager"),
                    metadata: SwiftAgentKitLogging.metadata(
                        ("source", .string("SwiftAgentKitOrchestrator")),
                        ("connectionTimeout", .stringConvertible(config.mcpConnectionTimeout))
                    )
                ),
                oauthHandler: mcpOAuthHandler
            )
        } else {
            self.mcpManager = nil
        }
        
        if let providedA2AManager = a2aManager {
            self.a2aManager = providedA2AManager
        } else if config.a2aCatalogEnabled {
            self.a2aManager = A2AManager(
                logger: SwiftAgentKitLogging.logger(
                    for: .a2a("A2AManager"),
                    metadata: SwiftAgentKitLogging.metadata(
                        ("source", .string("SwiftAgentKitOrchestrator"))
                    )
                )
            )
        } else {
            self.a2aManager = nil
        }

        if let providedACPManager = acpManager {
            self.acpManager = providedACPManager
        } else if config.acpCatalogEnabled {
            self.acpManager = ACPManager(
                logger: SwiftAgentKitLogging.logger(
                    for: .acp("ACPManager"),
                    metadata: SwiftAgentKitLogging.metadata(
                        ("source", .string("SwiftAgentKitOrchestrator"))
                    )
                )
            )
        } else {
            self.acpManager = nil
        }
        
        self.toolManager = toolManager
        let agenticHub = AgenticLoopStateHub()
        self.agenticLoopStateHub = agenticHub
        self.orchestrationObservation = OrchestrationObservationCoordinator(
            llm: llm,
            agenticLoopStateHub: agenticHub
        )
        self.toolLifecycleEventHub = ToolLifecycleEventHub()
    }
    
    /// Process a conversation thread and publish message updates to the message stream
    /// - Parameter messages: Array of messages representing the conversation thread
    /// - Parameter availableTools: Array of available tools that can be used during conversation processing
    public func updateConversation(_ messages: [Message], availableTools: [ToolDefinition] = []) async throws {
        _ = try await updateConversation(messages, availableTools: availableTools, options: .default)
    }

    /// Process a conversation with per-invocation options layered on ``OrchestratorConfig``.
    ///
    /// Each inner LLM call uses a fresh ``LLMRequestConfig`` built from the orchestrator config merged with ``OrchestratorInvocationOptions``
    /// (additional parameters and metadata apply to every step in this `updateConversation` tree).
    @discardableResult
    public func updateConversation(_ messages: [Message], availableTools: [ToolDefinition], options: OrchestratorInvocationOptions) async throws -> UpdateConversationOutcome {
        let outcome = await updateConversationWithOutcome(messages, availableTools: availableTools, options: options)
        switch outcome.terminalState {
        case .completed:
            return outcome
        case .cancelled:
            throw CancellationError()
        case .failed:
            switch outcome.terminalReason {
            case .boundedStop(let limit):
                throw OrchestratorError.agenticStepLimitReached(limit: limit)
            case .failure(let message):
                throw OrchestratorError.processingError(message ?? "Conversation update failed")
            case .externalCancellation:
                throw CancellationError()
            case .naturalStop:
                throw OrchestratorError.processingError("Unexpected failed state with naturalStop")
            }
        }
    }

    /// Non-throwing terminal outcome API for deterministic run result reporting.
    public func updateConversationWithOutcome(
        _ messages: [Message],
        availableTools: [ToolDefinition] = [],
        options: OrchestratorInvocationOptions = .default
    ) async -> UpdateConversationOutcome {
        logger.info(
            "Processing conversation",
            metadata: SwiftAgentKitLogging.metadata(
                ("messageCount", .stringConvertible(messages.count)),
                ("streamingEnabled", .string(config.streamingEnabled ? "true" : "false")),
                ("toolCount", .stringConvertible(availableTools.count))
            )
        )
        if !availableTools.isEmpty {
            let toolNames = availableTools.map { $0.name }
            logger.debug(
                "Resolved available tools",
                metadata: SwiftAgentKitLogging.metadata(
                    ("tools", .array(toolNames.map { .string($0) }))
                )
            )
        }
        let context = makeInvocationContext(options: options)
        let runID = AgenticLoopID.orchestratorSession(UUID())
        activeRuns[runID] = ActiveRunState(assistantPersistenceMode: context.assistantPersistenceMode)
        do {
            try await updateConversationWithAgenticLoop(
                messages,
                availableTools: availableTools,
                iteration: 1,
                agenticLoopId: runID,
                context: context
            )
            let cancellationRequested = activeRuns[runID]?.cancellationRequested ?? false
            if cancellationRequested {
                let outcome = await finalizeRunOutcome(
                    runID: runID,
                    terminalState: .cancelled,
                    terminalReason: .externalCancellation,
                    commitAssistantMessages: false
                )
                return outcome
            }
            return await finalizeRunOutcome(
                runID: runID,
                terminalState: .completed,
                terminalReason: .naturalStop,
                commitAssistantMessages: true
            )
        } catch {
            if error is CancellationError || (activeRuns[runID]?.cancellationRequested ?? false) {
                return await finalizeRunOutcome(
                    runID: runID,
                    terminalState: .cancelled,
                    terminalReason: .externalCancellation,
                    commitAssistantMessages: false
                )
            }
            if let orchestratorError = error as? OrchestratorError {
                if case .agenticStepLimitReached(let limit) = orchestratorError {
                    return await finalizeRunOutcome(
                        runID: runID,
                        terminalState: .failed,
                        terminalReason: .boundedStop(limit: limit),
                        commitAssistantMessages: false
                    )
                }
            }
            return await finalizeRunOutcome(
                runID: runID,
                terminalState: .failed,
                terminalReason: .failure(error.localizedDescription),
                commitAssistantMessages: false
            )
        }
    }

    /// Directly invoke a single tool without an LLM roundtrip.
    public func invokeTool(_ request: ToolInvocationRequest) async -> ToolInvocationOutcome {
        let batchRequest = ToolBatchInvocationRequest(
            requests: [normalizeInvocationRequest(request)],
            plannerMode: config.dispatchPlannerMode,
            defaultTimeoutSeconds: config.toolCallTimeout,
            conversationID: request.conversationID,
            runID: request.runID,
            source: request.source
        )
        let outcome = await invokeTools(batchRequest)
        return outcome.outcomes.first ?? .denied(
            metadata: ToolInvocationMetadata(
                conversationID: request.conversationID,
                runID: request.runID,
                source: request.source,
                callerProvenance: request.callerProvenance,
                policyDecision: nil,
                dispatchMode: nil,
                dispatchPlan: outcome.diagnostics
            )
        )
    }

    /// Directly invoke one or more tools with deterministic planning and policy enforcement.
    public func invokeTools(_ request: ToolBatchInvocationRequest) async -> ToolBatchInvocationOutcome {
        let normalizedRequests = request.requests.map(normalizeInvocationRequest(_:))
        let plannerMode = request.plannerMode ?? config.dispatchPlannerMode ?? .serial
        let dispatchPlan = await makeDispatchPlan(
            requests: normalizedRequests,
            plannerMode: plannerMode,
            explicitSafety: [:],
            parallelEnabledHint: config.parallelToolDispatchEnabled
        )
        let invocationRunID = request.runID ?? "direct-\(UUID().uuidString)"
        var outcomesByCallID: [String: ToolInvocationOutcome] = [:]
        for stage in dispatchPlan.stages {
            let stageRequests = normalizedRequests.filter { stage.toolCallIDs.contains($0.toolCallID) }
            if stage.mode == .parallel {
                let parallelResults = await withTaskGroup(of: (String, ToolInvocationOutcome).self) { group in
                    for stageRequest in stageRequests {
                        group.addTask { [self] in
                            let outcome = await executeInvocationRequest(
                                stageRequest,
                                dispatchMode: .parallel,
                                runID: .orchestratorSession(UUID()),
                                invocationRunID: invocationRunID,
                                source: request.source,
                                conversationID: request.conversationID,
                                batchDiagnostics: dispatchPlan.diagnostics
                            )
                            return (stageRequest.toolCallID, outcome)
                        }
                    }
                    var collected: [(String, ToolInvocationOutcome)] = []
                    for await value in group {
                        collected.append(value)
                    }
                    return collected
                }
                parallelResults.forEach { outcomesByCallID[$0.0] = $0.1 }
            } else {
                for stageRequest in stageRequests {
                    outcomesByCallID[stageRequest.toolCallID] = await executeInvocationRequest(
                        stageRequest,
                        dispatchMode: .serial,
                        runID: .orchestratorSession(UUID()),
                        invocationRunID: invocationRunID,
                        source: request.source,
                        conversationID: request.conversationID,
                        batchDiagnostics: dispatchPlan.diagnostics
                    )
                }
            }
        }
        let ordered = normalizedRequests.map { request in
            outcomesByCallID[request.toolCallID] ?? .denied(
                metadata: ToolInvocationMetadata(
                    conversationID: request.conversationID ?? request.conversationID,
                    runID: invocationRunID,
                    source: request.source,
                    callerProvenance: request.callerProvenance,
                    policyDecision: nil,
                    dispatchMode: nil,
                    dispatchPlan: dispatchPlan.diagnostics
                )
            )
        }
        return ToolBatchInvocationOutcome(outcomes: ordered, diagnostics: dispatchPlan.diagnostics)
    }

    private func makeInvocationContext(options: OrchestratorInvocationOptions) -> OrchestratorInvocationContext {
        var merged = mergeJSONObjectParameters(config.additionalParameters, options.additionalParameters)
        if let meta = options.systemPromptMetadata, !meta.isEmpty {
            let metaJSON = JSON.object(Dictionary(uniqueKeysWithValues: meta.map { ($0.key, JSON.string($0.value)) }))
            merged = mergeJSONObjectParameters(merged, metaJSON)
        }
        let policy = options.toolInvocationPolicy ?? config.toolInvocationPolicy
        let assistantMode = options.assistantPersistenceMode ?? config.assistantPersistenceMode
        let parallelEnabled = options.parallelToolDispatchEnabled ?? config.parallelToolDispatchEnabled
        let plannerMode = options.dispatchPlannerMode ?? config.dispatchPlannerMode
        let safetyMetadata = options.toolParallelSafetyMetadata ?? [:]
        let preDispatchPolicy = options.preDispatchPolicyEvaluator ?? config.preDispatchPolicyEvaluator
        let maxSteps = options.maxAgenticStepsPerUpdate ?? config.maxAgenticStepsPerUpdate
        let reject = options.rejectAssistantTurnWithNoToolCallsWhenToolsAvailable ?? config.rejectAssistantTurnWithNoToolCallsWhenToolsAvailable
        let maxCorr = options.maxCorrectionRetries ?? config.maxCorrectionRetries
        let msg = options.correctionMessage ?? config.correctionMessage
        let role = options.correctionRole ?? config.correctionRole
        return OrchestratorInvocationContext(
            mergedAdditionalParameters: merged,
            toolInvocationPolicy: policy,
            assistantPersistenceMode: assistantMode,
            parallelToolDispatchEnabled: parallelEnabled,
            dispatchPlannerMode: plannerMode,
            toolParallelSafetyMetadata: safetyMetadata,
            preDispatchPolicyEvaluator: preDispatchPolicy,
            maxAgenticStepsPerUpdate: maxSteps,
            rejectProseWithoutTools: reject,
            maxCorrectionRetries: maxCorr,
            correctionMessage: msg,
            correctionRole: role
        )
    }

    private func updateConversationWithAgenticLoop(
        _ messages: [Message],
        availableTools: [ToolDefinition],
        iteration: Int,
        agenticLoopId: AgenticLoopID?,
        context: OrchestratorInvocationContext
    ) async throws {
        let loopId = agenticLoopId ?? AgenticLoopID.orchestratorSession(UUID())
        let isRootEntry = iteration == 1
        if isRootEntry {
            agenticLoopStateHub.publish(loopId, .started)
        }
        if isRunCancellationRequested(loopId) || Task.isCancelled {
            agenticLoopStateHub.publish(loopId, .cancelled)
            throw CancellationError()
        }
        if let max = context.maxAgenticStepsPerUpdate, iteration > max {
            agenticLoopStateHub.publish(loopId, .maxIterationsReached)
            throw OrchestratorError.agenticStepLimitReached(limit: max)
        }
        agenticLoopStateHub.publish(loopId, .llmCall(iteration: iteration))

        var updatedMessages = messages

        let requestConfig = LLMRequestConfig(
            maxTokens: config.maxTokens,
            temperature: config.temperature,
            topP: config.topP,
            stream: config.streamingEnabled,
            availableTools: availableTools,
            additionalParameters: context.mergedAdditionalParameters,
            toolInvocationPolicy: context.toolInvocationPolicy
        )

        do {
            let response = try await performAgenticLLMCall(
                initialMessages: messages,
                availableTools: availableTools,
                requestConfig: requestConfig,
                loopId: loopId,
                iteration: iteration,
                context: context
            )

            logger.info(
                "Received model response",
                metadata: SwiftAgentKitLogging.metadata(
                    ("contentLength", .stringConvertible(response.content.count)),
                    ("hasToolCalls", .string(response.hasToolCalls ? "true" : "false"))
                )
            )

            let toolCallsWithIds = response.hasToolCalls ? ensureToolCallsHaveIds(response.toolCalls) : response.toolCalls
            let responseMessage = Message(id: UUID(), role: .assistant, content: response.content, toolCalls: toolCallsWithIds)
            updatedMessages.append(responseMessage)
            publishMessage(responseMessage, runID: loopId)

            if response.hasToolCalls {
                if isRunCancellationRequested(loopId) || Task.isCancelled {
                    agenticLoopStateHub.publish(loopId, .cancelled)
                    throw CancellationError()
                }
                transitionLLMState(to: .idle(.ready))
                agenticLoopStateHub.publish(loopId, .waitingForToolExecution)
                agenticLoopStateHub.publish(loopId, .executingTools)
                logger.info(
                    "Response contains tool calls",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("toolCallCount", .stringConvertible(toolCallsWithIds.count))
                    )
                )
                let toolExecution = await executeToolCalls(toolCallsWithIds, context: context, runID: loopId)
                let toolResponses = toolExecution.responses

                guard !toolResponses.isEmpty || toolExecution.hasPending else {
                    logger.warning(
                        "No tool responses after model requested tool calls; ending agentic loop",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("iteration", .stringConvertible(iteration)),
                            ("toolCallCount", .stringConvertible(toolCallsWithIds.count))
                        )
                    )
                    transitionLLMState(to: .idle(.ready))
                    agenticLoopStateHub.publish(loopId, .failed(Self.noToolResponsesAgenticFailureMessage))
                    return
                }

                if toolResponses.isEmpty && toolExecution.hasPending {
                    logger.info(
                        "Tool batch accepted as pending; waiting for asynchronous completion callbacks",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("pendingCount", .stringConvertible(toolExecution.pendingCount))
                        )
                    )
                    agenticLoopStateHub.publish(loopId, .completed)
                    transitionLLMState(to: .idle(.ready))
                    return
                }

                logger.info(
                    "Sending tool responses back to LLM",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("responseCount", .stringConvertible(toolResponses.count))
                    )
                )
                let toolResponseMessages = toolResponses.map { messageFromToolResponse($0) }
                updatedMessages.append(contentsOf: toolResponseMessages)
                toolResponseMessages.forEach { publishMessage($0, runID: loopId) }

                agenticLoopStateHub.publish(loopId, .betweenIterations)
                if isRunCancellationRequested(loopId) || Task.isCancelled {
                    agenticLoopStateHub.publish(loopId, .cancelled)
                    throw CancellationError()
                }
                try await LLMQueuePriority.$current.withValue(.continuation) {
                    try await updateConversationWithAgenticLoop(updatedMessages, availableTools: availableTools, iteration: iteration + 1, agenticLoopId: loopId, context: context)
                }
            } else {
                agenticLoopStateHub.publish(loopId, .completed)
                transitionLLMState(to: .idle(.completed))
                transitionLLMState(to: .idle(.ready))
            }
        } catch {
            if error is CancellationError {
                agenticLoopStateHub.publish(loopId, .cancelled)
                transitionLLMState(to: .idle(.ready))
                throw error
            }
            agenticLoopStateHub.publish(loopId, .failed(error.localizedDescription))
            transitionLLMState(to: .failed(error.localizedDescription))
            transitionLLMState(to: .idle(.ready))
            throw error
        }
    }

    private func performAgenticLLMCall(
        initialMessages: [Message],
        availableTools: [ToolDefinition],
        requestConfig: LLMRequestConfig,
        loopId: AgenticLoopID,
        iteration: Int,
        context: OrchestratorInvocationContext
    ) async throws -> LLMResponse {
        var working = initialMessages
        var remainingCorrections = context.maxCorrectionRetries

        while true {
            let response: LLMResponse
            if config.streamingEnabled {
                response = try await streamToCompleteLLMResponse(messages: working, config: requestConfig)
            } else {
                transitionLLMState(to: .generating(.reasoning))
                response = try await llm.send(working, config: requestConfig)
            }

            let summary = Self.makeGenerationSummary(iteration: iteration, response: response)
            agenticLoopStateHub.publish(loopId, .llmGenerationCompleted(summary))

            let reject = shouldRejectAssistantTurn(
                response: response,
                conversationMessages: working,
                availableTools: availableTools,
                context: context
            )
            if !reject {
                return response
            }
            if remainingCorrections == 0 {
                throw OrchestratorError.assistantTurnCorrectionRetriesExhausted(configuredMaxCorrectionRetries: context.maxCorrectionRetries)
            }
            remainingCorrections -= 1
            let correction = Message(
                id: UUID(),
                role: context.correctionRole,
                content: context.correctionMessage
            )
            working.append(correction)
        }
    }

    private static func makeGenerationSummary(iteration: Int, response: LLMResponse) -> LLMGenerationSummary {
        let meta = response.metadata
        return LLMGenerationSummary(
            innerStepIndex: iteration,
            hadToolCalls: response.hasToolCalls,
            toolNames: response.toolCalls.map(\.name),
            finishReason: meta?.finishReason,
            promptTokens: meta?.promptTokens,
            completionTokens: meta?.completionTokens,
            totalTokens: meta?.totalTokens
        )
    }

    private func shouldRejectAssistantTurn(
        response: LLMResponse,
        conversationMessages: [Message],
        availableTools: [ToolDefinition],
        context: OrchestratorInvocationContext
    ) -> Bool {
        guard context.rejectProseWithoutTools,
              !availableTools.isEmpty,
              !response.hasToolCalls
        else { return false }
        // After tool outputs exist in the thread, allow plain assistant text (e.g. final summary).
        let hadToolOutput = conversationMessages.contains { $0.role == .tool }
        return !hadToolOutput
    }

    private func streamToCompleteLLMResponse(messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        if currentPartialContentStream == nil {
            createPartialStreams()
        }
        transitionLLMState(to: .generating(.reasoning))
        let stream = llm.stream(messages, config: config)
        var finalResponse: LLMResponse?
        for try await result in stream {
            if Task.isCancelled {
                throw CancellationError()
            }
            switch result {
            case .stream(let response):
                transitionLLMState(to: .generating(.responding))
                logger.debug(
                    "Received streaming chunk",
                    metadata: metadataForStreamingPartial(response)
                )
                publishStreamingPartial(from: response)
            case .complete(let response):
                finalResponse = response
            }
        }
        if Task.isCancelled {
            throw CancellationError()
        }
        guard let response = finalResponse else {
            throw LLMError.invalidResponse("Streaming ended without a complete response")
        }
        finishPartialStreamsForStreamingTurn()
        return response
    }
    
    /// Finishes ``messageStream``, ``partialContentStream``, and ``partialFragmentsStream`` continuations.
    public func endMessageStream() {
        messageStreamContinuation?.finish()
        messageStreamContinuation = nil
        currentMessageStream = nil
        partialContentStreamContinuation?.finish()
        partialContentStreamContinuation = nil
        currentPartialContentStream = nil
        partialFragmentsStreamContinuation?.finish()
        partialFragmentsStreamContinuation = nil
        currentPartialFragmentsStream = nil
        pendingCompletionStreamContinuation?.finish()
        pendingCompletionStreamContinuation = nil
        currentPendingCompletionStream = nil
    }

    /// Accepts an externally produced completion for a pending handle.
    /// Duplicate completions for the same handle are ignored.
    public func submitPendingCompletion(_ completion: PendingToolCompletion) async {
        await onPendingCompletion(completion)
    }

    /// Cancels an active run and in-flight pending handles bound to it.
    public func cancelRun(runID: AgenticLoopID, conversationID: String? = nil) async -> CancelOutcome {
        guard var run = activeRuns[runID] else {
            return CancelOutcome(runID: runID, cancelledToolHandles: [], terminalState: .cancelled)
        }
        run.cancellationRequested = true
        activeRuns[runID] = run

        var cancelledHandles: [PendingToolHandle] = []
        for handleID in run.pendingHandleIDs {
            if let handle = pendingHandlesByID[handleID] {
                cancelledHandles.append(handle)
            }
            await cancelPendingTool(handleID: handleID, reason: "Run cancelled")
        }
        return CancelOutcome(
            runID: runID,
            cancelledToolHandles: cancelledHandles,
            terminalState: .cancelled
        )
    }

    /// Snapshot active runs for orphan/restart recovery.
    public func recoverableActiveRunsSnapshot() -> [RecoverableActiveRunMetadata] {
        activeRuns.map { runID, run in
            RecoverableActiveRunMetadata(
                runID: runID,
                pendingHandleIDs: Array(run.pendingHandleIDs).sorted(),
                cancellationRequested: run.cancellationRequested
            )
        }
    }

    public func lastRunOutcome(for runID: AgenticLoopID) -> UpdateConversationOutcome? {
        lastRunOutcomeByID[runID]
    }

    /// Marks a run as abandoned for host-level recovery workflows.
    public func markRunAbandoned(_ runID: AgenticLoopID) {
        guard var run = activeRuns[runID] else { return }
        run.cancellationRequested = true
        activeRuns[runID] = run
        agenticLoopStateHub.publish(runID, .cancelled)
    }

    /// Cancels a pending handle if it is still active.
    public func cancelPendingTool(handleID: String, reason: String? = nil) async {
        guard let handle = pendingHandlesByID.removeValue(forKey: handleID) else {
            return
        }
        if let runID = pendingHandleRunByID.removeValue(forKey: handleID) {
            if var run = activeRuns[runID] {
                run.pendingHandleIDs.remove(handleID)
                if run.pendingHandleIDs.isEmpty, run.terminalOutcome != nil {
                    activeRuns[runID] = nil
                } else {
                    activeRuns[runID] = run
                }
            }
        }
        pendingTimeoutTasks[handleID]?.cancel()
        pendingTimeoutTasks.removeValue(forKey: handleID)
        completedPendingHandleIDs.insert(handleID)

        let cancelledByManager = await a2aManager?.cancelPendingHandle(handleID) ?? false
        let cancellationReason = reason ?? (cancelledByManager ? "Cancelled by host" : "Cancelled")
        publishToolLifecycle(
            toolCallID: handle.toolCallID,
            toolName: nil,
            state: .cancelled,
            dispatchMode: nil
        )
        logger.info(
            "Pending tool cancelled",
            metadata: SwiftAgentKitLogging.metadata(
                ("handleID", .string(handleID)),
                ("toolCallID", .string(handle.toolCallID)),
                ("reason", .string(cancellationReason))
            )
        )
    }
    
    // MARK: - Private
    
    /// Current message stream
    private var currentMessageStream: AsyncStream<Message>?
    
    /// Current partial content stream (assistant text only)
    private var currentPartialContentStream: AsyncStream<String>?

    /// Current discriminated partial fragments stream
    private var currentPartialFragmentsStream: AsyncStream<PartialFragment>?

    /// Internal stream continuation for publishing messages
    private var messageStreamContinuation: AsyncStream<Message>.Continuation?

    /// Internal stream continuation for publishing partial assistant text
    private var partialContentStreamContinuation: AsyncStream<String>.Continuation?

    /// Internal stream continuation for publishing ``PartialFragment`` values
    private var partialFragmentsStreamContinuation: AsyncStream<PartialFragment>.Continuation?
    
    /// Publish a message to the stream (assistant can be staged per run policy).
    private func publishMessage(_ message: Message, runID: AgenticLoopID?) {
        if message.role == .assistant, let runID, var run = activeRuns[runID], run.assistantPersistenceMode == .stagedCommit {
            run.stagedAssistantMessages.append(message)
            activeRuns[runID] = run
            return
        }
        logger.debug(
            "Publishing message",
            metadata: metadataForMessage(message)
        )
        messageStreamContinuation?.yield(message)
    }
    
    /// Publish partial content to the legacy string stream (assistant ``PartialFragment/text`` only).
    private func publishPartialContent(_ content: String) {
        logger.debug(
            "Publishing partial content chunk",
            metadata: metadataForStreamingContent(content)
        )
        partialContentStreamContinuation?.yield(content)
    }

    /// Classifies a streaming chunk and publishes to both partial streams.
    private func publishStreamingPartial(from response: LLMResponse) {
        let fragment = response.streamingFragment ?? .text(response.content)
        partialFragmentsStreamContinuation?.yield(fragment)
        if case .text(let text) = fragment {
            publishPartialContent(text)
        }
    }

    private func transitionLLMState(to state: LLMRuntimeState) {
        guard let controllable = llm as? any LLMRuntimeStateControllable else {
            return
        }
        controllable.transition(to: state)
    }

    private func finishPartialStreamsForStreamingTurn() {
        partialContentStreamContinuation?.finish()
        partialContentStreamContinuation = nil
        currentPartialContentStream = nil
        partialFragmentsStreamContinuation?.finish()
        partialFragmentsStreamContinuation = nil
        currentPartialFragmentsStream = nil
    }
    
    /// Create a message stream if one does not exist
    private func createMessageStream() -> AsyncStream<Message> {
        let stream = AsyncStream { continuation in
            self.messageStreamContinuation = continuation
        }
        self.currentMessageStream = stream
        logger.debug("Created message stream")
        return stream
    }
    
    /// Creates partial text and partial fragments streams together if they do not exist.
    private func createPartialStreams() {
        let stringStream = AsyncStream<String> { continuation in
            self.partialContentStreamContinuation = continuation
        }
        self.currentPartialContentStream = stringStream
        let fragmentsStream = AsyncStream<PartialFragment> { continuation in
            self.partialFragmentsStreamContinuation = continuation
        }
        self.currentPartialFragmentsStream = fragmentsStream
        logger.debug("Created partial content and partial fragments streams")
    }
    
    /// Ensures all tool calls have IDs, generating them if missing
    /// Some LLM models don't provide tool call IDs, so we generate them here
    /// - Parameter toolCalls: Array of tool calls that may or may not have IDs
    /// - Returns: Array of tool calls with guaranteed IDs
    private func ensureToolCallsHaveIds(_ toolCalls: [ToolCall]) -> [ToolCall] {
        return toolCalls.map { toolCall in
            if toolCall.id != nil {
                return toolCall
            }
            // Generate a unique ID for tool calls without one
            // Format: "call_" followed by a short UUID (first 8 characters)
            let generatedId = "call_\(UUID().uuidString.prefix(8))"
            return ToolCall(
                name: toolCall.name,
                arguments: toolCall.arguments,
                instructions: toolCall.instructions,
                id: generatedId
            )
        }
    }
    
    /// Converts a ToolResult from ToolManager/ToolProvider into an LLMResponse for the conversation
    private func llmResponseFromToolResult(_ result: ToolResult, toolCallId: String?) -> LLMResponse {
        let content: String = {
            if result.success {
                return result.content
            }
            let baseError = result.error ?? "Tool execution failed"
            return "\(baseError) Please try another tool or approach."
        }()
        let metadata: LLMMetadata? = {
            guard case .object(let dict) = result.metadata, !dict.isEmpty else { return nil }
            return LLMMetadata(modelMetadata: result.metadata)
        }()
        return LLMResponse.complete(content: content, metadata: metadata, toolCallId: toolCallId)
    }
    
    private func llmResponseFromToolExecutionError(_ error: Error, toolCallId: String?) -> LLMResponse {
        if let timeout = error as? ToolCallTimeoutError {
            return LLMResponse.complete(content: timeout.message, toolCallId: toolCallId)
        }
        return LLMResponse.complete(content: "Tool execution failed: \(error)", toolCallId: toolCallId)
    }
    
    /// Builds a conversation Message from a tool call LLMResponse, including images and file references.
    /// When the response contains files (URLs or data), appends a text summary so the next LLM turn sees them.
    private func messageFromToolResponse(_ response: LLMResponse) -> Message {
        var content = response.content
        if !response.files.isEmpty {
            let fileDescriptions = response.files.map { file in
                let name = file.name ?? "attachment"
                if let url = file.url {
                    return "\(name): \(url.absoluteString)"
                }
                if let data = file.data {
                    return "\(name): \(data.count) bytes"
                }
                return name
            }
            let attachmentSummary = "\n\n[Attachments: " + fileDescriptions.joined(separator: ", ") + "]"
            content = content.isEmpty ? attachmentSummary.trimmingCharacters(in: .whitespacesAndNewlines) : content + attachmentSummary
        }
        return Message(
            id: UUID(),
            role: .tool,
            content: content,
            images: response.images,
            toolCalls: response.toolCalls,
            toolCallId: response.toolCallId
        )
    }
    
    /// Execute tool calls using available managers.
    private func executeToolCalls(
        _ toolCalls: [ToolCall],
        context: OrchestratorInvocationContext,
        runID: AgenticLoopID
    ) async -> ToolExecutionBatchResult {
        guard let plannerMode = context.dispatchPlannerMode else {
            let dispatchDecision = await decideDispatchPolicy(for: toolCalls, context: context)
            if dispatchDecision.mode == .parallel {
                return await executeToolCallsInParallel(toolCalls, dispatchMode: .parallel, runID: runID, context: context)
            }
            return await executeToolCallsSerially(toolCalls, dispatchMode: .serial, runID: runID, context: context)
        }
        let plan = await makeDispatchPlan(
            toolCalls: toolCalls,
            plannerMode: plannerMode,
            explicitSafety: context.toolParallelSafetyMetadata,
            parallelEnabledHint: context.parallelToolDispatchEnabled
        )
        logger.info(
            "Dispatch plan selected",
            metadata: SwiftAgentKitLogging.metadata(
                ("plannerMode", .string(plan.diagnostics.plannerMode.rawValue)),
                ("reason", .string(plan.diagnostics.reason))
            )
        )
        var aggregated: [LLMResponse] = []
        var pendingCount = 0
        for stage in plan.stages {
            let stageCalls = toolCalls.filter { stage.toolCallIDs.contains($0.id ?? "") }
            let batch: ToolExecutionBatchResult
            if stage.mode == .parallel {
                batch = await executeToolCallsInParallel(stageCalls, dispatchMode: .parallel, runID: runID, context: context)
            } else {
                batch = await executeToolCallsSerially(stageCalls, dispatchMode: .serial, runID: runID, context: context)
            }
            aggregated.append(contentsOf: batch.responses)
            pendingCount += batch.pendingCount
        }
        return ToolExecutionBatchResult(responses: aggregated, pendingCount: pendingCount)
    }

    private func executeToolCallsSerially(
        _ toolCalls: [ToolCall],
        dispatchMode: ToolDispatchMode,
        runID: AgenticLoopID,
        context: OrchestratorInvocationContext
    ) async -> ToolExecutionBatchResult {
        var aggregated: [LLMResponse] = []
        var pendingCount = 0
        for toolCall in toolCalls {
            let outcome = await executeSingleToolCall(toolCall, dispatchMode: dispatchMode, runID: runID, context: context)
            aggregated.append(contentsOf: outcome.responses)
            if outcome.pendingAccepted {
                pendingCount += 1
            }
        }
        return ToolExecutionBatchResult(responses: aggregated, pendingCount: pendingCount)
    }

    private func executeToolCallsInParallel(
        _ toolCalls: [ToolCall],
        dispatchMode: ToolDispatchMode,
        runID: AgenticLoopID,
        context: OrchestratorInvocationContext
    ) async -> ToolExecutionBatchResult {
        let indexed = await withTaskGroup(of: (Int, SingleToolExecutionOutcome).self) { group in
            for (index, toolCall) in toolCalls.enumerated() {
                group.addTask { [self] in
                    let outcome = await executeSingleToolCall(toolCall, dispatchMode: dispatchMode, runID: runID, context: context)
                    return (index, outcome)
                }
            }
            var collected: [(Int, SingleToolExecutionOutcome)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        let sorted = indexed.sorted { $0.0 < $1.0 }.map(\.1)
        let responses = sorted.flatMap(\.responses)
        let pendingCount = sorted.filter(\.pendingAccepted).count
        return ToolExecutionBatchResult(responses: responses, pendingCount: pendingCount)
    }

    private func executeSingleToolCall(
        _ toolCall: ToolCall,
        dispatchMode: ToolDispatchMode,
        runID: AgenticLoopID,
        context: OrchestratorInvocationContext
    ) async -> SingleToolExecutionOutcome {
        if isRunCancellationRequested(runID) || Task.isCancelled {
            return SingleToolExecutionOutcome(responses: [], pendingAccepted: false)
        }
        logger.info(
            "Executing tool call",
            metadata: metadataForToolCall(toolCall, provider: "orchestrator")
        )
        let callID = toolCall.id ?? "unknown"
        if let policyOutcome = await evaluatePreDispatchPolicy(
            for: toolCall,
            context: context,
            runID: String(describing: runID),
            source: .model,
            dispatchMode: dispatchMode
        ) {
            return policyOutcome
        }
        publishToolLifecycle(toolCallID: callID, toolName: toolCall.name, state: .started, dispatchMode: dispatchMode)
        var callResponses: [LLMResponse] = []
        var abortedWithError: LLMResponse?

        // Try MCP manager first
        if let mcpManager = mcpManager, config.mcpEnabled {
            do {
                let mcpResponses = try await mcpManager.toolCall(toolCall, orchestratorDefaultTimeout: config.toolCallTimeout)
                if let mcpResponses {
                    let responsesWithID = mcpResponses.map { response in
                        LLMResponse(
                            content: response.content,
                            toolCalls: response.toolCalls,
                            metadata: response.metadata,
                            isComplete: response.isComplete,
                            toolCallId: toolCall.id
                        )
                    }
                    callResponses.append(contentsOf: responsesWithID)
                }
            } catch {
                abortedWithError = llmResponseFromToolExecutionError(error, toolCallId: toolCall.id)
            }
        }
        if let err = abortedWithError {
            publishToolLifecycle(toolCallID: callID, toolName: toolCall.name, state: .failed(err.content), dispatchMode: dispatchMode)
            return SingleToolExecutionOutcome(responses: [err], pendingAccepted: false)
        }

        // Try A2A manager
        if let a2aManager = a2aManager, config.a2aInlineExecutionEnabled {
            do {
                let a2aResponses = try await a2aManager.agentCall(toolCall, orchestratorDefaultTimeout: config.toolCallTimeout)
                if let a2aResponses {
                    let responsesWithID = a2aResponses.map { response in
                        LLMResponse(
                            content: response.content,
                            toolCalls: response.toolCalls,
                            metadata: response.metadata,
                            isComplete: response.isComplete,
                            toolCallId: toolCall.id
                        )
                    }
                    callResponses.append(contentsOf: responsesWithID)
                }
            } catch {
                abortedWithError = llmResponseFromToolExecutionError(error, toolCallId: toolCall.id)
            }
        }
        if let err = abortedWithError {
            publishToolLifecycle(toolCallID: callID, toolName: toolCall.name, state: .failed(err.content), dispatchMode: dispatchMode)
            return SingleToolExecutionOutcome(responses: [err], pendingAccepted: false)
        }

        // Try ACP manager
        if let acpManager = acpManager, config.acpInlineExecutionEnabled {
            do {
                let acpResponses = try await acpManager.agentCall(toolCall, orchestratorDefaultTimeout: config.toolCallTimeout)
                if let acpResponses {
                    let responsesWithID = acpResponses.map { response in
                        LLMResponse(
                            content: response.content,
                            toolCalls: response.toolCalls,
                            metadata: response.metadata,
                            isComplete: response.isComplete,
                            toolCallId: toolCall.id
                        )
                    }
                    callResponses.append(contentsOf: responsesWithID)
                }
            } catch {
                abortedWithError = llmResponseFromToolExecutionError(error, toolCallId: toolCall.id)
            }
        }
        if let err = abortedWithError {
            publishToolLifecycle(toolCallID: callID, toolName: toolCall.name, state: .failed(err.content), dispatchMode: dispatchMode)
            return SingleToolExecutionOutcome(responses: [err], pendingAccepted: false)
        }

        // Try generic ToolManager if MCP, A2A, and ACP didn't handle the tool
        if callResponses.isEmpty, let toolManager = toolManager {
            do {
                let outcome = try await withToolCallTimeout(config.toolCallTimeout, toolName: toolCall.name) {
                    try await toolManager.executeToolOutcome(toolCall)
                }
                switch outcome {
                case .completed(let result):
                    let response = llmResponseFromToolResult(result, toolCallId: toolCall.id)
                    callResponses.append(response)
                case .pending(let handle):
                    registerPendingHandle(handle, toolName: toolCall.name, dispatchMode: dispatchMode, runID: runID)
                    return SingleToolExecutionOutcome(responses: [], pendingAccepted: true)
                }
            } catch {
                let response = llmResponseFromToolExecutionError(error, toolCallId: toolCall.id)
                publishToolLifecycle(toolCallID: callID, toolName: toolCall.name, state: .failed(response.content), dispatchMode: dispatchMode)
                return SingleToolExecutionOutcome(responses: [response], pendingAccepted: false)
            }
        }

        publishToolLifecycle(toolCallID: callID, toolName: toolCall.name, state: .completed, dispatchMode: dispatchMode)
        return SingleToolExecutionOutcome(responses: callResponses, pendingAccepted: false)
    }

    private func decideDispatchPolicy(
        for toolCalls: [ToolCall],
        context: OrchestratorInvocationContext
    ) async -> ToolDispatchPolicyDecision {
        let metadata = await collectParallelSafetyMetadata(
            for: toolCalls,
            explicit: context.toolParallelSafetyMetadata
        )
        let evaluator = config.toolDispatchPolicyEvaluator ??
            DefaultToolDispatchPolicyEvaluator(orchestratorParallelModeEnabled: context.parallelToolDispatchEnabled)
        return evaluator.decide(toolCalls: toolCalls, metadata: metadata)
    }

    private func collectParallelSafetyMetadata(
        for toolCalls: [ToolCall],
        explicit: [ToolCallID: ToolParallelSafety]
    ) async -> [ToolCallID: ToolParallelSafety] {
        var metadata = explicit
        guard let toolManager else { return metadata }
        for toolCall in toolCalls {
            guard let id = toolCall.id, metadata[id] == nil else { continue }
            metadata[id] = await toolManager.parallelSafety(for: toolCall)
        }
        return metadata
    }

    private func normalizeInvocationRequest(_ request: ToolInvocationRequest) -> ToolInvocationRequest {
        var normalizedArgs = request.argumentsPayload
        if request.argumentMode == .raw, let envelope = request.rawEnvelope {
            normalizedArgs = .object([
                "envelopeVersion": .string(envelope.envelopeVersion),
                "rawText": .string(envelope.rawText),
                "commandToken": envelope.commandToken.map(JSON.string) ?? .string(""),
                "commandName": envelope.commandName.map(JSON.string) ?? .string(""),
                "argsText": envelope.argsText.map(JSON.string) ?? .string(""),
                "parsedTokens": .array((envelope.parsedTokens ?? []).map(JSON.string))
            ])
        }
        return ToolInvocationRequest(
            toolName: request.toolName,
            argumentsPayload: normalizedArgs,
            toolCallID: request.toolCallID,
            argumentMode: request.argumentMode,
            rawEnvelope: request.rawEnvelope,
            conversationID: request.conversationID,
            runID: request.runID,
            source: request.source,
            callerProvenance: request.callerProvenance,
            policyContext: request.policyContext,
            timeoutSeconds: request.timeoutSeconds
        )
    }

    private func makeDispatchPlan(
        requests: [ToolInvocationRequest],
        plannerMode: ToolDispatchPlannerMode,
        explicitSafety: [ToolCallID: ToolParallelSafety],
        parallelEnabledHint: Bool
    ) async -> (stages: [ToolDispatchPlanStage], diagnostics: ToolDispatchPlanDiagnostics) {
        let toolCalls = requests.map {
            ToolCall(name: $0.toolName, arguments: $0.argumentsPayload, id: $0.toolCallID)
        }
        let plan = await makeDispatchPlan(
            toolCalls: toolCalls,
            plannerMode: plannerMode,
            explicitSafety: explicitSafety,
            parallelEnabledHint: parallelEnabledHint
        )
        return (plan.stages, plan.diagnostics)
    }

    private func makeDispatchPlan(
        toolCalls: [ToolCall],
        plannerMode: ToolDispatchPlannerMode,
        explicitSafety: [ToolCallID: ToolParallelSafety],
        parallelEnabledHint: Bool
    ) async -> (stages: [ToolDispatchPlanStage], diagnostics: ToolDispatchPlanDiagnostics) {
        let metadata = await collectParallelSafetyMetadata(for: toolCalls, explicit: explicitSafety)
        switch plannerMode {
        case .serial:
            let ids = toolCalls.compactMap(\.id)
            let stages = ids.map { ToolDispatchPlanStage(mode: .serial, toolCallIDs: [$0]) }
            return (
                stages,
                ToolDispatchPlanDiagnostics(plannerMode: .serial, reason: "Explicit serial planner mode", stages: stages)
            )
        case .allParallel:
            let ids = toolCalls.compactMap(\.id)
            let mode: ToolDispatchMode = parallelEnabledHint ? .parallel : .serial
            let stages = ids.isEmpty ? [] : [ToolDispatchPlanStage(mode: mode, toolCallIDs: ids)]
            let reason = parallelEnabledHint ? "Explicit allParallel planner mode" : "Parallel disabled; downgraded to serial stage"
            return (
                stages,
                ToolDispatchPlanDiagnostics(plannerMode: .allParallel, reason: reason, stages: stages)
            )
        case .mixedDeterministic:
            var stages: [ToolDispatchPlanStage] = []
            var currentParallel: [String] = []
            func flushParallel() {
                guard !currentParallel.isEmpty else { return }
                stages.append(ToolDispatchPlanStage(mode: .parallel, toolCallIDs: currentParallel))
                currentParallel.removeAll(keepingCapacity: true)
            }
            for call in toolCalls {
                guard let id = call.id else { continue }
                let safety = metadata[id] ?? .unknown
                if parallelEnabledHint && safety == .parallelSafe {
                    currentParallel.append(id)
                } else {
                    flushParallel()
                    stages.append(ToolDispatchPlanStage(mode: .serial, toolCallIDs: [id]))
                }
            }
            flushParallel()
            return (
                stages,
                ToolDispatchPlanDiagnostics(
                    plannerMode: .mixedDeterministic,
                    reason: "Parallel-safe calls grouped; mutating/unknown calls serialized in input order",
                    stages: stages
                )
            )
        }
    }

    private func executeInvocationRequest(
        _ request: ToolInvocationRequest,
        dispatchMode: ToolDispatchMode,
        runID: AgenticLoopID,
        invocationRunID: String,
        source: ToolInvocationSource,
        conversationID: String?,
        batchDiagnostics: ToolDispatchPlanDiagnostics
    ) async -> ToolInvocationOutcome {
        let context = makeInvocationContext(options: .default)
        let call = ToolCall(name: request.toolName, arguments: request.argumentsPayload, id: request.toolCallID)
        if let preDispatch = await evaluatePreDispatchPolicyForRequest(
            request,
            dispatchMode: dispatchMode,
            context: context,
            invocationRunID: invocationRunID,
            source: source
        ) {
            return preDispatch
        }

        publishToolLifecycle(
            eventName: .toolCallStarted,
            toolCallID: request.toolCallID,
            toolName: request.toolName,
            state: .started,
            dispatchMode: dispatchMode,
            conversationID: conversationID ?? request.conversationID,
            runID: invocationRunID,
            source: source.rawValue
        )
        let timeout = request.timeoutSeconds ?? config.toolCallTimeout
        do {
            if let mcpManager = mcpManager, config.mcpEnabled,
               let responses = try await mcpManager.toolCall(call, orchestratorDefaultTimeout: timeout),
               let first = responses.first {
                let result = ToolResult(success: true, content: first.content, metadata: .object([:]), toolCallId: request.toolCallID)
                let meta = ToolInvocationMetadata(
                    conversationID: conversationID ?? request.conversationID,
                    runID: invocationRunID,
                    source: source,
                    callerProvenance: request.callerProvenance,
                    policyDecision: nil,
                    dispatchMode: dispatchMode,
                    dispatchPlan: batchDiagnostics
                )
                publishToolLifecycle(eventName: .toolCallCompleted, toolCallID: request.toolCallID, toolName: request.toolName, state: .completed, dispatchMode: dispatchMode, conversationID: conversationID ?? request.conversationID, runID: invocationRunID, source: source.rawValue)
                return .completed(result: result, metadata: meta)
            }
            if let a2aManager = a2aManager, config.a2aInlineExecutionEnabled,
               let responses = try await a2aManager.agentCall(call, orchestratorDefaultTimeout: timeout),
               let first = responses.first {
                let result = ToolResult(success: true, content: first.content, metadata: .object([:]), toolCallId: request.toolCallID)
                let meta = ToolInvocationMetadata(conversationID: conversationID ?? request.conversationID, runID: invocationRunID, source: source, callerProvenance: request.callerProvenance, policyDecision: nil, dispatchMode: dispatchMode, dispatchPlan: batchDiagnostics)
                publishToolLifecycle(eventName: .toolCallCompleted, toolCallID: request.toolCallID, toolName: request.toolName, state: .completed, dispatchMode: dispatchMode, conversationID: conversationID ?? request.conversationID, runID: invocationRunID, source: source.rawValue)
                return .completed(result: result, metadata: meta)
            }
            if let acpManager = acpManager, config.acpInlineExecutionEnabled,
               let responses = try await acpManager.agentCall(call, orchestratorDefaultTimeout: timeout),
               let first = responses.first {
                let result = ToolResult(success: true, content: first.content, metadata: .object([:]), toolCallId: request.toolCallID)
                let meta = ToolInvocationMetadata(conversationID: conversationID ?? request.conversationID, runID: invocationRunID, source: source, callerProvenance: request.callerProvenance, policyDecision: nil, dispatchMode: dispatchMode, dispatchPlan: batchDiagnostics)
                publishToolLifecycle(eventName: .toolCallCompleted, toolCallID: request.toolCallID, toolName: request.toolName, state: .completed, dispatchMode: dispatchMode, conversationID: conversationID ?? request.conversationID, runID: invocationRunID, source: source.rawValue)
                return .completed(result: result, metadata: meta)
            }
            if let toolManager {
                let outcome = try await withToolCallTimeout(timeout, toolName: request.toolName) {
                    try await toolManager.executeToolOutcome(call)
                }
                let meta = ToolInvocationMetadata(conversationID: conversationID ?? request.conversationID, runID: invocationRunID, source: source, callerProvenance: request.callerProvenance, policyDecision: nil, dispatchMode: dispatchMode, dispatchPlan: batchDiagnostics)
                switch outcome {
                case .completed(let result):
                    publishToolLifecycle(eventName: .toolCallCompleted, toolCallID: request.toolCallID, toolName: request.toolName, state: .completed, dispatchMode: dispatchMode, conversationID: conversationID ?? request.conversationID, runID: invocationRunID, source: source.rawValue)
                    return .completed(result: result, metadata: meta)
                case .pending(let handle):
                    registerPendingHandle(handle, toolName: request.toolName, dispatchMode: dispatchMode, runID: runID)
                    return .pending(handle: handle, metadata: meta)
                }
            }
            let fallback = ToolResult(success: false, content: "", metadata: .object([:]), toolCallId: request.toolCallID, error: "No provider handled tool '\(request.toolName)'")
            let meta = ToolInvocationMetadata(conversationID: conversationID ?? request.conversationID, runID: invocationRunID, source: source, callerProvenance: request.callerProvenance, policyDecision: nil, dispatchMode: dispatchMode, dispatchPlan: batchDiagnostics)
            publishToolLifecycle(eventName: .toolCallFailed, toolCallID: request.toolCallID, toolName: request.toolName, state: .failed(fallback.error), dispatchMode: dispatchMode, conversationID: conversationID ?? request.conversationID, runID: invocationRunID, source: source.rawValue)
            return .completed(result: fallback, metadata: meta)
        } catch {
            let failed = ToolResult(success: false, content: "", metadata: .object([:]), toolCallId: request.toolCallID, error: String(describing: error))
            let meta = ToolInvocationMetadata(conversationID: conversationID ?? request.conversationID, runID: invocationRunID, source: source, callerProvenance: request.callerProvenance, policyDecision: nil, dispatchMode: dispatchMode, dispatchPlan: batchDiagnostics)
            publishToolLifecycle(eventName: .toolCallFailed, toolCallID: request.toolCallID, toolName: request.toolName, state: .failed(failed.error), dispatchMode: dispatchMode, conversationID: conversationID ?? request.conversationID, runID: invocationRunID, source: source.rawValue)
            return .completed(result: failed, metadata: meta)
        }
    }

    private func evaluatePreDispatchPolicyForRequest(
        _ request: ToolInvocationRequest,
        dispatchMode: ToolDispatchMode,
        context: OrchestratorInvocationContext,
        invocationRunID: String,
        source: ToolInvocationSource
    ) async -> ToolInvocationOutcome? {
        guard let evaluator = context.preDispatchPolicyEvaluator else { return nil }
        let descriptor = await findDescriptor(for: request.toolName)
        let decision = await evaluator.decide(.init(request: request, descriptor: descriptor))
        let meta = ToolInvocationMetadata(
            conversationID: request.conversationID,
            runID: invocationRunID,
            source: source,
            callerProvenance: request.callerProvenance,
            policyDecision: decision,
            dispatchMode: dispatchMode,
            dispatchPlan: nil
        )
        switch decision.decision {
        case .allow:
            return nil
        case .deny:
            publishToolLifecycle(eventName: .toolCallFailed, toolCallID: request.toolCallID, toolName: request.toolName, state: .failed(decision.reasonText), dispatchMode: dispatchMode, conversationID: request.conversationID, runID: invocationRunID, source: source.rawValue, reasonCode: decision.reasonCode, reasonText: decision.reasonText, policyDecision: decision.decision.rawValue)
            return .denied(metadata: meta)
        case .requireApproval:
            publishToolLifecycle(eventName: .toolApprovalRequired, toolCallID: request.toolCallID, toolName: request.toolName, state: .pending, dispatchMode: dispatchMode, conversationID: request.conversationID, runID: invocationRunID, source: source.rawValue, reasonCode: decision.reasonCode, reasonText: decision.reasonText, policyDecision: decision.decision.rawValue)
            return .approvalRequired(metadata: meta)
        case .elevated:
            publishToolLifecycle(eventName: .toolElevatedExecuted, toolCallID: request.toolCallID, toolName: request.toolName, state: .started, dispatchMode: dispatchMode, conversationID: request.conversationID, runID: invocationRunID, source: source.rawValue, reasonCode: decision.reasonCode, reasonText: decision.reasonText, policyDecision: decision.decision.rawValue)
            return nil
        }
    }

    private func evaluatePreDispatchPolicy(
        for toolCall: ToolCall,
        context: OrchestratorInvocationContext,
        runID: String,
        source: ToolInvocationSource,
        dispatchMode: ToolDispatchMode
    ) async -> SingleToolExecutionOutcome? {
        guard let evaluator = context.preDispatchPolicyEvaluator else { return nil }
        let request = ToolInvocationRequest(
            toolName: toolCall.name,
            argumentsPayload: toolCall.arguments,
            toolCallID: toolCall.id,
            source: source
        )
        let descriptor = await findDescriptor(for: toolCall.name)
        let decision = await evaluator.decide(.init(request: request, descriptor: descriptor))
        switch decision.decision {
        case .allow:
            return nil
        case .deny:
            publishToolLifecycle(eventName: .toolCallFailed, toolCallID: toolCall.id ?? "unknown", toolName: toolCall.name, state: .failed(decision.reasonText), dispatchMode: dispatchMode, runID: runID, source: source.rawValue, reasonCode: decision.reasonCode, reasonText: decision.reasonText, policyDecision: decision.decision.rawValue)
            let response = LLMResponse.complete(content: "Tool denied by policy: \(decision.reasonText ?? "denied")", toolCallId: toolCall.id)
            return SingleToolExecutionOutcome(responses: [response], pendingAccepted: false)
        case .requireApproval:
            publishToolLifecycle(eventName: .toolApprovalRequired, toolCallID: toolCall.id ?? "unknown", toolName: toolCall.name, state: .pending, dispatchMode: dispatchMode, runID: runID, source: source.rawValue, reasonCode: decision.reasonCode, reasonText: decision.reasonText, policyDecision: decision.decision.rawValue)
            let response = LLMResponse.complete(content: "Tool requires approval before execution.", toolCallId: toolCall.id)
            return SingleToolExecutionOutcome(responses: [response], pendingAccepted: false)
        case .elevated:
            publishToolLifecycle(eventName: .toolElevatedExecuted, toolCallID: toolCall.id ?? "unknown", toolName: toolCall.name, state: .started, dispatchMode: dispatchMode, runID: runID, source: source.rawValue, reasonCode: decision.reasonCode, reasonText: decision.reasonText, policyDecision: decision.decision.rawValue)
            return nil
        }
    }

    private func findDescriptor(for toolName: String) async -> RegisteredToolDescriptor? {
        let descriptors = await allRegisteredTools
        return descriptors.first { $0.definition.name == toolName }
    }

    /// Shuts down MCP local subprocesses and A2A boot processes. Call from normal app termination; it does not run when the process receives `SIGKILL`.
    public func shutdown() async {
        await mcpManager?.shutdown()
        await a2aManager?.shutdown()
        await acpManager?.shutdown()
    }
}

/// Resolved per-`updateConversation` parameters (config + ``OrchestratorInvocationOptions``).
private struct OrchestratorInvocationContext: Sendable {
    let mergedAdditionalParameters: JSON?
    let toolInvocationPolicy: ToolInvocationPolicy
    let assistantPersistenceMode: AssistantPersistenceMode
    let parallelToolDispatchEnabled: Bool
    let dispatchPlannerMode: ToolDispatchPlannerMode?
    let toolParallelSafetyMetadata: [ToolCallID: ToolParallelSafety]
    let preDispatchPolicyEvaluator: (any ToolPreDispatchPolicyEvaluating)?
    let maxAgenticStepsPerUpdate: Int?
    let rejectProseWithoutTools: Bool
    let maxCorrectionRetries: Int
    let correctionMessage: String
    let correctionRole: MessageRole
}

private struct ToolExecutionBatchResult: Sendable {
    let responses: [LLMResponse]
    let pendingCount: Int
    var hasPending: Bool { pendingCount > 0 }
}

private struct SingleToolExecutionOutcome: Sendable {
    let responses: [LLMResponse]
    let pendingAccepted: Bool
}

private struct ActiveRunState: Sendable {
    var assistantPersistenceMode: AssistantPersistenceMode = .immediate
    var cancellationRequested: Bool = false
    var stagedAssistantMessages: [Message] = []
    var assistantCommitted: Bool = false
    var pendingHandleIDs: Set<String> = []
    var terminalOutcome: UpdateConversationOutcome? = nil
}

extension SwiftAgentKitOrchestrator: PendingToolCompletionSink {
    public func onPendingCompletion(_ completion: PendingToolCompletion) async {
        if completedPendingHandleIDs.contains(completion.handleID) {
            logger.debug(
                "Ignoring duplicate pending completion",
                metadata: SwiftAgentKitLogging.metadata(("handleID", .string(completion.handleID)))
            )
            return
        }
        completedPendingHandleIDs.insert(completion.handleID)
        pendingHandlesByID.removeValue(forKey: completion.handleID)
        let runID = pendingHandleRunByID.removeValue(forKey: completion.handleID)
        pendingTimeoutTasks[completion.handleID]?.cancel()
        pendingTimeoutTasks.removeValue(forKey: completion.handleID)
        if let runID, var run = activeRuns[runID] {
            run.pendingHandleIDs.remove(completion.handleID)
            if run.cancellationRequested {
                activeRuns[runID] = run
                logger.info(
                    "Ignoring pending completion for cancelled run",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("runID", .string(String(describing: runID))),
                        ("handleID", .string(completion.handleID))
                    )
                )
                return
            }
            if run.pendingHandleIDs.isEmpty, run.terminalOutcome != nil {
                activeRuns[runID] = nil
            } else {
                activeRuns[runID] = run
            }
        }
        pendingCompletionStreamContinuation?.yield(completion)
        publishToolLifecycle(
            toolCallID: completion.toolCallID,
            toolName: nil,
            state: completion.result.success ? .completed : .failed(completion.result.error),
            dispatchMode: nil
        )
    }
}

private extension SwiftAgentKitOrchestrator {
    func publishToolLifecycle(
        eventName: ToolLifecycleEventName? = nil,
        toolCallID: String,
        toolName: String?,
        state: ToolLifecycleState,
        dispatchMode: ToolDispatchMode?,
        conversationID: String? = nil,
        runID: String? = nil,
        source: String? = nil,
        reasonCode: String? = nil,
        reasonText: String? = nil,
        policyDecision: String? = nil
    ) {
        let resolvedEventName: ToolLifecycleEventName
        if let eventName {
            resolvedEventName = eventName
        } else {
            switch state {
            case .started:
                resolvedEventName = .toolCallStarted
            case .pending:
                resolvedEventName = .toolApprovalRequired
            case .completed:
                resolvedEventName = .toolCallCompleted
            case .failed:
                resolvedEventName = .toolCallFailed
            case .cancelled:
                resolvedEventName = .toolCallFailed
            }
        }
        toolLifecycleEventHub.publish(
            ToolLifecycleEvent(
                eventName: resolvedEventName,
                toolCallID: toolCallID,
                toolName: toolName,
                state: state,
                timestamp: Date(),
                dispatchMode: dispatchMode,
                conversationID: conversationID,
                runID: runID,
                source: source,
                reasonCode: reasonCode,
                reasonText: reasonText,
                policyDecision: policyDecision
            )
        )
    }

    func registerPendingHandle(
        _ handle: PendingToolHandle,
        toolName: String,
        dispatchMode: ToolDispatchMode,
        runID: AgenticLoopID
    ) {
        pendingHandlesByID[handle.handleID] = handle
        pendingHandleRunByID[handle.handleID] = runID
        if var run = activeRuns[runID] {
            run.pendingHandleIDs.insert(handle.handleID)
            activeRuns[runID] = run
        }
        pendingTimeoutTasks[handle.handleID]?.cancel()

        if let timeout = config.pendingToolTimeout, timeout > 0 {
            pendingTimeoutTasks[handle.handleID] = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                } catch {
                    return
                }
                await self?.cancelPendingTool(
                    handleID: handle.handleID,
                    reason: "Pending tool timed out after \(Int(timeout)) seconds"
                )
            }
        }

        publishToolLifecycle(
            toolCallID: handle.toolCallID,
            toolName: toolName,
            state: .pending,
            dispatchMode: dispatchMode
        )
    }

    func isRunCancellationRequested(_ runID: AgenticLoopID) -> Bool {
        activeRuns[runID]?.cancellationRequested ?? false
    }

    @discardableResult
    func finalizeRunOutcome(
        runID: AgenticLoopID,
        terminalState: OrchestratorTerminalState,
        terminalReason: OrchestratorTerminalReason,
        commitAssistantMessages: Bool
    ) async -> UpdateConversationOutcome {
        var run = activeRuns[runID] ?? ActiveRunState()
        if terminalState == .cancelled {
            for handleID in run.pendingHandleIDs {
                await cancelPendingTool(handleID: handleID, reason: "Run cancelled")
            }
        }
        let shouldCommitAssistant = commitAssistantMessages
            && terminalState == .completed
            && !run.cancellationRequested

        if shouldCommitAssistant {
            for message in run.stagedAssistantMessages {
                logger.debug(
                    "Publishing staged assistant message",
                    metadata: metadataForMessage(message)
                )
                messageStreamContinuation?.yield(message)
            }
            run.assistantCommitted = !run.stagedAssistantMessages.isEmpty
        } else {
            run.stagedAssistantMessages.removeAll()
            run.assistantCommitted = false
        }

        let outcome = UpdateConversationOutcome(
            runID: runID,
            terminalState: terminalState,
            terminalReason: terminalReason,
            assistantCommitted: run.assistantCommitted
        )
        run.terminalOutcome = outcome
        lastRunOutcomeByID[runID] = outcome
        if run.pendingHandleIDs.isEmpty {
            activeRuns[runID] = nil
        } else {
            activeRuns[runID] = run
        }
        return outcome
    }
}

// MARK: - Logging helpers

private extension SwiftAgentKitOrchestrator {
    nonisolated func metadataForStreamingContent(_ content: String) -> Logger.Metadata {
        SwiftAgentKitLogging.metadata(
            ("content", .string(content)),
            ("length", .stringConvertible(content.count))
        )
    }

    nonisolated func metadataForStreamingPartial(_ response: LLMResponse) -> Logger.Metadata {
        let fragment = response.streamingFragment ?? .text(response.content)
        switch fragment {
        case .text(let text):
            var meta = SwiftAgentKitLogging.metadata(
                ("partialKind", .string("text")),
                ("length", .stringConvertible(text.count))
            )
            meta["content"] = .string(text)
            return meta
        case .reasoning(let text):
            return SwiftAgentKitLogging.metadata(
                ("partialKind", .string("reasoning")),
                ("length", .stringConvertible(text.count))
            )
        case .toolCall(let id, let name, let argumentsFragment):
            var meta = SwiftAgentKitLogging.metadata(
                ("partialKind", .string("toolCall")),
                ("argumentsFragmentLength", .stringConvertible(argumentsFragment.count))
            )
            if let id { meta["toolCallId"] = .string(id) }
            if let name { meta["toolName"] = .string(name) }
            return meta
        case .toolCallStarted(let id, let name, let contentIndex):
            var meta = SwiftAgentKitLogging.metadata(
                ("partialKind", .string("toolCallStarted"))
            )
            if let id { meta["toolCallId"] = .string(id) }
            if let name { meta["toolName"] = .string(name) }
            if let contentIndex { meta["contentIndex"] = .stringConvertible(contentIndex) }
            return meta
        case .toolCallCompleted(let id, let name, let arguments):
            var meta = SwiftAgentKitLogging.metadata(
                ("partialKind", .string("toolCallCompleted")),
                ("argumentsLength", .stringConvertible(arguments.count))
            )
            if let id { meta["toolCallId"] = .string(id) }
            if let name { meta["toolName"] = .string(name) }
            return meta
        }
    }

    nonisolated func metadataForMessage(_ message: Message) -> Logger.Metadata {
        var metadata = SwiftAgentKitLogging.metadata(
            ("role", .string(message.role.rawValue)),
            ("content", .string(message.content)),
            ("hasToolCalls", .string(message.toolCalls.isEmpty ? "false" : "true"))
        )
        if !message.toolCalls.isEmpty {
            metadata["toolCallCount"] = .stringConvertible(message.toolCalls.count)
        }
        return metadata
    }
    
    nonisolated func metadataForToolCall(_ toolCall: ToolCall, provider: String) -> Logger.Metadata {
        var metadata = SwiftAgentKitLogging.metadata(
            ("provider", .string(provider)),
            ("toolName", .string(toolCall.name)),
            ("arguments", .string(stringifyJSON(toolCall.arguments)))
        )
        if let instructions = toolCall.instructions, !instructions.isEmpty {
            metadata["instructions"] = .string(instructions)
        }
        if let identifier = toolCall.id {
            metadata["toolCallId"] = .string(identifier)
        }
        return metadata
    }
    
    nonisolated func metadataForResponses(_ responses: [LLMResponse], provider: String) -> Logger.Metadata {
        var metadata = SwiftAgentKitLogging.metadata(
            ("provider", .string(provider)),
            ("responseCount", .stringConvertible(responses.count))
        )
        if !responses.isEmpty {
            metadata["contents"] = .array(responses.map { .string($0.content) })
        }
        return metadata
    }
    
    nonisolated func stringifyJSON(_ json: JSON) -> String {
        let literal = json.literalValue
        if JSONSerialization.isValidJSONObject(literal),
           let data = try? JSONSerialization.data(withJSONObject: literal, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: json)
    }
}
