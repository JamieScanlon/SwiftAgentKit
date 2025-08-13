import Foundation
import Testing
import SwiftAgentKit
import SwiftAgentKitAdapters
import SwiftAgentKitA2A

@Suite("ToolAwareAdapter Tests")
struct ToolAwareAdapterTests {
    
    @Test("processResponseForToolCalls - Text-based tool calls")
    func testProcessResponseForToolCallsTextBased() async throws {
        // Create a mock adapter that implements ToolAwareAgentAdapter
        let mockAdapter = MockToolAwareAdapter()
        let toolManager = ToolManager()
        let toolAwareAdapter = ToolAwareAdapter(baseAdapter: mockAdapter, toolManager: toolManager)
        
        // Create a message with text-based tool calls
        let message = A2AMessage(
            role: "assistant",
            parts: [.text(text: "Here is the answer: search_tool(query=\"test\")")],
            messageId: "test-message"
        )
        
        // Process the response
        let (processedMessage, toolCalls) = await toolAwareAdapter.processResponseForToolCalls(message, availableTools: ["search_tool"])
        
        // Verify the text was processed correctly
        #expect(processedMessage.parts.count == 1)
        if case .text(let text) = processedMessage.parts[0] {
            #expect(text == "Here is the answer: ")
        } else {
            #expect(false, "Expected text part")
        }
        
        // Verify tool calls were extracted
        #expect(toolCalls.count == 1)
        #expect(toolCalls[0].name == "search_tool")
        #expect(toolCalls[0].arguments["query"] as? String == "test")
    }
    
    @Test("processResponseForToolCalls - Data-based tool calls")
    func testProcessResponseForToolCallsDataBased() async throws {
        // Create a mock adapter that implements ToolAwareAgentAdapter
        let mockAdapter = MockToolAwareAdapter()
        let toolManager = ToolManager()
        let toolAwareAdapter = ToolAwareAdapter(baseAdapter: mockAdapter, toolManager: toolManager)
        
        // Create tool call data in the format used by OpenAI adapter
        let toolCallDict: [String: Any] = [
            "id": "call_123",
            "type": "function",
            "function": [
                "name": "calculate_sum",
                "arguments": "{\"a\": 5, \"b\": 10}"
            ]
        ]
        let toolCallData = try JSONSerialization.data(withJSONObject: toolCallDict)
        
        // Create a message with data-based tool calls
        let message = A2AMessage(
            role: "assistant",
            parts: [
                .text(text: "I'll calculate the sum for you."),
                .data(data: toolCallData)
            ],
            messageId: "test-message"
        )
        
        // Process the response
        let (processedMessage, toolCalls) = await toolAwareAdapter.processResponseForToolCalls(message, availableTools: [])
        
        // Verify the text was preserved
        #expect(processedMessage.parts.count == 1)
        if case .text(let text) = processedMessage.parts[0] {
            #expect(text == "I'll calculate the sum for you.")
        } else {
            #expect(false, "Expected text part")
        }
        
        // Verify tool calls were extracted from data
        #expect(toolCalls.count == 1)
        #expect(toolCalls[0].name == "calculate_sum")
        #expect(toolCalls[0].arguments["a"] as? Int == 5)
        #expect(toolCalls[0].arguments["b"] as? Int == 10)
    }
    
    @Test("processResponseForToolCalls - Mixed content types")
    func testProcessResponseForToolCallsMixedContent() async throws {
        // Create a mock adapter that implements ToolAwareAgentAdapter
        let mockAdapter = MockToolAwareAdapter()
        let toolManager = ToolManager()
        let toolAwareAdapter = ToolAwareAdapter(baseAdapter: mockAdapter, toolManager: toolManager)
        
        // Create tool call data
        let toolCallDict: [String: Any] = [
            "id": "call_456",
            "type": "function",
            "function": [
                "name": "get_weather",
                "arguments": "{\"city\": \"New York\", \"units\": \"celsius\"}"
            ]
        ]
        let toolCallData = try JSONSerialization.data(withJSONObject: toolCallDict)
        
        // Create a message with mixed content: text with embedded tool call + data-based tool call
        let message = A2AMessage(
            role: "assistant",
            parts: [
                .text(text: "Let me check the weather: get_weather(city=\"London\") and also get the weather for New York."),
                .data(data: toolCallData)
            ],
            messageId: "test-message"
        )
        
        // Process the response
        let (processedMessage, toolCalls) = await toolAwareAdapter.processResponseForToolCalls(message, availableTools: ["get_weather"])
        
        // Verify the text was processed correctly (embedded tool call removed)
        #expect(processedMessage.parts.count == 1)
        if case .text(let text) = processedMessage.parts[0] {
            #expect(text == "Let me check the weather:  and also get the weather for New York.")
        } else {
            #expect(false, "Expected text part")
        }
        
        // Verify both tool calls were extracted
        #expect(toolCalls.count == 2)
        
        // Find the text-based tool call
        let textToolCall: ToolCall? = toolCalls.first { $0.name == "get_weather" && $0.arguments["city"] as? String == "London" }
        #expect(textToolCall != nil)
        
        // Find the data-based tool call
        let dataToolCall: ToolCall? = toolCalls.first { $0.name == "get_weather" && $0.arguments["city"] as? String == "New York" }
        #expect(dataToolCall != nil)
        #expect(dataToolCall?.arguments["units"] as? String == "celsius")
    }
    
