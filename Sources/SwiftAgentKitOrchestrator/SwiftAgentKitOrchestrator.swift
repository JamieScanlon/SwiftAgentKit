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
    /// Maximum number of tokens to generate (passed to LLM requests)
    public let maxTokens: Int?
    /// Temperature for response randomness, 0.0 to 2.0 (passed to LLM requests)
    public let temperature: Double?
    /// Top-p sampling parameter (passed to LLM requests)
    public let topP: Double?
    /// Additional model-specific parameters (passed to LLM requests)
    public let additionalParameters: JSON?
    
    public init(
        streamingEnabled: Bool = false,
        mcpEnabled: Bool = false,
        a2aEnabled: Bool = false,
        mcpConnectionTimeout: TimeInterval = 30.0,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        additionalParameters: JSON? = nil
    ) {
        self.streamingEnabled = streamingEnabled
        self.mcpEnabled = mcpEnabled
        self.a2aEnabled = a2aEnabled
        self.mcpConnectionTimeout = mcpConnectionTimeout
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.additionalParameters = additionalParameters
    }
}

/// SwiftAgentKitOrchestrator provides building blocks for creating LLM orchestrators
/// that can use tools through MCP, communicate with other agents through A2A,
/// and execute generic function tools via a configurable ToolManager.
public actor SwiftAgentKitOrchestrator {
    public let logger: Logger
    public let llm: LLMProtocol
    public let config: OrchestratorConfig
    public let mcpManager: MCPManager?
    public let a2aManager: A2AManager?
    /// Optional ToolManager for executing generic function tools (non-MCP, non-A2A)
    public let toolManager: ToolManager?
    
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
    
    /// Stream of partial content updates (streaming text chunks) from the orchestrator
    public var partialContentStream: AsyncStream<String> {
        get async {
            return currentPartialContentStream ?? createPartialContentStream()
        }
    }
    
    public init(
        llm: LLMProtocol,
        config: OrchestratorConfig = OrchestratorConfig(),
        mcpManager: MCPManager? = nil,
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
                )
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
    }
    
    /// Process a conversation thread and publish message updates to the message stream
    /// - Parameter messages: Array of messages representing the conversation thread
    /// - Parameter availableTools: Array of available tools that can be used during conversation processing
    public func updateConversation(_ messages: [Message], availableTools: [ToolDefinition] = []) async throws {
        
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
        
        // Create a copy of the conversation history
        var updatedMessages = messages
        
        // Determine if we should use streaming based on configuration
        let requestConfig = LLMRequestConfig(
            maxTokens: config.maxTokens,
            temperature: config.temperature,
            topP: config.topP,
            stream: config.streamingEnabled,
            availableTools: availableTools,
            additionalParameters: config.additionalParameters
        )
                
        if config.streamingEnabled {
            // Handle streaming response
            let stream = llm.stream(messages, config: requestConfig)
            
            for try await result in stream {
                switch result {
                case .stream(let response):
                    logger.debug(
                        "Received streaming chunk",
                        metadata: metadataForStreamingContent(response.content)
                    )
                    // Publish the streaming chunk to partial content stream
                    publishPartialContent(response.content)
                    
                case .complete(let response):
                    logger.info(
                        "Received complete streaming response",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("contentLength", .stringConvertible(response.content.count)),
                            ("hasToolCalls", .string(response.hasToolCalls ? "true" : "false"))
                        )
                    )

                    // Ensure all tool calls have IDs (some models don't provide them)
                    let toolCallsWithIds = response.hasToolCalls ? ensureToolCallsHaveIds(response.toolCalls) : response.toolCalls
                    
                    // Convert LLMResponse to Message for conversation history
                    let responseMessage = Message(id: UUID(), role: .assistant, content: response.content, toolCalls: toolCallsWithIds)
                    updatedMessages.append(responseMessage)
                    // Publish the message
                    publishMessage(responseMessage)
                    
                    if response.hasToolCalls {
                        
                        // Execute tool calls
                        logger.info(
                            "Response contains tool calls",
                            metadata: SwiftAgentKitLogging.metadata(
                                ("toolCallCount", .stringConvertible(toolCallsWithIds.count))
                            )
                        )
                        let toolResponses = await executeToolCalls(toolCallsWithIds)
                        
                        guard !toolResponses.isEmpty else { continue }
                        
                        // Create tool response messages with proper toolCallId mapping
                        // TODO: We need to show the full tool call to the user so we should publish summarized tool call messages. Something like "Calling tool \(name)..."
                        logger.info(
                            "Sending tool responses back to LLM",
                            metadata: SwiftAgentKitLogging.metadata(
                                ("responseCount", .stringConvertible(toolResponses.count))
                            )
                        )
                        let toolResponseMessages = toolResponses.map { messageFromToolResponse($0) }
                        updatedMessages.append(contentsOf: toolResponseMessages)
                        toolResponseMessages.forEach { publishMessage($0) }
                        
                        // Recurse here with the updated message history
                        try await updateConversation(updatedMessages, availableTools: availableTools)
                    }
                    
                    // Finish and nil out the partial content stream continuation since streaming is complete
                    partialContentStreamContinuation?.finish()
                    partialContentStreamContinuation = nil
                    currentPartialContentStream = nil
                }
            }
        } else {
            // Handle synchronous response
            let response = try await llm.send(messages, config: requestConfig)
            
            logger.info(
                "Received complete response",
                metadata: SwiftAgentKitLogging.metadata(
                    ("contentLength", .stringConvertible(response.content.count)),
                    ("hasToolCalls", .string(response.hasToolCalls ? "true" : "false"))
                )
            )
            // Ensure all tool calls have IDs (some models don't provide them)
            let toolCallsWithIds = response.hasToolCalls ? ensureToolCallsHaveIds(response.toolCalls) : response.toolCalls
            
            // Convert LLMResponse to Message for conversation history
            let responseMessage = Message(id: UUID(), role: .assistant, content: response.content, toolCalls: toolCallsWithIds)
            updatedMessages.append(responseMessage)
            // Publish the final conversation history
            publishMessage(responseMessage)
            
            if response.hasToolCalls {
                
                // Execute tool calls
                logger.info(
                    "Response contains tool calls",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("toolCallCount", .stringConvertible(toolCallsWithIds.count))
                    )
                )
                let toolResponses = await executeToolCalls(toolCallsWithIds)
                
                guard !toolResponses.isEmpty else { return }
                
                // Create tool response messages with proper toolCallId mapping
                // TODO: We need to show the full tool call to the user so we should publish summarized tool call messages. Something like "Calling tool \(name)..."
                logger.info(
                    "Sending tool responses back to LLM",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("responseCount", .stringConvertible(toolResponses.count))
                    )
                )
                let toolResponseMessages = toolResponses.map { messageFromToolResponse($0) }
                updatedMessages.append(contentsOf: toolResponseMessages)
                toolResponseMessages.forEach { publishMessage($0) }
                
                // Recurse here with the updated message history
                try await updateConversation(updatedMessages, availableTools: availableTools)
            }
        }
    }
    
    /// Finish the message stream
    public func endMessageStream() {
        messageStreamContinuation?.finish()
        messageStreamContinuation = nil
        currentMessageStream = nil
        partialContentStreamContinuation?.finish()
        partialContentStreamContinuation = nil
        currentPartialContentStream = nil
    }
    
    // MARK: - Private
    
    /// Current message stream
    private var currentMessageStream: AsyncStream<Message>?
    
    /// Current partial content stream
    private var currentPartialContentStream: AsyncStream<String>?
    
    /// Internal stream continuation for publishing messages
    private var messageStreamContinuation: AsyncStream<Message>.Continuation?
    
    /// Internal stream continuation for publishing partial content
    private var partialContentStreamContinuation: AsyncStream<String>.Continuation?
    
    /// Publish a message to the stream
    private func publishMessage(_ message: Message) {
        logger.debug(
            "Publishing message",
            metadata: metadataForMessage(message)
        )
        messageStreamContinuation?.yield(message)
    }
    
    /// Publish partial content to the partial content stream
    private func publishPartialContent(_ content: String) {
        logger.debug(
            "Publishing partial content chunk",
            metadata: metadataForStreamingContent(content)
        )
        partialContentStreamContinuation?.yield(content)
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
    
    /// Create a partial content stream if one does not exist
    private func createPartialContentStream() -> AsyncStream<String> {
        let stream = AsyncStream { continuation in
            self.partialContentStreamContinuation = continuation
        }
        self.currentPartialContentStream = stream
        logger.debug("Created partial content stream")
        return stream
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
        let content = result.success ? result.content : (result.error ?? "Tool execution failed")
        let metadata: LLMMetadata? = {
            guard case .object(let dict) = result.metadata, !dict.isEmpty else { return nil }
            return LLMMetadata(modelMetadata: result.metadata)
        }()
        return LLMResponse.complete(content: content, metadata: metadata, toolCallId: toolCallId)
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
            do {
                var callResponses: [LLMResponse] = []
                // Try MCP manager first
                if let mcpManager = mcpManager, config.mcpEnabled {
                    logger.debug(
                        "Dispatching MCP tool call",
                        metadata: metadataForToolCall(toolCall, provider: "mcp")
                    )
                    if let mcpResponses = try await mcpManager.toolCall(toolCall) {
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
                            // Set toolCallId on each response
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
                }
                // Try A2A manager
                if let a2aManager = a2aManager, config.a2aEnabled {
                    logger.debug(
                        "Dispatching A2A agent call",
                        metadata: metadataForToolCall(toolCall, provider: "a2a")
                    )
                    if let a2aResponses = try await a2aManager.agentCall(toolCall) {
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
                            // Set toolCallId on each response
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
                }
                // Try generic ToolManager if MCP and A2A didn't handle the tool
                if callResponses.isEmpty, let toolManager = toolManager {
                    logger.debug(
                        "Dispatching to ToolManager",
                        metadata: metadataForToolCall(toolCall, provider: "toolManager")
                    )
                    do {
                        let result = try await toolManager.executeTool(toolCall)
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
                        callResponses.append(LLMResponse.complete(
                            content: "Tool execution failed: \(error)",
                            toolCallId: toolCall.id
                        ))
                    }
                }
                
                var successMetadata = metadataForToolCall(toolCall, provider: "orchestrator")
                successMetadata["responseCount"] = .stringConvertible(callResponses.count)
                logger.info(
                    "Tool call executed successfully",
                    metadata: successMetadata
                )
                aggregatedResponses.append(contentsOf: callResponses)
            } catch {
                logger.error(
                    "Tool call failed",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("toolName", .string(toolCall.name)),
                        ("error", .string(String(describing: error)))
                    )
                )
            }
        }
        return aggregatedResponses
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
