import Testing
import Logging
import Foundation
@testable import SwiftAgentKitAdapters
@testable import SwiftAgentKitA2A
@testable import SwiftAgentKit

@Suite("ToolAwareAdapter Tests")
struct ToolAwareAdapterTests {
    

    
    @Test("ToolAwareAdapter should be created successfully")
    func testToolAwareAdapterCreation() throws {
        // Create a simple mock adapter
        let mockAdapter = SimpleMockAdapter()
        
        // Create a tool manager
        let toolManager = ToolManager()
        toolManager.addProvider(SimpleToolProvider())
        
        // Create the tool-aware adapter
        let toolAwareAdapter = ToolAwareAdapter(
            baseAdapter: mockAdapter,
            toolManager: toolManager
        )
        
        // Verify the adapter was created
        #expect(toolAwareAdapter.cardCapabilities.streaming == true)
        #expect(toolAwareAdapter.skills.count > 0)
    }
}

// Simple mock adapter for testing
final class SimpleMockAdapter: AgentAdapter {
    var cardCapabilities: AgentCard.AgentCapabilities {
        .init(streaming: true, pushNotifications: false, stateTransitionHistory: true)
    }
    
    var skills: [AgentCard.AgentSkill] {
        [.init(id: "mock", name: "Mock", description: "Mock skill", tags: ["mock"])]
    }
    
    var defaultInputModes: [String] { ["text/plain"] }
    var defaultOutputModes: [String] { ["text/plain"] }
    
    func handleSend(_ params: MessageSendParams, store: TaskStore) async throws -> A2ATask {
        let taskId = UUID().uuidString
        let contextId = UUID().uuidString
        
        let message = A2AMessage(
            role: "assistant",
            parts: [.text(text: "Mock response")],
            messageId: UUID().uuidString,
            taskId: taskId,
            contextId: contextId
        )
        
        let task = A2ATask(
            id: taskId,
            contextId: contextId,
            status: TaskStatus(
                state: .completed,
                message: message,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            history: []
        )
        
        await store.addTask(task: task)
        return task
    }
    
    func handleStream(_ params: MessageSendParams, store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws {
        // Mock streaming implementation
    }
}

// Simple tool provider for testing
struct SimpleToolProvider: ToolProvider {
    var name: String { "Simple Tools" }
    
    func availableTools() async -> [ToolDefinition] {
        return [
            ToolDefinition(
                name: "simple_tool",
                description: "A simple tool for testing",
                parameters: [],
                type: .function
            )
        ]
    }
    
    func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        return ToolResult(
            success: true,
            content: "Simple tool executed successfully",
            metadata: .object(["source": .string("simple_tool")])
        )
    }
} 