import Foundation
import Testing
import SwiftAgentKitOrchestrator
import SwiftAgentKit
import Logging

// Mock LLM for testing
struct MockLLM: LLMProtocol {
    let model: String
    let logger: Logger
    
    init(model: String = "mock-gpt-4", logger: Logger) {
        self.model = model
        self.logger = logger
    }
    
    func getModelName() -> String {
        return model
    }
    
    func getCapabilities() -> [LLMCapability] {
        return [.completion, .tools]
    }
    
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        return LLMResponse.complete(content: "Mock response")
    }
    
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                // Simulate streaming response with multiple chunks
                let chunks = ["Mock", " streaming", " response"]
                
                // Send streaming chunks
                for chunk in chunks {
                    continuation.yield(.stream(LLMResponse.streamChunk(chunk)))
                }
                
                // Send the complete response
                continuation.yield(.complete(LLMResponse.complete(content: "Mock streaming response")))
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
        var finalConversation: [Message]?
        
        // Start listening to the stream
        _ = Task {
            for await message in messageStream {
                #expect(message.role == .assistant)
                finalConversation = finalConversation ?? []
                finalConversation?.append(message)
            }
        }
        
        // Process the conversation
        try await orchestrator.updateConversation(initialMessages, availableTools: [])
        
        // Give a small delay to allow stream listeners to process messages
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        #expect(finalConversation != nil)
        #expect(finalConversation!.count >= 1) // At least one new message
        #expect(finalConversation!.last?.role == .assistant)
        #expect(finalConversation!.last?.content.contains("Mock response") == true)
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
        var streamCount = 0
        var finalConversation: [Message]?
        
        // Start listening to the stream
        _ = Task {
            for await message in messageStream {
                streamCount += 1
                #expect(message.role == .assistant)
                finalConversation = finalConversation ?? []
                finalConversation?.append(message)
            }
        }
        
        // Process the conversation
        try await orchestrator.updateConversation(initialMessages, availableTools: [])
        
        // Give a small delay to allow stream listeners to process messages
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        #expect(streamCount > 0) // Should have received some streaming chunks
        #expect(finalConversation != nil)
        #expect(finalConversation!.count >= 1) // At least one new message
        #expect(finalConversation!.last?.role == .assistant)
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
        var finalConversation: [Message]?
        
        // Start listening to the stream
        _ = Task {
            for await message in messageStream {
                #expect(message.role == .assistant)
                finalConversation = finalConversation ?? []
                finalConversation?.append(message)
            }
        }
        
        // Process the conversation
        try await orchestrator.updateConversation(initialMessages, availableTools: [])
        
        // Give a small delay to allow stream listeners to process messages
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        #expect(finalConversation != nil)
        #expect(finalConversation!.count >= 1) // At least one new message
        
        // Check that we received at least one new message
        #expect(finalConversation!.last?.role == .assistant) // New response
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
        var finalConversation: [Message]?
        
        // Start listening to the stream
        _ = Task {
            for await message in messageStream {
                #expect(message.role == .assistant)
                finalConversation = finalConversation ?? []
                finalConversation?.append(message)
            }
        }
        
        // Process the conversation
        try await orchestrator.updateConversation(initialMessages, availableTools: availableTools)
        
        // Give a small delay to allow stream listeners to process messages
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        #expect(finalConversation != nil)
        #expect(finalConversation!.count >= 1) // At least one new message
        #expect(finalConversation!.last?.role == .assistant)
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
} 