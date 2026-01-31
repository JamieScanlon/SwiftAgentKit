//
//  LLMProtocolAdapter.swift
//  SwiftAgentKitAdapters
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitA2A
import EasyJSON

/// A generic AgentAdapter that wraps any LLMProtocol implementation
/// This adapter provides a bridge between the A2A protocol and any LLM
/// that implements the LLMProtocol interface.
public struct LLMProtocolAdapter: ToolAwareAdapter {
    
    // MARK: - Configuration
    
    /// Callback function type for updating the system prompt before sending a message.
    /// - Parameters:
    ///   - params: The message send parameters containing the message being sent
    ///   - currentPrompt: The current system prompt (may be nil)
    /// - Returns: An updated system prompt (or nil to remove the system prompt)
    public typealias SystemPromptUpdateCallback = @Sendable (MessageSendParams, DynamicPrompt?) -> DynamicPrompt?
    
    public struct Configuration: Sendable {
        public let model: String
        public let maxTokens: Int?
        public let temperature: Double?
        public let topP: Double?
        public let systemPrompt: DynamicPrompt?
        public let additionalParameters: JSON?
        
        /// Optional callback to update the system prompt before sending a message.
        /// This callback is called right before a message is sent to the LLM,
        /// allowing you to dynamically update the system prompt based on the message content.
        public let systemPromptUpdateCallback: SystemPromptUpdateCallback?
        
        // MARK: - Agentic Loop Configuration
        public let maxAgenticIterations: Int
        
        // MARK: - Agent Configuration
        public let agentName: String
        public let agentDescription: String
        public let cardCapabilities: AgentCard.AgentCapabilities
        public let skills: [AgentCard.AgentSkill]
        public let defaultInputModes: [String]
        public let defaultOutputModes: [String]
        
        public init(
            model: String,
            maxTokens: Int? = nil,
            temperature: Double? = nil,
            topP: Double? = nil,
            systemPrompt: DynamicPrompt? = nil,
            additionalParameters: JSON? = nil,
            maxAgenticIterations: Int = 10,
            systemPromptUpdateCallback: SystemPromptUpdateCallback? = nil,
            agentName: String? = nil,
            agentDescription: String? = nil,
            cardCapabilities: AgentCard.AgentCapabilities? = nil,
            skills: [AgentCard.AgentSkill]? = nil,
            defaultInputModes: [String]? = nil,
            defaultOutputModes: [String]? = nil
        ) {
            self.model = model
            self.maxTokens = maxTokens
            self.temperature = temperature
            self.topP = topP
            self.systemPrompt = systemPrompt
            self.additionalParameters = additionalParameters
            self.maxAgenticIterations = maxAgenticIterations
            self.systemPromptUpdateCallback = systemPromptUpdateCallback
            
            // Set agent properties with defaults if not provided
            self.agentName = agentName ?? "LLM Protocol Agent"
            self.agentDescription = agentDescription ?? "An A2A-compliant agent that provides text generation and conversation capabilities using any LLM that implements the LLMProtocol interface."
            self.cardCapabilities = cardCapabilities ?? .init(
                streaming: true,
                pushNotifications: false,
                stateTransitionHistory: true
            )
            self.skills = skills ?? [
                .init(
                    id: "text-generation",
                    name: "text-generation",
                    description: "Generate text responses using the underlying LLM",
                    tags: ["llm", "text"],
                    inputModes: ["text/plain"],
                    outputModes: ["text/plain"]
                ),
                .init(
                    id: "conversation",
                    name: "conversation",
                    description: "Engage in conversational interactions",
                    tags: ["llm", "conversation"],
                    inputModes: ["text/plain"],
                    outputModes: ["text/plain"]
                )
            ]
            self.defaultInputModes = defaultInputModes ?? ["text/plain"]
            self.defaultOutputModes = defaultOutputModes ?? ["text/plain"]
        }
    }
    
    // MARK: - Properties
    
    private let llm: LLMProtocol
    private let config: Configuration
    private let logger: Logger
    
