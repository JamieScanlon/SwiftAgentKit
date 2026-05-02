import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitMCP
import SwiftAgentKitAdapters
import EasyJSON

/// Configuration for the SwiftAgentKitOrchestrator
public struct OrchestratorConfig: Sendable {
    /// Whether streaming responses are enabled
    public let streamingEnabled: Bool
    /// Whether MCP (Model Context Protocol) tool usage is enabled
    public let mcpEnabled: Bool
    /// Whether A2A (Agent-to-Agent) communication is enabled
    public let a2aEnabled: Bool
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
    /// How tool calls are chosen when tools are passed to the orchestrator (forwarded in ``LLMRequestConfig``).
    public let toolInvocationPolicy: ToolInvocationPolicy
    /// When true and tools are non-empty, reject assistant turns with no tool calls and retry with a correction message (see correction fields).
    public let rejectAssistantTurnWithNoToolCallsWhenToolsAvailable: Bool
    /// Maximum correction messages appended after a rejected prose turn; `0` disables retry (throws if rejected).
    public let maxCorrectionRetries: Int
    public let correctionMessage: String
    public let correctionRole: MessageRole
    
    public init(
        streamingEnabled: Bool = false,
        mcpEnabled: Bool = false,
        a2aEnabled: Bool = false,
        mcpConnectionTimeout: TimeInterval = 30.0,
        toolCallTimeout: TimeInterval = 300.0,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        additionalParameters: JSON? = nil,
        maxAgenticStepsPerUpdate: Int? = nil,
        toolInvocationPolicy: ToolInvocationPolicy = .automatic,
        rejectAssistantTurnWithNoToolCallsWhenToolsAvailable: Bool = false,
        maxCorrectionRetries: Int = 0,
        correctionMessage: String = "You must call a tool or indicate you are done.",
        correctionRole: MessageRole = .user
    ) {
        self.streamingEnabled = streamingEnabled
        self.mcpEnabled = mcpEnabled
        self.a2aEnabled = a2aEnabled
        self.mcpConnectionTimeout = mcpConnectionTimeout
        self.toolCallTimeout = toolCallTimeout
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.additionalParameters = additionalParameters
        self.maxAgenticStepsPerUpdate = maxAgenticStepsPerUpdate
        self.toolInvocationPolicy = toolInvocationPolicy
        self.rejectAssistantTurnWithNoToolCallsWhenToolsAvailable = rejectAssistantTurnWithNoToolCallsWhenToolsAvailable
        self.maxCorrectionRetries = maxCorrectionRetries
        self.correctionMessage = correctionMessage
        self.correctionRole = correctionRole
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
    /// Optional ToolManager for executing generic function tools (non-MCP, non-A2A)
    public let toolManager: ToolManager?

    private let agenticLoopStateHub: AgenticLoopStateHub
    private let orchestrationObservation: OrchestrationObservationCoordinator
    
    /// All available tools from MCP and A2A managers
    public var allAvailableTools: [ToolDefinition] {
        get async {
            var allTools: [ToolDefinition] = []
            
            // Get tools from MCP manager if enabled
            if let mcpManager = mcpManager, config.mcpEnabled {
                allTools.append(contentsOf: await mcpManager.availableTools())
            }
            
            // Get tools from A2A manager if enabled
            if let a2aManager = a2aManager, config.a2aEnabled {
                allTools.append(contentsOf: await a2aManager.availableTools())
            }
            
            // Get tools from generic ToolManager if configured
            if let toolManager = toolManager {
                allTools.append(contentsOf: await toolManager.allToolsAsync())
            }
            
            return allTools
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
    ///   - a2aManager: Pre-built A2A manager; if nil and `config.a2aEnabled` is true, one is created.
    ///   - toolManager: Optional ToolManager for generic function tools.
    ///   - logger: Optional logger; a default is created if nil.
    public init(
        llm: LLMProtocol,
        config: OrchestratorConfig = OrchestratorConfig(),
        mcpManager: MCPManager? = nil,
        mcpOAuthHandler: MCPOAuthHandler? = nil,
        a2aManager: A2AManager? = nil,
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
                ("a2aEnabled", .string(config.a2aEnabled ? "true" : "false"))
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
        } else if config.a2aEnabled {
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
        
        self.toolManager = toolManager
        let agenticHub = AgenticLoopStateHub()
        self.agenticLoopStateHub = agenticHub
        self.orchestrationObservation = OrchestrationObservationCoordinator(
            llm: llm,
            agenticLoopStateHub: agenticHub
        )
    }
    
    /// Process a conversation thread and publish message updates to the message stream
    /// - Parameter messages: Array of messages representing the conversation thread
    /// - Parameter availableTools: Array of available tools that can be used during conversation processing
    public func updateConversation(_ messages: [Message], availableTools: [ToolDefinition] = []) async throws {
        try await updateConversation(messages, availableTools: availableTools, options: .default)
    }

    /// Process a conversation with per-invocation options layered on ``OrchestratorConfig``.
    ///
    /// Each inner LLM call uses a fresh ``LLMRequestConfig`` built from the orchestrator config merged with ``OrchestratorInvocationOptions``
    /// (additional parameters and metadata apply to every step in this `updateConversation` tree).
    public func updateConversation(_ messages: [Message], availableTools: [ToolDefinition], options: OrchestratorInvocationOptions) async throws {
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
        try await updateConversationWithAgenticLoop(messages, availableTools: availableTools, iteration: 1, agenticLoopId: nil, context: context)
    }

    private func makeInvocationContext(options: OrchestratorInvocationOptions) -> OrchestratorInvocationContext {
        var merged = mergeJSONObjectParameters(config.additionalParameters, options.additionalParameters)
        if let meta = options.systemPromptMetadata, !meta.isEmpty {
            let metaJSON = JSON.object(Dictionary(uniqueKeysWithValues: meta.map { ($0.key, JSON.string($0.value)) }))
            merged = mergeJSONObjectParameters(merged, metaJSON)
        }
        let policy = options.toolInvocationPolicy ?? config.toolInvocationPolicy
        let maxSteps = options.maxAgenticStepsPerUpdate ?? config.maxAgenticStepsPerUpdate
        let reject = options.rejectAssistantTurnWithNoToolCallsWhenToolsAvailable ?? config.rejectAssistantTurnWithNoToolCallsWhenToolsAvailable
        let maxCorr = options.maxCorrectionRetries ?? config.maxCorrectionRetries
        let msg = options.correctionMessage ?? config.correctionMessage
        let role = options.correctionRole ?? config.correctionRole
        return OrchestratorInvocationContext(
            mergedAdditionalParameters: merged,
            toolInvocationPolicy: policy,
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
        let isRootEntry = agenticLoopId == nil
        if isRootEntry {
            agenticLoopStateHub.publish(loopId, .started)
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
            publishMessage(responseMessage)

            if response.hasToolCalls {
                transitionLLMState(to: .idle(.ready))
                agenticLoopStateHub.publish(loopId, .waitingForToolExecution)
                agenticLoopStateHub.publish(loopId, .executingTools)
                logger.info(
                    "Response contains tool calls",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("toolCallCount", .stringConvertible(toolCallsWithIds.count))
                    )
                )
                let toolResponses = await executeToolCalls(toolCallsWithIds)

                guard !toolResponses.isEmpty else {
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

                logger.info(
                    "Sending tool responses back to LLM",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("responseCount", .stringConvertible(toolResponses.count))
                    )
                )
                let toolResponseMessages = toolResponses.map { messageFromToolResponse($0) }
                updatedMessages.append(contentsOf: toolResponseMessages)
                toolResponseMessages.forEach { publishMessage($0) }

                agenticLoopStateHub.publish(loopId, .betweenIterations)
                try await LLMQueuePriority.$current.withValue(.continuation) {
                    try await updateConversationWithAgenticLoop(updatedMessages, availableTools: availableTools, iteration: iteration + 1, agenticLoopId: loopId, context: context)
                }
            } else {
                agenticLoopStateHub.publish(loopId, .completed)
                transitionLLMState(to: .idle(.completed))
                transitionLLMState(to: .idle(.ready))
            }
        } catch {
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
    
    /// Publish a message to the stream
    private func publishMessage(_ message: Message) {
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
    
    /// Execute tool calls using available managers
    /// - Parameter toolCalls: Array of tool calls to execute
    /// - Returns: Array of tool response messages to send back to the LLM
    private func executeToolCalls(_ toolCalls: [ToolCall]) async -> [LLMResponse] {
        var aggregatedResponses: [LLMResponse] = []
        for toolCall in toolCalls {
            logger.info(
                "Executing tool call",
                metadata: metadataForToolCall(toolCall, provider: "orchestrator")
            )
            var callResponses: [LLMResponse] = []
            var abortedWithError: LLMResponse?
            
            // Try MCP manager first
            if let mcpManager = mcpManager, config.mcpEnabled {
                logger.debug(
                    "Dispatching MCP tool call",
                    metadata: metadataForToolCall(toolCall, provider: "mcp")
                )
                do {
                    let mcpResponses = try await mcpManager.toolCall(toolCall, orchestratorDefaultTimeout: config.toolCallTimeout)
                    if let mcpResponses = mcpResponses {
                        if mcpResponses.isEmpty {
                            logger.debug(
                                "MCP tool call returned no responses",
                                metadata: metadataForToolCall(toolCall, provider: "mcp")
                            )
                        } else {
                            logger.debug(
                                "MCP tool call responses received",
                                metadata: metadataForResponses(mcpResponses, provider: "mcp")
                            )
                            let responsesWithId = mcpResponses.map { response in
                                LLMResponse(
                                    content: response.content,
                                    toolCalls: response.toolCalls,
                                    metadata: response.metadata,
                                    isComplete: response.isComplete,
                                    toolCallId: toolCall.id
                                )
                            }
                            callResponses.append(contentsOf: responsesWithId)
                        }
                    } else {
                        logger.debug(
                            "MCP tool call returned nil",
                            metadata: metadataForToolCall(toolCall, provider: "mcp")
                        )
                    }
                } catch {
                    logger.error(
                        "MCP tool call failed",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("toolName", .string(toolCall.name)),
                            ("error", .string(String(describing: error)))
                        )
                    )
                    abortedWithError = llmResponseFromToolExecutionError(error, toolCallId: toolCall.id)
                }
            }
            if let err = abortedWithError {
                aggregatedResponses.append(err)
                continue
            }
            
            // Try A2A manager
            if let a2aManager = a2aManager, config.a2aEnabled {
                logger.debug(
                    "Dispatching A2A agent call",
                    metadata: metadataForToolCall(toolCall, provider: "a2a")
                )
                do {
                    let a2aResponses = try await a2aManager.agentCall(toolCall, orchestratorDefaultTimeout: config.toolCallTimeout)
                    if let a2aResponses = a2aResponses {
                        if a2aResponses.isEmpty {
                            logger.debug(
                                "A2A agent call returned no responses",
                                metadata: metadataForToolCall(toolCall, provider: "a2a")
                            )
                        } else {
                            logger.debug(
                                "A2A agent call responses received",
                                metadata: metadataForResponses(a2aResponses, provider: "a2a")
                            )
                            let responsesWithId = a2aResponses.map { response in
                                LLMResponse(
                                    content: response.content,
                                    toolCalls: response.toolCalls,
                                    metadata: response.metadata,
                                    isComplete: response.isComplete,
                                    toolCallId: toolCall.id
                                )
                            }
                            callResponses.append(contentsOf: responsesWithId)
                        }
                    } else {
                        logger.debug(
                            "A2A agent call returned nil",
                            metadata: metadataForToolCall(toolCall, provider: "a2a")
                        )
                    }
                } catch {
                    logger.error(
                        "A2A agent call failed",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("toolName", .string(toolCall.name)),
                            ("error", .string(String(describing: error)))
                        )
                    )
                    abortedWithError = llmResponseFromToolExecutionError(error, toolCallId: toolCall.id)
                }
            }
            if let err = abortedWithError {
                aggregatedResponses.append(err)
                continue
            }
            
            // Try generic ToolManager if MCP and A2A didn't handle the tool
            if callResponses.isEmpty, let toolManager = toolManager {
                logger.debug(
                    "Dispatching to ToolManager",
                    metadata: metadataForToolCall(toolCall, provider: "toolManager")
                )
                do {
                    let result = try await withToolCallTimeout(config.toolCallTimeout, toolName: toolCall.name) {
                        try await toolManager.executeTool(toolCall)
                    }
                    let response = llmResponseFromToolResult(result, toolCallId: toolCall.id)
                    if result.success {
                        logger.debug(
                            "ToolManager executed tool successfully",
                            metadata: metadataForToolCall(toolCall, provider: "toolManager")
                        )
                    } else {
                        logger.warning(
                            "ToolManager reported tool execution failure",
                            metadata: SwiftAgentKitLogging.metadata(
                                ("toolName", .string(toolCall.name)),
                                ("error", .string(result.error ?? "unknown"))
                            )
                        )
                    }
                    callResponses.append(response)
                } catch {
                    logger.error(
                        "ToolManager tool execution failed",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("toolName", .string(toolCall.name)),
                            ("error", .string(String(describing: error)))
                        )
                    )
                    callResponses.append(llmResponseFromToolExecutionError(error, toolCallId: toolCall.id))
                }
            }
            
            var successMetadata = metadataForToolCall(toolCall, provider: "orchestrator")
            successMetadata["responseCount"] = .stringConvertible(callResponses.count)
            logger.info(
                "Tool call finished",
                metadata: successMetadata
            )
            aggregatedResponses.append(contentsOf: callResponses)
        }
        return aggregatedResponses
    }

    /// Shuts down MCP local subprocesses and A2A boot processes. Call from normal app termination; it does not run when the process receives `SIGKILL`.
    public func shutdown() async {
        await mcpManager?.shutdown()
        await a2aManager?.shutdown()
    }
}

/// Resolved per-`updateConversation` parameters (config + ``OrchestratorInvocationOptions``).
private struct OrchestratorInvocationContext: Sendable {
    let mergedAdditionalParameters: JSON?
    let toolInvocationPolicy: ToolInvocationPolicy
    let maxAgenticStepsPerUpdate: Int?
    let rejectProseWithoutTools: Bool
    let maxCorrectionRetries: Int
    let correctionMessage: String
    let correctionRole: MessageRole
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
