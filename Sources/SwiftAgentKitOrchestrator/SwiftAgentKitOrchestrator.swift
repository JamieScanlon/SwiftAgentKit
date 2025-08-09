import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitMCP
import SwiftAgentKitAdapters

/// Configuration for the SwiftAgentKitOrchestrator
public struct OrchestratorConfig: Sendable {
    /// Whether streaming responses are enabled
    public let streamingEnabled: Bool
    /// Whether MCP (Model Context Protocol) tool usage is enabled
    public let mcpEnabled: Bool
    /// Whether A2A (Agent-to-Agent) communication is enabled
    public let a2aEnabled: Bool
    
    public init(
        streamingEnabled: Bool = false,
        mcpEnabled: Bool = false,
        a2aEnabled: Bool = false
    ) {
        self.streamingEnabled = streamingEnabled
        self.mcpEnabled = mcpEnabled
        self.a2aEnabled = a2aEnabled
    }
}

/// SwiftAgentKitOrchestrator provides building blocks for creating LLM orchestrators
/// that can use tools through MCP and communicate with other agents through A2A.
public actor SwiftAgentKitOrchestrator {
    public let logger: Logger
    public let llm: LLMProtocol
    public let config: OrchestratorConfig
    public let mcpManager: MCPManager?
    public let a2aManager: A2AManager?
    
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
        logger: Logger? = nil
    ) {
        self.llm = llm
        self.config = config
        self.mcpManager = mcpManager
        self.a2aManager = a2aManager
        self.logger = logger ?? Logger(label: "SwiftAgentKitOrchestrator")
    }
    
    /// Process a conversation thread and publish message updates to the message stream
    /// - Parameter messages: Array of messages representing the conversation thread
    /// - Parameter availableTools: Array of available tools that can be used during conversation processing
    public func updateConversation(_ messages: [Message], availableTools: [ToolDefinition] = []) async throws {
        
        logger.info("Processing conversation with \(messages.count) messages")
        if !availableTools.isEmpty {
            logger.info("Available tools: \(availableTools.map { $0.name }.joined(separator: ", "))")
        }
        
        // Create a copy of the conversation history
        var updatedMessages = messages
        
        // Determine if we should use streaming based on configuration
        let requestConfig = LLMRequestConfig(stream: config.streamingEnabled, availableTools: availableTools)
                
        if config.streamingEnabled {
            // Handle streaming response
            let stream = llm.stream(messages, config: requestConfig)
            
            for try await result in stream {
                switch result {
                case .stream(let response):
                    logger.info("Received streaming chunk")
                    // Publish the streaming chunk to partial content stream
                    publishPartialContent(response.content)
                    
                case .complete(let response):
                    logger.info("Received complete streaming response")
                    // Convert LLMResponse to Message for conversation history
                    let responseMessage = Message(id: UUID(), role: .assistant, content: response.content)
                    updatedMessages.append(responseMessage)
                    // Publish the message
                    publishMessage(responseMessage)
                    
                    // Finish and nil out the partial content stream continuation since streaming is complete
                    partialContentStreamContinuation?.finish()
                    partialContentStreamContinuation = nil
                    currentPartialContentStream = nil
                    
                    if response.hasToolCalls {
                        
                        // Execute tool calls
                        logger.info("Response contains \(response.toolCalls.count) tool calls")
                        let toolResponses = await executeToolCalls(response.toolCalls)
                        
                        guard !toolResponses.isEmpty else { continue }
                        
                        // Pubilsh the tool calll Messages
                        // TODO: We need to show the full tool call to the user so we should publish summarized tool call messages. Something like "Calling tool \(name)..."
                        logger.info("Sending \(toolResponses.count) tool responses back to LLM")
                        let toolResponseMessages = toolResponses.map({ Message(id: UUID(), role: .tool, content: $0.content) })
                        updatedMessages.append(contentsOf: toolResponseMessages)
                        toolResponseMessages.forEach { publishMessage($0) }
                        
                        // Recurse here with the updated message history
                        try await updateConversation(updatedMessages, availableTools: availableTools)
                    }
                }
            }
        } else {
            // Handle synchronous response
            let response = try await llm.send(messages, config: requestConfig)
            
            logger.info("Received complete response")
            // Convert LLMResponse to Message for conversation history
            let responseMessage = Message(id: UUID(), role: .assistant, content: response.content)
            updatedMessages.append(responseMessage)
            // Publish the final conversation history
            publishMessage(responseMessage)
            
            if response.hasToolCalls {
                
                // Execute tool calls
                logger.info("Response contains \(response.toolCalls.count) tool calls")
                let toolResponses = await executeToolCalls(response.toolCalls)
                
                guard !toolResponses.isEmpty else { return }
                
                // Pubilsh the tool calll Messages
                // TODO: We need to show the full tool call to the user so we should publish summarized tool call messages. Something like "Calling tool \(name)..."
                logger.info("Sending \(toolResponses.count) tool responses back to LLM")
                let toolResponseMessages = toolResponses.map({ Message(id: UUID(), role: .tool, content: $0.content) })
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
        messageStreamContinuation?.yield(message)
    }
    
    /// Publish partial content to the partial content stream
    private func publishPartialContent(_ content: String) {
        partialContentStreamContinuation?.yield(content)
    }
    
    /// Create a message stream if one does not exist
    private func createMessageStream() -> AsyncStream<Message> {
        let stream = AsyncStream { continuation in
            self.messageStreamContinuation = continuation
        }
        self.currentMessageStream = stream
        return stream
    }
    
    /// Create a partial content stream if one does not exist
    private func createPartialContentStream() -> AsyncStream<String> {
        let stream = AsyncStream { continuation in
            self.partialContentStreamContinuation = continuation
        }
        self.currentPartialContentStream = stream
        return stream
    }
    
    /// Execute tool calls using available managers
    /// - Parameter toolCalls: Array of tool calls to execute
    /// - Returns: Array of tool response messages to send back to the LLM
    private func executeToolCalls(_ toolCalls: [ToolCall]) async -> [LLMResponse] {
        var responses: [LLMResponse] = []
        for toolCall in toolCalls {
            logger.info("Executing tool call: \(toolCall.name)")
            do {
                responses = try await {
                    var temp = [LLMResponse]()
                    // Try MCP manager first
                    if let mcpManager = mcpManager, config.mcpEnabled {
                        temp.append(contentsOf: try await mcpManager.toolCall(toolCall) ?? [])
                    }
                    // Try A2A manager
                    if let a2aManager = a2aManager, config.a2aEnabled {
                        temp.append(contentsOf: try await a2aManager.agentCall(toolCall) ?? [])
                    }
                    logger.info("Tool call executed successfully, got \(temp.count) responses")
                    return temp
                }()
            } catch {
                logger.error("Tool call failed: \(error.localizedDescription)")
                continue
            }
        }
        return responses
    }
}