    // Custom URLSession for image downloads with optimized settings
    private static let imageDownloadSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60.0  // 60 seconds per image
        configuration.timeoutIntervalForResource = 300.0  // 5 minutes total timeout
        configuration.httpMaximumConnectionsPerHost = 10  // Allow parallel downloads
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData  // Always fetch fresh images
        return URLSession(configuration: configuration)
    }()
    
    // MARK: - Initialization
    
    public init(
        llm: LLMProtocol,
        configuration: Configuration,
        logger: Logger? = nil
    ) {
        self.llm = llm
        self.config = configuration
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .adapters("LLMProtocolAdapter"),
            metadata: SwiftAgentKitLogging.metadata(
                ("model", .string(configuration.model))
            )
        )
    }
    
    /// Convenience initializer that accepts a DynamicPrompt for systemPrompt.
    /// 
    /// Example:
    /// ```swift
    /// var prompt = DynamicPrompt(template: "You are {{role}} assistant.")
    /// prompt["role"] = "helpful"
    /// let adapter = LLMProtocolAdapter(
    ///     llm: myLLM,
    ///     systemPrompt: prompt
    /// )
    /// ```
    /// 
    /// Example with callback:
    /// ```swift
    /// let adapter = LLMProtocolAdapter(
    ///     llm: myLLM,
    ///     systemPrompt: prompt,
    ///     systemPromptUpdateCallback: { params, currentPrompt in
    ///         // Update prompt based on message content
    ///         var updated = currentPrompt ?? DynamicPrompt(template: "You are a helpful assistant.")
    ///         updated["context"] = extractContext(from: params.message)
    ///         return updated
    ///     }
    /// )
    /// ```
    public init(
        llm: LLMProtocol,
        model: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        systemPrompt: DynamicPrompt? = nil,
        additionalParameters: JSON? = nil,
        maxAgenticIterations: Int = 10,
        systemPromptUpdateCallback: SystemPromptUpdateCallback? = nil,
        agentName: String? = nil,
        agentDescription: String? = nil,
        cardCapabilities: AgentCard.AgentCapabilities? = nil,
        skills: [AgentCard.AgentSkill]? = nil,
        defaultInputModes: [String]? = nil,
        defaultOutputModes: [String]? = nil,
        logger: Logger? = nil
    ) {
        let config = Configuration(
            model: model ?? llm.getModelName(),
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            systemPrompt: systemPrompt,
            additionalParameters: additionalParameters,
            maxAgenticIterations: maxAgenticIterations,
            systemPromptUpdateCallback: systemPromptUpdateCallback,
            agentName: agentName,
            agentDescription: agentDescription,
            cardCapabilities: cardCapabilities,
            skills: skills,
            defaultInputModes: defaultInputModes,
            defaultOutputModes: defaultOutputModes
        )
        self.init(llm: llm, configuration: config, logger: logger)
    }
    
    /// Convenience initializer that accepts a String for systemPrompt (deprecated).
    /// 
    /// - Deprecated: Use `DynamicPrompt` instead. Strings are automatically converted to `DynamicPrompt` instances.
    ///   For dynamic prompts with tokens, create a `DynamicPrompt` and use the non-deprecated initializer.
    /// 
    /// Example migration:
    /// ```swift
    /// // Old (deprecated):
    /// let adapter = LLMProtocolAdapter(
    ///     llm: myLLM,
    ///     systemPrompt: "You are a helpful assistant."
    /// )
    /// 
    /// // New:
    /// let prompt = DynamicPrompt(template: "You are a helpful assistant.")
    /// let adapter = LLMProtocolAdapter(
    ///     llm: myLLM,
    ///     systemPrompt: prompt
    /// )
    /// ```
    /// 
    /// - Note: This initializer only matches when `systemPrompt` is explicitly provided as a `String`.
    ///   When `systemPrompt` is omitted or `nil`, the non-deprecated `DynamicPrompt?` initializer is used.
    @available(*, deprecated, message: "Use DynamicPrompt instead. Create a DynamicPrompt from your string template and use the non-deprecated initializer.")
    public init(
        llm: LLMProtocol,
        model: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        systemPrompt: String,  // Non-optional to avoid ambiguity when omitted
        additionalParameters: JSON? = nil,
        maxAgenticIterations: Int = 10,
        systemPromptUpdateCallback: SystemPromptUpdateCallback? = nil,
        agentName: String? = nil,
        agentDescription: String? = nil,
        cardCapabilities: AgentCard.AgentCapabilities? = nil,
        skills: [AgentCard.AgentSkill]? = nil,
        defaultInputModes: [String]? = nil,
        defaultOutputModes: [String]? = nil,
        logger: Logger? = nil
    ) {
        let systemPromptDynamic = DynamicPrompt(template: systemPrompt)
        let config = Configuration(
            model: model ?? llm.getModelName(),
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            systemPrompt: systemPromptDynamic,
            additionalParameters: additionalParameters,
            maxAgenticIterations: maxAgenticIterations,
            systemPromptUpdateCallback: systemPromptUpdateCallback,
            agentName: agentName,
            agentDescription: agentDescription,
            cardCapabilities: cardCapabilities,
            skills: skills,
            defaultInputModes: defaultInputModes,
            defaultOutputModes: defaultOutputModes
        )
        self.init(llm: llm, configuration: config, logger: logger)
    }
    
    // MARK: - AgentAdapter Implementation
    
    public var agentName: String {
        config.agentName
    }
    
    public var agentDescription: String {
        config.agentDescription
    }
    
    public var cardCapabilities: AgentCard.AgentCapabilities {
        config.cardCapabilities
    }
    
    public var skills: [AgentCard.AgentSkill] {
        config.skills
    }
    
    public var defaultInputModes: [String] {
        config.defaultInputModes
    }
    
    public var defaultOutputModes: [String] {
        config.defaultOutputModes
    }
    
    public func responseType(for params: MessageSendParams) -> AdapterResponseType {
        return .task  // LLMProtocolAdapter always uses task tracking
    }
    
    public func handleMessageSend(_ params: MessageSendParams) async throws -> A2AMessage {
        // Not used - LLMProtocolAdapter always returns tasks
        fatalError("LLMProtocolAdapter always returns tasks")
    }
    
    public func handleTaskSend(_ params: MessageSendParams, taskId: String, contextId: String, store: TaskStore) async throws {
        
        // Update to working state
        await store.updateTaskStatus(
            id: taskId,
            status: TaskStatus(
                state: .working,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
        )
        
        do {
            // Check if this is an image generation request
            // extractImageGenerationConfig already verifies LLM capability and client acceptance
            if let imageGenConfig = extractImageGenerationConfig(from: params) {
                // Generate images
                let imageResponse = try await llm.generateImage(imageGenConfig)
                
                // Process image URLs (download remote URLs, verify local URLs)
                let processedImageURLs = try await processImageURLs(imageResponse.images)
                
                // Create updated response with processed URLs
                let processedResponse = ImageGenerationResponse(
                    images: processedImageURLs,
                    createdAt: imageResponse.createdAt,
                    metadata: imageResponse.metadata
                )
                
                // Convert to artifacts
                let artifacts = createArtifactsFromImageGeneration(processedResponse)
                
                // Update the task store with the artifacts
                await store.updateTaskArtifacts(
                    id: taskId,
                    artifacts: artifacts
                )
                
                // Update task with completed status
                await store.updateTaskStatus(
                    id: taskId,
                    status: TaskStatus(
                        state: .completed,
                        timestamp: ISO8601DateFormatter().string(from: .init())
                    )
                )
                
                return
            }
            
            // Get task history from store
            let task = await store.getTask(id: taskId)
            
            // Convert A2A message to SwiftAgentKit Message
            let messages = try convertA2AMessageToMessages(params.message, metadata: params.metadata, taskHistory: task?.history, params: params)
            
            // Create LLM request configuration
            let llmConfig = LLMRequestConfig(
                maxTokens: config.maxTokens,
                temperature: config.temperature,
                topP: config.topP,
                stream: false,
                availableTools: [],
                additionalParameters: config.additionalParameters
            )
            
            // Call the LLM
            let response = try await llm.send(messages, config: llmConfig)
            
            // Create response Artifact
            let responseArtifact = Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: response.content)]
            )
            
            // Update the task store with the artifact
            await store.updateTaskArtifacts(
                id: taskId,
                artifacts: [responseArtifact]
            )
            
            // Update task with completed status
            await store.updateTaskStatus(
                id: taskId,
                status: TaskStatus(
                    state: .completed,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
        } catch {
            logger.error(
                "LLM call failed",
                metadata: SwiftAgentKitLogging.metadata(
                    ("taskId", .string(taskId)),
                    ("contextId", .string(contextId)),
                    ("error", .string(String(describing: error)))
                )
            )
            
            // Update task with failed status
            await store.updateTaskStatus(
                id: taskId,
                status: TaskStatus(
                    state: .failed,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
            throw error
        }
    }
    
    public func handleStream(_ params: MessageSendParams, taskId: String?, contextId: String?, store: TaskStore?, eventSink: @escaping (Encodable) -> Void) async throws {
        // LLMProtocol adapter always uses task tracking for streaming
        guard let taskId = taskId, let contextId = contextId, let store = store else {
            throw NSError(domain: "LLMProtocolAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "LLMProtocol adapter requires task tracking for streaming"])
        }
        
        let requestId = (params.metadata?.literalValue as? [String: Any])?["requestId"] as? Int ?? 1
        
        // Update to working state
        let workingStatus = TaskStatus(
            state: .working,
            timestamp: ISO8601DateFormatter().string(from: .init())
        )
        await store.updateTaskStatus(
            id: taskId,
            status: workingStatus
        )
        
        let workingEvent = TaskStatusUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            kind: "status-update",
            status: workingStatus,
            final: false
        )
        
        let workingResponse = SendStreamingMessageSuccessResponse(
            jsonrpc: "2.0",
            id: requestId,
            result: workingEvent
        )
        eventSink(workingResponse)
        
        do {
            // Check if this is an image generation request
            // extractImageGenerationConfig already verifies LLM capability and client acceptance
            if let imageGenConfig = extractImageGenerationConfig(from: params) {
                // Generate images (typically synchronous, but we'll emit events as they're ready)
                let imageResponse = try await llm.generateImage(imageGenConfig)
                
                // Process image URLs (download remote URLs, verify local URLs)
                let processedImageURLs = try await processImageURLs(imageResponse.images)
                
                // Create updated response with processed URLs
                let processedResponse = ImageGenerationResponse(
                    images: processedImageURLs,
                    createdAt: imageResponse.createdAt,
                    metadata: imageResponse.metadata
                )
                
                // Convert to artifacts
                let artifacts = createArtifactsFromImageGeneration(processedResponse)
                
                // Emit artifact update events for each image
                for (index, artifact) in artifacts.enumerated() {
                    let isLast = index == artifacts.count - 1
                    
                    let artifactEvent = TaskArtifactUpdateEvent(
                        taskId: taskId,
                        contextId: contextId,
                        kind: "artifact-update",
                        artifact: artifact,
                        append: false,
                        lastChunk: isLast,
                        metadata: nil
                    )
                    
                    let artifactResponse = SendStreamingMessageSuccessResponse(
                        jsonrpc: "2.0",
                        id: requestId,
                        result: artifactEvent
                    )
                    
                    eventSink(artifactResponse)
                }
                
                // Update the task store with all artifacts
                await store.updateTaskArtifacts(
                    id: taskId,
                    artifacts: artifacts
                )
                
                // Update task with completed status
                let completedStatus = TaskStatus(
                    state: .completed,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
                await store.updateTaskStatus(
                    id: taskId,
                    status: completedStatus
                )
                
                let completedEvent = TaskStatusUpdateEvent(
                    taskId: taskId,
                    contextId: contextId,
                    kind: "status-update",
                    status: completedStatus,
                    final: true
                )
                
                let completedResponse = SendStreamingMessageSuccessResponse(
                    jsonrpc: "2.0",
                    id: requestId,
                    result: completedEvent
                )
                
                eventSink(completedResponse)
                
                return
            }
            
            // Get task history from store
            let task = await store.getTask(id: taskId)
            
            // Convert A2A message to SwiftAgentKit Message
            let messages = try convertA2AMessageToMessages(params.message, metadata: params.metadata, taskHistory: task?.history, params: params)
            
            // Create LLM request configuration for streaming
            let llmConfig = LLMRequestConfig(
                maxTokens: config.maxTokens,
                temperature: config.temperature,
                topP: config.topP,
                stream: true,
                availableTools: [],
                additionalParameters: config.additionalParameters
            )
            
            // Stream from the LLM
            let stream = llm.stream(messages, config: llmConfig)
            var fullContent = ""
            var partialArtifacts: [Artifact] = []
            
            for try await result in stream {
                switch result {
                case .stream(let response):
                    fullContent += response.content
                    
                    // Create artifact update event for streaming
                    let artifact = Artifact(
                        artifactId: UUID().uuidString,
                        parts: [.text(text: response.content)],
                        name: "partial-llm-response",
                        description: "Partial S=streaming response from LLM",
                        metadata: nil,
                        extensions: []
                    )
                    
                    partialArtifacts.append(artifact)
                    await store.updateTaskArtifacts(id: taskId, artifacts: partialArtifacts)
                    
                    let artifactEvent = TaskArtifactUpdateEvent(
                        taskId: taskId,
                        contextId: contextId,
                        kind: "artifact-update",
                        artifact: artifact,
                        append: true,
                        lastChunk: false,
                        metadata: nil
                    )
                    
                    let streamingEvent = SendStreamingMessageSuccessResponse(
                        jsonrpc: "2.0",
                        id: requestId,
                        result: artifactEvent
                    )
                    
                    eventSink(streamingEvent)
                    
                case .complete(let response):

                    // the response.content sould contain the full response
                    fullContent = response.content
                    
                    // Create artifact update event for final response
                    let artifact = Artifact(
                        artifactId: UUID().uuidString,
                        parts: [.text(text: response.content)],
                        name: "final-llm-response",
                        description: "Final streaming response from LLM",
                        metadata: nil,
                        extensions: []
                    )
                    
                    await store.updateTaskArtifacts(id: taskId, artifacts: [artifact])
                    
                    let artifactEvent = TaskArtifactUpdateEvent(
                        taskId: taskId,
                        contextId: contextId,
                        kind: "artifact-update",
                        artifact: artifact,
                        append: false,
                        lastChunk: true,
                        metadata: nil
                    )
                    
                    let streamingEvent = SendStreamingMessageSuccessResponse(
                        jsonrpc: "2.0",
                        id: requestId,
                        result: artifactEvent
                    )
                    
                    eventSink(streamingEvent)
                }
            }
            
            // Update task with completed status
            let completedStatus = TaskStatus(
                state: .completed,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
            await store.updateTaskStatus(
                id: taskId,
                status: completedStatus
            )
            
            let completedEvent = TaskStatusUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                kind: "status-update",
                status: completedStatus,
                final: true
            )
            
            let completedResponse = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: requestId,
                result: completedEvent
            )
            
            eventSink(completedResponse)
            
        } catch {
            logger.error(
                "LLM streaming failed",
                metadata: SwiftAgentKitLogging.metadata(
                    ("taskId", .string(taskId)),
                    ("contextId", .string(contextId)),
                    ("error", .string(String(describing: error)))
                )
            )
            
            // Update task with failed status
            let failedStatus = TaskStatus(
                state: .failed,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
            await store.updateTaskStatus(
                id: taskId,
                status: failedStatus
            )
            
            let failedEvent = TaskStatusUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                kind: "status-update",
                status: failedStatus,
                final: true
            )
            
            let failedResponse = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: requestId,
                result: failedEvent
            )
            
            eventSink(failedResponse)
            
            throw error
        }
    }
    
    // MARK: - ToolAwareAgentAdapter Methods
    
    public func handleTaskSendWithTools(_ params: MessageSendParams, taskId: String, contextId: String, toolProviders: [ToolProvider], store: TaskStore) async throws {
        
        // Update to working state
        await store.updateTaskStatus(
            id: taskId,
            status: TaskStatus(
                state: .working,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
        )
        
        do {
            // Check if this is an image generation request
            // Image generation bypasses tool handling (direct operation)
            if let imageGenConfig = extractImageGenerationConfig(from: params) {
                // Generate images
                let imageResponse = try await llm.generateImage(imageGenConfig)
                
                // Process image URLs (download remote URLs, verify local URLs)
                let processedImageURLs = try await processImageURLs(imageResponse.images)
                
                // Create updated response with processed URLs
                let processedResponse = ImageGenerationResponse(
                    images: processedImageURLs,
                    createdAt: imageResponse.createdAt,
                    metadata: imageResponse.metadata
                )
                
                // Convert to artifacts
                let artifacts = createArtifactsFromImageGeneration(processedResponse)
                
                // Update the task store with the artifacts
                await store.updateTaskArtifacts(
                    id: taskId,
                    artifacts: artifacts
                )
                
                // Update task with completed status
                await store.updateTaskStatus(
                    id: taskId,
                    status: TaskStatus(
                        state: .completed,
                        timestamp: ISO8601DateFormatter().string(from: .init())
                    )
                )
                
                return
            }
            
            // Get task history from store
            let task = await store.getTask(id: taskId)
            
            // Convert A2A message to SwiftAgentKit Message
            var messages = try convertA2AMessageToMessages(params.message, metadata: params.metadata, taskHistory: task?.history, params: params)
            let availableToolCalls: [ToolDefinition] = await {
                var returnValue = [ToolDefinition]()
                for provider in toolProviders {
                    let tools = await provider.availableTools()
                    returnValue.append(contentsOf: tools)
                }
                return returnValue
            }()
            
            // Create LLM request configuration WITH tools
            let llmConfig = LLMRequestConfig(
                maxTokens: config.maxTokens,
                temperature: config.temperature,
                topP: config.topP,
                stream: false,
                availableTools: availableToolCalls,
                additionalParameters: config.additionalParameters
            )
            
            // Agentic loop: continue calling LLM until we get a response without tool calls
            var iteration = 0
            var finalResponse: String = ""
            var toolFileArtifacts: [Artifact] = []
            
            while iteration < config.maxAgenticIterations {
                iteration += 1
                logger.debug(
                    "Agentic iteration started",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("taskId", .string(taskId)),
                        ("contextId", .string(contextId)),
                        ("iteration", .stringConvertible(iteration)),
                        ("maxIterations", .stringConvertible(config.maxAgenticIterations))
                    )
                )
                
                // Call the LLM
                let response = try await llm.send(messages, config: llmConfig)
                
                // Look at the text response for any tool calls not parsed automatically
                var llmResponse = LLMResponse.llmResponse(from: response.content, availableTools: availableToolCalls)
                // Add the Tool calls the LLM identified automatically
                llmResponse = llmResponse.appending(toolCalls: response.toolCalls)
                
                // Add assistant's response to conversation
                messages.append(Message(
                    id: UUID(),
                    role: .assistant,
                    content: llmResponse.content,
                    timestamp: Date(),
                    toolCalls: llmResponse.toolCalls,
                    toolCallId: nil
                ))
                
                // If no tool calls, we have the final answer
                if llmResponse.toolCalls.isEmpty {
                    finalResponse = llmResponse.content
                    logger.info(
                        "Final response received without tool calls",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("taskId", .string(taskId)),
                            ("contextId", .string(contextId)),
                            ("iteration", .stringConvertible(iteration))
                        )
                    )
                    break
                }
                
                // Execute tool calls and add results to conversation
                logger.info(
                    "Executing tool calls",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("taskId", .string(taskId)),
                        ("contextId", .string(contextId)),
                        ("toolCallCount", .stringConvertible(llmResponse.toolCalls.count)),
                        ("toolCalls", .array(llmResponse.toolCalls.map { .string($0.name) }))
                    )
                )
                var toolResults: [String] = []
                
                for toolCall in llmResponse.toolCalls {
                    for provider in toolProviders {
                        let result = try await provider.executeTool(toolCall)
                        if result.success {
                            let toolResultText = "Successfully Executed Tool: \(toolCall.name)\n-- Start Tool Result ---\n\(result.content)\n-- End Tool Result ---\n\nYou can now continue with the next step in the conversation."
                            toolResults.append(toolResultText)
                            
                            // Check for file resources in metadata
                            if let metadataDict = result.metadata.literalValue as? [String: Any],
                               let fileResources = metadataDict["fileResources"] as? [[String: Any]] {
                                for (index, fileResource) in fileResources.enumerated() {
                                    if let uri = fileResource["uri"] as? String,
                                       let mimeType = fileResource["mimeType"] as? String,
                                       let base64Data = fileResource["data"] as? String,
                                       let fileData = Data(base64Encoded: base64Data) {
                                        
                                        let fileName = fileResource["name"] as? String ?? "file-\(index + 1)"
                                        
                                        // Create file artifact
                                        let artifactMetadata = try? JSON([
                                            "mimeType": mimeType,
                                            "source": "mcp_tool",
                                            "toolName": toolCall.name
                                        ])
                                        
                                        let artifact = Artifact(
                                            artifactId: UUID().uuidString,
                                            parts: [.file(data: fileData, url: nil)],
                                            name: fileName,
                                            description: "File resource from MCP tool: \(toolCall.name)",
                                            metadata: artifactMetadata
                                        )
                                        
                                        toolFileArtifacts.append(artifact)
                                        
                                        logger.info(
                                            "Created file artifact from MCP tool result",
                                            metadata: SwiftAgentKitLogging.metadata(
                                                ("toolName", .string(toolCall.name)),
                                                ("fileName", .string(fileName)),
                                                ("mimeType", .string(mimeType)),
                                                ("size", .stringConvertible(fileData.count))
                                            )
                                        )
                                    }
                                }
                            }
                            
                            // Add tool result as a tool message
                            messages.append(Message(
                                id: UUID(),
                                role: .tool,
                                content: toolResultText,
                                timestamp: Date(),
                                toolCalls: [],
                                toolCallId: toolCall.id
                            ))
                        } else {
                            let errorMessage = "Error Executing Tool: \(toolCall.name)\nError: \(result.content)"
                            toolResults.append(errorMessage)
                            messages.append(Message(
                                id: UUID(),
                                role: .tool,
                                content: errorMessage,
                                timestamp: Date(),
                                toolCalls: [],
                                toolCallId: toolCall.id
                            ))
                        }
                    }
                }
            }
            
            // Check if we hit max iterations
            if iteration >= config.maxAgenticIterations && finalResponse.isEmpty {
                logger.warning(
                    "Max agentic iterations reached without final response",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("taskId", .string(taskId)),
                        ("contextId", .string(contextId)),
                        ("maxIterations", .stringConvertible(config.maxAgenticIterations))
                    )
                )
                // Use the last message as the final response
                if let lastMessage = messages.last, lastMessage.role == .assistant {
                    finalResponse = lastMessage.content
                } else {
                    finalResponse = "Maximum iterations reached. Unable to complete the task."
                }
            }
            
            // Create response Artifact with final answer
            let responseArtifact = Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: finalResponse)]
            )
            
            // Combine response artifact with file artifacts from tool results
            var allArtifacts = [responseArtifact]
            allArtifacts.append(contentsOf: toolFileArtifacts)
            
            // Update the task artifacts
            await store.updateTaskArtifacts(
                id: taskId,
                artifacts: allArtifacts
            )
            
            // Update task with completed status
            await store.updateTaskStatus(
                id: taskId,
                status: TaskStatus(
                    state: .completed,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
        } catch {
            logger.error(
                "LLM call with tools failed",
                metadata: SwiftAgentKitLogging.metadata(
                    ("taskId", .string(taskId)),
                    ("contextId", .string(contextId)),
                    ("error", .string(String(describing: error)))
                )
            )
            
            // Update task with failed status
            await store.updateTaskStatus(
                id: taskId,
                status: TaskStatus(
                    state: .failed,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
            )
            
            throw error
        }
    }
    
    public func handleStreamWithTools(_ params: MessageSendParams, taskId: String?, contextId: String?, toolProviders: [ToolProvider], store: TaskStore?, eventSink: @escaping (Encodable) -> Void) async throws {
        // LLMProtocol adapter always uses task tracking for streaming with tools
        guard let taskId = taskId, let contextId = contextId, let store = store else {
            throw NSError(domain: "LLMProtocolAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "LLMProtocol adapter requires task tracking for streaming with tools"])
        }
        
        let requestId = (params.metadata?.literalValue as? [String: Any])?["requestId"] as? Int ?? 1
        let availableToolCalls: [ToolDefinition] = await {
            var returnValue = [ToolDefinition]()
            for provider in toolProviders {
                let tools = await provider.availableTools()
                returnValue.append(contentsOf: tools)
            }
            return returnValue
        }()
        
        // Update to working state
        let workingStatus = TaskStatus(
            state: .working,
            timestamp: ISO8601DateFormatter().string(from: .init())
        )
        await store.updateTaskStatus(
            id: taskId,
            status: workingStatus
        )
        
        let workingEvent = TaskStatusUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            kind: "status-update",
            status: workingStatus,
            final: false
        )
        
        let workingResponse = SendStreamingMessageSuccessResponse(
            jsonrpc: "2.0",
            id: requestId,
            result: workingEvent
        )
        eventSink(workingResponse)
        
        do {
            // Check if this is an image generation request
            // Image generation bypasses tool handling (direct operation)
            if let imageGenConfig = extractImageGenerationConfig(from: params) {
                // Generate images
                let imageResponse = try await llm.generateImage(imageGenConfig)
                
                // Process image URLs (download remote URLs, verify local URLs)
                let processedImageURLs = try await processImageURLs(imageResponse.images)
                
                // Create updated response with processed URLs
                let processedResponse = ImageGenerationResponse(
                    images: processedImageURLs,
                    createdAt: imageResponse.createdAt,
                    metadata: imageResponse.metadata
                )
                
                // Convert to artifacts
                let artifacts = createArtifactsFromImageGeneration(processedResponse)
                
                // Emit artifact update events for each image
                for (index, artifact) in artifacts.enumerated() {
                    let isLast = index == artifacts.count - 1
                    
                    let artifactEvent = TaskArtifactUpdateEvent(
                        taskId: taskId,
                        contextId: contextId,
                        kind: "artifact-update",
                        artifact: artifact,
                        append: false,
                        lastChunk: isLast,
                        metadata: nil
                    )
                    
                    let artifactResponse = SendStreamingMessageSuccessResponse(
                        jsonrpc: "2.0",
                        id: requestId,
                        result: artifactEvent
                    )
                    
                    eventSink(artifactResponse)
                }
                
                // Update the task store with all artifacts
                await store.updateTaskArtifacts(
                    id: taskId,
                    artifacts: artifacts
                )
                
                // Update task with completed status
                let completedStatus = TaskStatus(
                    state: .completed,
                    timestamp: ISO8601DateFormatter().string(from: .init())
                )
                await store.updateTaskStatus(
                    id: taskId,
                    status: completedStatus
                )
                
                let completedEvent = TaskStatusUpdateEvent(
                    taskId: taskId,
                    contextId: contextId,
                    kind: "status-update",
                    status: completedStatus,
                    final: true
                )
                
                let completedResponse = SendStreamingMessageSuccessResponse(
                    jsonrpc: "2.0",
                    id: requestId,
                    result: completedEvent
                )
                eventSink(completedResponse)
                
                return
            }
            
            // Get task history from store
            let task = await store.getTask(id: taskId)
            
            // Convert A2A message to SwiftAgentKit Message
            var messages = try convertA2AMessageToMessages(params.message, metadata: params.metadata, taskHistory: task?.history, params: params)
            
            // Create LLM request configuration for streaming WITH tools
            let llmConfig = LLMRequestConfig(
                maxTokens: config.maxTokens,
                temperature: config.temperature,
                topP: config.topP,
                stream: true,
                availableTools: availableToolCalls,
                additionalParameters: config.additionalParameters
            )
            
            // Agentic loop: continue calling LLM until we get a response without tool calls
            var iteration = 0
            var finalResponse: String = ""
            var toolFileArtifacts: [Artifact] = []
            
            while iteration < config.maxAgenticIterations {
                iteration += 1
                logger.debug(
                    "Agentic iteration (streaming) started",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("taskId", .string(taskId)),
                        ("contextId", .string(contextId)),
                        ("iteration", .stringConvertible(iteration)),
                        ("maxIterations", .stringConvertible(config.maxAgenticIterations))
                    )
                )
                
                // Stream from the LLM
                let stream = llm.stream(messages, config: llmConfig)
                var fullContent = ""
                var streamedToolCalls: [ToolCall] = []
                
                for try await result in stream {
                    switch result {
                    case .stream(let response):
                        fullContent += response.content
                        
                        // Stream partial content to client
                        let artifact = Artifact(
                            artifactId: UUID().uuidString,
                            parts: [.text(text: response.content)],
                            name: "partial-llm-response",
                            description: "Partial streaming response from LLM",
                            metadata: nil,
                            extensions: []
                        )
                        
                        let artifactEvent = TaskArtifactUpdateEvent(
                            taskId: taskId,
                            contextId: contextId,
                            kind: "artifact-update",
                            artifact: artifact,
                            append: true,
                            lastChunk: false,
                            metadata: nil
                        )
                        
                        let streamingEvent = SendStreamingMessageSuccessResponse(
                            jsonrpc: "2.0",
                            id: requestId,
                            result: artifactEvent
                        )
                        
                        eventSink(streamingEvent)
                        
                    case .complete(let response):
                        // The response.content should contain the full response
                        fullContent = response.content
                        streamedToolCalls = response.toolCalls
                    }
                }
                
                // Look at the text response for any tool calls not parsed automatically
                var llmResponse = LLMResponse.llmResponse(from: fullContent, availableTools: availableToolCalls)
                // Add the Tool calls the LLM identified automatically
                llmResponse = llmResponse.appending(toolCalls: streamedToolCalls)
                
                // Add assistant's response to conversation
                messages.append(Message(
                    id: UUID(),
                    role: .assistant,
                    content: llmResponse.content,
                    timestamp: Date(),
                    toolCalls: llmResponse.toolCalls,
                    toolCallId: nil
                ))
                
                // If no tool calls, we have the final answer
                if llmResponse.toolCalls.isEmpty {
                    finalResponse = llmResponse.content
                    logger.info(
                        "Final streaming response received without tool calls",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("taskId", .string(taskId)),
                            ("contextId", .string(contextId)),
                            ("iteration", .stringConvertible(iteration))
                        )
                    )
                    break
                }
                
                // Execute tool calls and add results to conversation
                logger.info(
                    "Executing tool calls during streaming",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("taskId", .string(taskId)),
                        ("contextId", .string(contextId)),
                        ("toolCallCount", .stringConvertible(llmResponse.toolCalls.count)),
                        ("toolCalls", .array(llmResponse.toolCalls.map { .string($0.name) }))
                    )
                )
                
                // Stream tool execution status
                let toolStatusArtifact = Artifact(
                    artifactId: UUID().uuidString,
                    parts: [.text(text: "\n\n[Executing \(llmResponse.toolCalls.count) tool(s)...]\n\n")],
                    name: "tool-status",
                    description: "Tool execution status",
                    metadata: nil,
                    extensions: []
                )
                
                let toolStatusEvent = TaskArtifactUpdateEvent(
                    taskId: taskId,
                    contextId: contextId,
                    kind: "artifact-update",
                    artifact: toolStatusArtifact,
                    append: true,
                    lastChunk: false,
                    metadata: nil
                )
                
                let toolStatusResponse = SendStreamingMessageSuccessResponse(
                    jsonrpc: "2.0",
                    id: requestId,
                    result: toolStatusEvent
                )
                
                eventSink(toolStatusResponse)
                
                for toolCall in llmResponse.toolCalls {
                    for provider in toolProviders {
                        let result = try await provider.executeTool(toolCall)
                        if result.success {
                            // Check for file resources in metadata
                            if let metadataDict = result.metadata.literalValue as? [String: Any],
                               let fileResources = metadataDict["fileResources"] as? [[String: Any]] {
                                for (index, fileResource) in fileResources.enumerated() {
                                    if let uri = fileResource["uri"] as? String,
                                       let mimeType = fileResource["mimeType"] as? String,
                                       let base64Data = fileResource["data"] as? String,
                                       let fileData = Data(base64Encoded: base64Data) {
                                        
                                        let fileName = fileResource["name"] as? String ?? "file-\(index + 1)"
                                        
                                        // Create file artifact
                                        let artifactMetadata = try? JSON([
                                            "mimeType": mimeType,
                                            "source": "mcp_tool",
                                            "toolName": toolCall.name
                                        ])
                                        
                                        let artifact = Artifact(
                                            artifactId: UUID().uuidString,
                                            parts: [.file(data: fileData, url: nil)],
                                            name: fileName,
                                            description: "File resource from MCP tool: \(toolCall.name)",
                                            metadata: artifactMetadata,
                                            extensions: []
                                        )
                                        
                                        toolFileArtifacts.append(artifact)
                                    }
                                }
                            }
                            
                            // Add tool result as a tool message
                            messages.append(Message(
                                id: UUID(),
                                role: .tool,
                                content: "Successfully Executed Tool: \(toolCall.name)\n-- Start Tool Result ---\n\(result.content)\n-- End Tool Result ---\n\nYou can now continue with the next step in the conversation.",
                                timestamp: Date(),
                                toolCalls: [],
                                toolCallId: toolCall.id
                            ))
                        } else {
                            let errorMessage = "Error Executing Tool: \(toolCall.name)\nError: \(result.content)"
                            messages.append(Message(
                                id: UUID(),
                                role: .tool,
                                content: errorMessage,
                                timestamp: Date(),
                                toolCalls: [],
                                toolCallId: toolCall.id
                            ))
                        }
                    }
                }
            }
            
            // Check if we hit max iterations
            if iteration >= config.maxAgenticIterations && finalResponse.isEmpty {
                logger.warning(
                    "Max agentic iterations reached without final streaming response",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("taskId", .string(taskId)),
                        ("contextId", .string(contextId)),
                        ("maxIterations", .stringConvertible(config.maxAgenticIterations))
                    )
                )
                // Use the last message as the final response
                if let lastMessage = messages.last, lastMessage.role == .assistant {
                    finalResponse = lastMessage.content
                } else {
                    finalResponse = "Maximum iterations reached. Unable to complete the task."
                }
            }
            
            // Create artifact update event for final response
            let finalArtifact = Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: finalResponse)],
                name: "final-llm-response",
                description: "Final streaming response from LLM",
                metadata: nil,
                extensions: []
            )
            
            // Combine response artifact with file artifacts from tool results
            var allArtifacts = [finalArtifact]
            allArtifacts.append(contentsOf: toolFileArtifacts)
            
            await store.updateTaskArtifacts(id: taskId, artifacts: allArtifacts)
            
            let artifactEvent = TaskArtifactUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                kind: "artifact-update",
                artifact: finalArtifact,
                append: false,
                lastChunk: true,
                metadata: nil
            )
            
            let streamingEvent = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: requestId,
                result: artifactEvent
            )
            
            eventSink(streamingEvent)
            
            // Update task with completed status
            let completedStatus = TaskStatus(
                state: .completed,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
            await store.updateTaskStatus(
                id: taskId,
                status: completedStatus
            )
            
            let completedEvent = TaskStatusUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                kind: "status-update",
                status: completedStatus,
                final: true
            )
            
            let completedResponse = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: requestId,
                result: completedEvent
            )
            
            eventSink(completedResponse)
            
        } catch {
            logger.error(
                "LLM streaming with tools failed",
                metadata: SwiftAgentKitLogging.metadata(
                    ("taskId", .string(taskId)),
                    ("contextId", .string(contextId)),
                    ("error", .string(String(describing: error)))
                )
            )
            
            // Update task with failed status
            
            let failedStatus = TaskStatus(
                state: .failed,
                timestamp: ISO8601DateFormatter().string(from: .init())
            )
            await store.updateTaskStatus(
                id: taskId,
                status: failedStatus
            )
            
            let failedEvent = TaskStatusUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                kind: "status-update",
                status: failedStatus,
                final: true
            )
            
            let failedResponse = SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: requestId,
                result: failedEvent
            )
            
            eventSink(failedResponse)
            
            throw error
        }
    }
    
    // MARK: - Helper Methods
    
    private func convertA2AMessageToMessages(_ a2aMessage: A2AMessage, metadata: JSON?, taskHistory: [A2AMessage]?, params: MessageSendParams) throws -> [Message] {
        var messages: [Message] = []
        
        // Get the system prompt, potentially updated by callback
        var systemPrompt = config.systemPrompt
        if let callback = config.systemPromptUpdateCallback {
            systemPrompt = callback(params, systemPrompt)
        }
        
        // Add system prompt if configured
        if let systemPrompt = systemPrompt {
            messages.append(Message(
                id: UUID(),
                role: .system,
                content: systemPrompt.render(),
                timestamp: Date(),
                toolCalls: [],
                toolCallId: nil
            ))
        }
        
        // Add conversation history
        if let history = taskHistory {
            for historyMessage in history {
                let role = convertA2ARoleToMessageRole(historyMessage.role)
                let content = extractTextFromParts(historyMessage.parts)
                let toolCallId = (historyMessage.metadata?.literalValue as? [String: Any])?["toolCallId"] as? String
                messages.append(Message(
                    id: UUID(),
                    role: role,
                    content: content,
                    toolCallId: toolCallId
                ))
            }
        }
        
        // Add current message
        let role = convertA2ARoleToMessageRole(a2aMessage.role)
        let content = extractTextFromParts(a2aMessage.parts)
        let toolCallId = (metadata?.literalValue as? [String: Any])?["toolCallId"] as? String
        messages.append(Message(
            id: UUID(),
            role: role,
            content: content,
            timestamp: Date(),
            toolCalls: [],
            toolCallId: toolCallId
        ))
        
        return messages
    }
    
    private func convertA2ARoleToMessageRole(_ a2aRole: String) -> MessageRole {
        switch a2aRole.lowercased() {
        case "user":
            return .user
        case "assistant":
            return .assistant
        case "system":
            return .system
        case "tool":
            return .tool
        default:
            return .user
        }
    }
    
    private func extractTextFromParts(_ parts: [A2AMessagePart]) -> String {
        return parts.compactMap { part in
            switch part {
            case .text(let text):
                return text
            case .file, .data:
                // For now, we'll skip non-text parts
                // In the future, this could be enhanced to handle files and data
                return nil
            }
        }.joined(separator: "\n")
    }
    
    // MARK: - Image Generation Helpers
    
    /// Detects MIME type for an image file based on its URL extension
    private func detectMIMEType(for url: URL) -> String? {
        let pathExtension = url.pathExtension.lowercased()
        switch pathExtension {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "svg":
            return "image/svg+xml"
        case "bmp":
            return "image/bmp"
        case "tiff", "tif":
            return "image/tiff"
        default:
            return nil
        }
    }
    
    /// Processes image URLs: downloads remote URLs and saves locally, verifies local URLs exist
    /// Returns array of local file URLs (all URLs normalized to filesystem)
    /// Implements partial failure handling - continues with successful downloads
    private func processImageURLs(_ urls: [URL]) async throws -> [URL] {
        return try await withThrowingTaskGroup(of: (Int, Result<URL, Error>).self) { group in
            var results: [(Int, Result<URL, Error>)] = []
            
            // Process all URLs in parallel
            for (index, url) in urls.enumerated() {
                group.addTask { [self] in
                    do {
                        // Check if URL is local or remote
                        if url.isFileURL {
                            // Local file - verify it exists
                            guard FileManager.default.fileExists(atPath: url.path) else {
                                self.logger.warning("Local image file does not exist: \(url.path)")
                                throw LLMError.imageGenerationError(.invalidImageData(url))
                            }
                            return (index, .success(url))
                        } else {
                            // Remote URL - download and save locally
                            let localURL = try await self.downloadAndSaveImage(from: url)
                            return (index, .success(localURL))
                        }
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            
            // Collect results (both successes and failures)
            for try await result in group {
                results.append(result)
            }
            
            // Sort by original index to maintain order
            results.sort(by: { $0.0 < $1.0 })
            
            // Separate successes and failures
            var successfulURLs: [URL] = []
            var failures: [Error] = []
            
            for (_, result) in results {
                switch result {
                case .success(let url):
                    successfulURLs.append(url)
                case .failure(let error):
                    failures.append(error)
                    logger.warning("Failed to process one image URL: \(error.localizedDescription)")
                }
            }
            
            // If all failed, throw error
            guard !successfulURLs.isEmpty else {
                if let firstFailure = failures.first {
                    throw firstFailure
                }
                throw LLMError.imageGenerationError(.noImagesGenerated)
            }
            
            // Log warnings for partial failures but continue with successful downloads
            if !failures.isEmpty {
                logger.warning("\(failures.count) of \(urls.count) image URLs failed to process, continuing with \(successfulURLs.count) successful URLs")
            }
            
            return successfulURLs
        }
    }
    
    /// Downloads an image from a remote URL and saves it to the local filesystem
    private func downloadAndSaveImage(from url: URL) async throws -> URL {
        logger.debug("Downloading image from remote URL: \(url.absoluteString)")
        
        // Create request with per-image timeout
        var request = URLRequest(url: url, timeoutInterval: 60.0)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        // Download image data using custom session
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Self.imageDownloadSession.data(for: request)
        } catch {
            logger.error("Failed to download image from \(url.absoluteString): \(error)")
            throw LLMError.imageGenerationError(.downloadFailed(url, error))
        }
        
        // Validate HTTP response
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let error = NSError(domain: "HTTPError", code: httpResponse.statusCode, userInfo: nil)
            logger.error("HTTP error downloading image: \(httpResponse.statusCode)")
            throw LLMError.imageGenerationError(.downloadFailed(url, error))
        }
        
        // Validate image data (basic check - should start with image magic bytes)
        if !isValidImageData(data) {
            logger.warning("Downloaded data from \(url.absoluteString) may not be a valid image")
            // Continue anyway - let filesystem handle it
        }
        
        // Determine file extension from URL or content
        let fileExtension = url.pathExtension.isEmpty ? "png" : url.pathExtension
        
        // Save to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let localURL = tempDir.appendingPathComponent("llm-generated-\(UUID().uuidString).\(fileExtension)")
        
        do {
            try data.write(to: localURL)
            logger.debug("Downloaded and saved image to \(localURL.path)")
            return localURL
        } catch {
            logger.error("Failed to save image to \(localURL.path): \(error)")
            throw LLMError.networkError(error)
        }
    }
    
    /// Validates that data appears to be image data
    private func isValidImageData(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        
        // Check for common image magic bytes
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let jpegSignature: [UInt8] = [0xFF, 0xD8, 0xFF]
        let gifSignature: [UInt8] = [0x47, 0x49, 0x46, 0x38] // "GIF8"
        let webpSignature: [UInt8] = [0x52, 0x49, 0x46, 0x46] // "RIFF" (WebP starts with RIFF)
        
        let firstBytes = Array(data.prefix(8))
        
        return firstBytes.starts(with: pngSignature) ||
               firstBytes.prefix(3).starts(with: jpegSignature) ||
               firstBytes.prefix(4).starts(with: gifSignature) ||
               firstBytes.prefix(4).starts(with: webpSignature)
    }
    
    /// Converts an ImageGenerationResponse to A2A artifacts
    /// Creates one artifact per image URL
    /// Note: URLs should already be processed (local filesystem URLs) via processImageURLs
    private func createArtifactsFromImageGeneration(_ response: ImageGenerationResponse) -> [Artifact] {
        return response.images.enumerated().map { index, imageURL in
            let mimeType = detectMIMEType(for: imageURL)
            
            // Create metadata with MIME type and creation timestamp if available
            var metadata: JSON? = nil
            if let mimeType = mimeType {
                metadata = try? JSON([
                    "mimeType": mimeType,
                    "createdAt": ISO8601DateFormatter().string(from: response.createdAt)
                ])
            } else {
                metadata = try? JSON([
                    "createdAt": ISO8601DateFormatter().string(from: response.createdAt)
                ])
            }
            
            return Artifact(
                artifactId: UUID().uuidString,
                parts: [.file(data: nil, url: imageURL)],
                name: "generated-image-\(index + 1)",
                description: "Generated image from image generation request",
                metadata: metadata
            )
        }
    }
    
    /// Extracts image generation parameters from message parts and configuration
    /// Returns nil if this is not an image generation request
    /// 
    /// Detection logic (A2A-compliant):
    /// 1. LLM must support .imageGeneration capability
    /// 2. Client must accept image/* output modes in acceptedOutputModes
    /// 3. Message must contain text prompt
    private func extractImageGenerationConfig(from params: MessageSendParams) -> ImageGenerationRequestConfig? {
        // First check: LLM must support image generation
        guard llm.getCapabilities().contains(.imageGeneration) else {
            return nil
        }
        
        // Second check: Client must accept image output modes
        // Check if acceptedOutputModes contains any image MIME types
        let acceptedModes = params.configuration?.acceptedOutputModes ?? []
        let imageMimeTypes = ["image/png", "image/jpeg", "image/jpg", "image/gif", "image/webp", "image/*"]
        let acceptsImages = acceptedModes.contains { mode in
            imageMimeTypes.contains { imageType in
                mode.lowercased() == imageType.lowercased() || 
                (imageType == "image/*" && mode.lowercased().hasPrefix("image/"))
            }
        }
        
        guard acceptsImages else {
            return nil
        }
        
        // Third check: Message must contain text prompt
        let prompt = extractTextFromParts(params.message.parts)
        guard !prompt.isEmpty else {
            return nil
        }
        
        // Validate prompt length (typical max is 1000 characters)
        if prompt.count > 1000 {
            logger.warning("Image generation prompt exceeds 1000 characters, may be truncated by LLM")
        }
        
        // Optional: Check metadata for additional parameters (n, size)
        // This allows clients to pass optional params via metadata if needed
        let metadata = params.metadata?.literalValue as? [String: Any]
        
        // Extract and validate n parameter
        let n: Int?
        if let nValue = metadata?["n"] as? Int {
            if nValue < 1 || nValue > 10 {
                logger.warning("Invalid 'n' parameter: \(nValue). Must be between 1 and 10. Using default: 1")
                n = 1
            } else {
                n = nValue
            }
        } else {
            n = nil
        }
        
        // Extract and validate size parameter
        let size: String?
        if let sizeValue = metadata?["size"] as? String {
            let validSizes = ["256x256", "512x512", "1024x1024", "1024x1792", "1792x1024"]
            if validSizes.contains(sizeValue.lowercased()) {
                size = sizeValue.lowercased()
            } else {
                logger.warning("Invalid 'size' parameter: \(sizeValue). Valid sizes: 256x256, 512x512, 1024x1024, 1024x1792, 1792x1024. Using default: 1024x1024")
                size = "1024x1024"
            }
        } else {
            size = nil
        }
        
        // Extract image and mask from file parts
        var image: Data? = nil
        var imageFileName: String? = nil
        var mask: Data? = nil
        var maskFileName: String? = nil
        
        for part in params.message.parts {
            switch part {
            case .file(let data, let url):
                if image == nil {
                    image = data
                    if let url = url {
                        imageFileName = url.lastPathComponent
                    } else if data != nil {
                        // If data provided but no URL, use default filename
                        imageFileName = "image.png"
                    }
                } else if mask == nil {
                    mask = data
                    if let url = url {
                        maskFileName = url.lastPathComponent
                    } else if data != nil {
                        maskFileName = "mask.png"
                    }
                }
            default:
                break
            }
        }
        
        return ImageGenerationRequestConfig(
            image: image,
            fileName: imageFileName,
            mask: mask,
            maskFileName: maskFileName,
            prompt: prompt,
            n: n,
            size: size
        )
    }
} 