    @Test("processResponseForToolCalls - No tool calls")
    func testProcessResponseForToolCallsNoToolCalls() async throws {
        // Create a mock adapter that implements ToolAwareAgentAdapter
        let mockAdapter = MockToolAwareAdapter()
        let toolManager = ToolManager()
        let toolAwareAdapter = ToolAwareAdapter(baseAdapter: mockAdapter, toolManager: toolManager)
        
        // Create a message with no tool calls
        let message = A2AMessage(
            role: "assistant",
            parts: [.text(text: "This is a regular response without any tool calls.")],
            messageId: "test-message"
        )
        
        // Process the response
        let (processedMessage, toolCalls) = await toolAwareAdapter.processResponseForToolCalls(message, availableTools: [])
        
        // Verify the text was preserved
        #expect(processedMessage.parts.count == 1)
        if case .text(let text) = processedMessage.parts[0] {
            #expect(text == "This is a regular response without any tool calls.")
        } else {
            #expect(false, "Expected text part")
        }
        
        // Verify no tool calls were extracted
        #expect(toolCalls.isEmpty)
    }
    
    @Test("processResponseForToolCalls - Invalid data")
    func testProcessResponseForToolCallsInvalidData() async throws {
        // Create a mock adapter that implements ToolAwareAgentAdapter
        let mockAdapter = MockToolAwareAdapter()
        let toolManager = ToolManager()
        let toolAwareAdapter = ToolAwareAdapter(baseAdapter: mockAdapter, toolManager: toolManager)
        
        // Create invalid data
        let invalidData = "This is not JSON".data(using: .utf8)!
        
        // Create a message with invalid data
        let message = A2AMessage(
            role: "assistant",
            parts: [
                .text(text: "Here is some text."),
                .data(data: invalidData)
            ],
            messageId: "test-message"
        )
        
        // Process the response
        let (processedMessage, toolCalls) = await toolAwareAdapter.processResponseForToolCalls(message, availableTools: [])
        
        // Verify the text was preserved
        #expect(processedMessage.parts.count == 2)
        if case .text(let text) = processedMessage.parts[0] {
            #expect(text == "Here is some text.")
        } else {
            #expect(false, "Expected text part")
        }
        
        // Verify the invalid data was preserved as-is
        if case .data(let data) = processedMessage.parts[1] {
            #expect(data == invalidData)
        } else {
            #expect(false, "Expected data part")
        }
        
        // Verify no tool calls were extracted
        #expect(toolCalls.isEmpty)
    }
}

// MARK: - Mock Adapter

private struct MockToolAwareAdapter: ToolAwareAgentAdapter {
    var cardCapabilities: AgentCard.AgentCapabilities {
        .init(streaming: true, pushNotifications: false, stateTransitionHistory: true)
    }
    
    var skills: [AgentCard.AgentSkill] {
        [.init(id: "test", name: "Test", description: "Test skill", tags: [], examples: [], inputModes: [], outputModes: [])]
    }
    
    var agentName: String {
        "Mock Tool-Aware Agent"
    }
    
    var agentDescription: String {
        "A mock agent adapter for testing tool-aware functionality."
    }
    
    var defaultInputModes: [String] { ["text/plain"] }
    var defaultOutputModes: [String] { ["text/plain"] }
    
    func handleSend(_ params: MessageSendParams, store: TaskStore) async throws -> A2ATask {
        // Mock implementation
        return A2ATask(id: "test", contextId: "test", status: TaskStatus(state: .completed, message: nil, timestamp: ""), history: [])
    }
    
    func handleStream(_ params: MessageSendParams, store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws {
        // Mock implementation
    }
    
    func handleSendWithTools(_ params: MessageSendParams, availableToolCalls: [ToolDefinition], store: TaskStore) async throws -> A2ATask {
        // Mock implementation
        return A2ATask(id: "test", contextId: "test", status: TaskStatus(state: .completed, message: nil, timestamp: ""), history: [])
    }
    
    func handleStreamWithTools(_ params: MessageSendParams, availableToolCalls: [ToolDefinition], store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws {
        // Mock implementation
    }
} 