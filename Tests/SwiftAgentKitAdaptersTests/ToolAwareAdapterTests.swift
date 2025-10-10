import Foundation
import Testing
import SwiftAgentKit
import SwiftAgentKitAdapters
import SwiftAgentKitA2A
import EasyJSON

// Helper extension for easier testing
extension JSON {
    subscript(key: String) -> Any? {
        guard case .object(let dict) = self else { return nil }
        guard let value = dict[key] else { return nil }
        switch value {
        case .string(let s): return s
        case .integer(let i): return i
        case .double(let d): return d
        case .boolean(let b): return b
        default: return nil
        }
    }
}

@Suite("ToolProxyAdapter Tests")
struct ToolAwareAdapterTests {
    
    @Test("processResponseForToolCalls - Text-based tool calls")
    func testProcessResponseForToolCallsTextBased() async throws {
        // Create a mock adapter that implements ToolAwareAdapter
        let mockAdapter = MockToolAwareAdapter()
        let toolManager = ToolManager()
        let _ = ToolProxyAdapter(baseAdapter: mockAdapter, toolManager: toolManager)
        
        // Process the response
        let (processedParts, toolCalls) = await ToolCall.processResponseForToolCalls([.text(text: "Here is the answer: search_tool(query=\"test\")")], availableTools: ["search_tool"])
        
        // Verify the text was processed correctly
        #expect(processedParts.count == 1)
        if case .text(let text) = processedParts[0] {
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
        // Create a mock adapter that implements ToolAwareAdapter
        let mockAdapter = MockToolAwareAdapter()
        let toolManager = ToolManager()
        let _ = ToolProxyAdapter(baseAdapter: mockAdapter, toolManager: toolManager)
        
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
        
        let parts: [A2AMessagePart] = [
                .text(text: "I'll calculate the sum for you."),
                .data(data: toolCallData)
            ]
        
        // Process the response
        let (processedParts, toolCalls) = await ToolCall.processResponseForToolCalls(parts, availableTools: [])
        
        // Verify the text was preserved
        #expect(processedParts.count == 1)
        if case .text(let text) = processedParts[0] {
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
        // Create a mock adapter that implements ToolAwareAdapter
        let mockAdapter = MockToolAwareAdapter()
        let toolManager = ToolManager()
        let _ = ToolProxyAdapter(baseAdapter: mockAdapter, toolManager: toolManager)
        
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
        let parts: [A2AMessagePart] = [
                .text(text: "Let me check the weather: get_weather(city=\"London\") and also get the weather for New York."),
                .data(data: toolCallData)
            ]
        
        // Process the response
        let (processedParts, toolCalls) = await ToolCall.processResponseForToolCalls(parts, availableTools: ["get_weather"])
        
        // Verify the text was processed correctly (embedded tool call removed)
        #expect(processedParts.count == 1)
        if case .text(let text) = processedParts[0] {
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
        // Create a mock adapter that implements ToolAwareAdapter
        let mockAdapter = MockToolAwareAdapter()
        let toolManager = ToolManager()
        let _ = ToolProxyAdapter(baseAdapter: mockAdapter, toolManager: toolManager)
        
        // Create a message with no tool calls
        let message = A2AMessage(
            role: "assistant",
            parts: [.text(text: "This is a regular response without any tool calls.")],
            messageId: "test-message"
        )
        
        // Process the response
        let (processedParts, toolCalls) = await ToolCall.processResponseForToolCalls([.text(text: "This is a regular response without any tool calls.")], availableTools: [])
        
        // Verify the text was preserved
        #expect(processedParts.count == 1)
        if case .text(let text) = processedParts[0] {
            #expect(text == "This is a regular response without any tool calls.")
        } else {
            #expect(false, "Expected text part")
        }
        
        // Verify no tool calls were extracted
        #expect(toolCalls.isEmpty)
    }
    
    @Test("processResponseForToolCalls - Invalid data")
    func testProcessResponseForToolCallsInvalidData() async throws {
        // Create a mock adapter that implements ToolAwareAdapter
        let mockAdapter = MockToolAwareAdapter()
        let toolManager = ToolManager()
        let _ = ToolProxyAdapter(baseAdapter: mockAdapter, toolManager: toolManager)
        
        // Create invalid data
        let invalidData = "This is not JSON".data(using: .utf8)!
        
        // Create a message with invalid data
        let parts: [A2AMessagePart] = [
                .text(text: "Here is some text."),
                .data(data: invalidData)
            ]
        
        // Process the response
        let (processedParts, toolCalls) = await ToolCall.processResponseForToolCalls(parts, availableTools: [])
        
        // Verify the text was preserved
        #expect(processedParts.count == 2)
        if case .text(let text) = processedParts[0] {
            #expect(text == "Here is some text.")
        } else {
            #expect(false, "Expected text part")
        }
        
        // Verify the invalid data was preserved as-is
        if case .data(let data) = processedParts[1] {
            #expect(data == invalidData)
        } else {
            #expect(false, "Expected data part")
        }
        
        // Verify no tool calls were extracted
        #expect(toolCalls.isEmpty)
    }
}

// MARK: - Mock Adapter

private struct MockToolAwareAdapter: ToolAwareAdapter {
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
    
    func responseType(for params: MessageSendParams) -> AdapterResponseType {
        return .task
    }
    
    func handleMessageSend(_ params: MessageSendParams) async throws -> A2AMessage {
        fatalError("Mock adapter always returns tasks")
    }
    
    func handleTaskSend(_ params: MessageSendParams, taskId: String, contextId: String, store: TaskStore) async throws {
        // Mock implementation
        // Create response Artifact
        let responseArtifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [.text(text: "test content")]
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
    }
    
    func handleStream(_ params: MessageSendParams, taskId: String?, contextId: String?, store: TaskStore?, eventSink: @escaping (Encodable) -> Void) async throws {
        // Mock implementation - requires task tracking
        guard let taskId = taskId, let contextId = contextId, let store = store else {
            throw NSError(domain: "MockAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock adapter requires task tracking"])
        }
        
        let requestId = (params.metadata?.literalValue as? [String: Any])?["requestId"] as? Int ?? 1
        
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
            result: MessageResult.taskStatusUpdate(completedEvent)
        )
        
        eventSink(completedResponse)
    }
    
    func handleTaskSendWithTools(_ params: MessageSendParams, taskId: String, contextId: String, toolProviders: [ToolProvider], store: TaskStore) async throws {
        // Mock implementation
        // Create response Artifact
        let responseArtifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [.text(text: "test")]
        )
        
        // Update the task artifacts
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
    }
    
    func handleStreamWithTools(_ params: MessageSendParams, taskId: String?, contextId: String?, toolProviders: [ToolProvider], store: TaskStore?, eventSink: @escaping (Encodable) -> Void) async throws {
        // Mock implementation - requires task tracking
        guard let taskId = taskId, let contextId = contextId, let store = store else {
            throw NSError(domain: "MockAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock adapter requires task tracking for tools"])
        }
        
        let requestId = (params.metadata?.literalValue as? [String: Any])?["requestId"] as? Int ?? 1
        
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
            result: MessageResult.taskStatusUpdate(completedEvent)
        )
        
        eventSink(completedResponse)
    }
} 
