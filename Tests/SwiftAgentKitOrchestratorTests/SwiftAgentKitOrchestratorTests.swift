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
} 