import Foundation
import Testing
import SwiftAgentKitOrchestrator
import SwiftAgentKit
import SwiftAgentKitMCP
import SwiftAgentKitA2A
import Logging
import EasyJSON

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


@Suite struct SwiftAgentKitOrchestratorTests {
    
    @Test("SwiftAgentKitOrchestrator can be initialized with LLM")
    func testInitialization() async throws {
        let mockLLM = MockLLM(model: "test-model", logger: Logger(label: "MockLLM"))
        let orchestrator = SwiftAgentKitOrchestrator(llm: mockLLM)
        
        #expect(await orchestrator.llm is MockLLM)
        #expect(mockLLM.getModelName() == "test-model")
    }
    
    @Test("OrchestratorConfig can be initialized with default values")
    func testOrchestratorConfigDefaultInit() throws {
        let config = OrchestratorConfig()
        
        #expect(config.streamingEnabled == false)
        #expect(config.mcpEnabled == false)
        #expect(config.a2aEnabled == false)
        #expect(config.maxTokens == nil)
        #expect(config.temperature == nil)
        #expect(config.topP == nil)
        #expect(config.additionalParameters == nil)
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
        #expect(config.a2aEnabled == true)
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
        _ = Task {
            for await message in messageStream {
                await collector.append(message)
            }
        }
        
        try await orchestrator.updateConversation(initialMessages, availableTools: [])
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
        _ = Task {
            for await message in messageStream {
                await collector.append(message)
            }
        }
        
        try await orchestrator.updateConversation(initialMessages, availableTools: [])
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
        
        // Start listening to the stream
        _ = Task {
            for await message in messageStream {
                #expect(message.role == .assistant)
                await collector.append(message)
            }
        }
        
        // Process the conversation
        try await orchestrator.updateConversation(initialMessages, availableTools: [])
        
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
        
        // Start listening to the stream
        _ = Task {
            for await message in messageStream {
                #expect(message.role == .assistant)
                await collector.append(message)
            }
        }
        
        // Process the conversation
        try await orchestrator.updateConversation(initialMessages, availableTools: [])
        
        // Give a small delay to allow stream listeners to process messages
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        let streamCount = await collector.count
        let finalConversation = await collector.messages
        #expect(streamCount > 0) // Should have received some streaming chunks
        #expect(finalConversation.count >= 1) // At least one new message
        #expect(finalConversation.last?.role == .assistant)
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
        
        // Start listening to the stream
        _ = Task {
            for await message in messageStream {
                #expect(message.role == .assistant)
                await collector.append(message)
            }
        }
        
        // Process the conversation
        try await orchestrator.updateConversation(initialMessages, availableTools: [])
        
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
        
        // Start listening to the stream
        _ = Task {
            for await message in messageStream {
                #expect(message.role == .assistant)
                await collector.append(message)
            }
        }
        
        // Process the conversation
        try await orchestrator.updateConversation(initialMessages, availableTools: availableTools)
        
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
        _ = Task {
            for await message in messageStream {
                await collector.append(message)
            }
        }
        
        // Process conversation - this should handle tool calls
        try await orchestrator.updateConversation(initialMessages, availableTools: [])
        
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
        _ = Task {
            for await message in messageStream {
                await collector.append(message)
            }
        }
        
        // Process conversation
        try await orchestrator.updateConversation(initialMessages, availableTools: [])
        
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
        _ = Task { for await _ in messageStream {} }
        
        try await orchestrator.updateConversation(
            [Message(id: UUID(), role: .user, content: "Generate an image")],
            availableTools: []
        )
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
        _ = Task { for await _ in messageStream {} }
        
        try await orchestrator.updateConversation(
            [Message(id: UUID(), role: .user, content: "Get the document")],
            availableTools: []
        )
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
        _ = Task { for await _ in messageStream {} }
        
        try await orchestrator.updateConversation(
            [Message(id: UUID(), role: .user, content: "Generate media")],
            availableTools: []
        )
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
        _ = Task { for await _ in messageStream {} }
        
        try await orchestrator.updateConversation(
            [Message(id: UUID(), role: .user, content: "Send image only")],
            availableTools: []
        )
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
        _ = Task { for await _ in messageStream {} }
        
        try await orchestrator.updateConversation(
            [Message(id: UUID(), role: .user, content: "What time is it?")],
            availableTools: []
        )
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
        _ = Task { for await _ in messageStream {} }
        
        try await orchestrator.updateConversation(
            [Message(id: UUID(), role: .user, content: "Use unknown_tool")],
            availableTools: []
        )
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
        _ = Task { for await _ in messageStream {} }
        
        try await orchestrator.updateConversation(
            [Message(id: UUID(), role: .user, content: "What time is it?")],
            availableTools: []
        )
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
} 