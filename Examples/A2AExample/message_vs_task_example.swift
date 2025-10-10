import Foundation
import SwiftAgentKitA2A

// MARK: - Quick Response Adapter (returns Messages)

/// Example adapter that returns simple messages for quick, synchronous responses
/// Use this pattern for lightweight interactions that don't need task tracking
struct QuickResponseAdapter: AgentAdapter {
    
    var agentName: String { "Quick Response Agent" }
    var agentDescription: String { "Provides instant responses without task tracking" }
    var cardCapabilities: AgentCard.AgentCapabilities {
        .init(streaming: false, pushNotifications: false)
    }
    var skills: [AgentCard.AgentSkill] {
        [
            .init(
                id: "quick-qa",
                name: "Quick Q&A",
                description: "Instant answers to simple questions",
                tags: ["chat", "qa"]
            )
        ]
    }
    var defaultInputModes: [String] { ["text/plain"] }
    var defaultOutputModes: [String] { ["text/plain"] }
    
    func responseType(for params: MessageSendParams) -> AdapterResponseType {
        return .message  // Always return simple messages
    }
    
    func handleMessageSend(_ params: MessageSendParams) async throws -> A2AMessage {
        // Extract the user's message
        let userMessage = params.message.parts.compactMap {
            if case .text(let text) = $0 { return text }
            return nil
        }.joined(separator: " ")
        
        // Generate a quick response
        let responseText = "Quick response: You said '\(userMessage)'"
        
        // Return a simple message (no task tracking)
        return A2AMessage(
            role: "assistant",
            parts: [.text(text: responseText)],
            messageId: UUID().uuidString
        )
    }
    
    func handleTaskSend(_ params: MessageSendParams, taskId: String, contextId: String, store: TaskStore) async throws {
        // Not used - this adapter always returns messages
    }
    
    func handleStream(_ params: MessageSendParams, taskId: String?, contextId: String?, store: TaskStore?, eventSink: @escaping (Encodable) -> Void) async throws {
        // Simple message streaming (taskId, contextId, and store are nil for message responses)
        let responseText = "Streaming quick response!"
        let message = A2AMessage(
            role: "assistant",
            parts: [.text(text: responseText)],
            messageId: UUID().uuidString
        )
        
        // Send the message as a streaming event
        eventSink(SendStreamingMessageSuccessResponse(jsonrpc: "2.0", id: 1, result: MessageResult.message(message)))
    }
}

// MARK: - Long Running Adapter (returns Tasks)

/// Example adapter that returns tracked tasks for complex, long-running operations
/// Use this pattern when you need progress tracking, status updates, or multiple artifacts
struct LongRunningAdapter: AgentAdapter {
    
    var agentName: String { "Long Running Agent" }
    var agentDescription: String { "Handles complex operations with full task tracking" }
    var cardCapabilities: AgentCard.AgentCapabilities {
        .init(streaming: true, pushNotifications: false)
    }
    var skills: [AgentCard.AgentSkill] {
        [
            .init(
                id: "deep-analysis",
                name: "Deep Analysis",
                description: "Comprehensive analysis with progress tracking",
                tags: ["analysis", "research"]
            )
        ]
    }
    var defaultInputModes: [String] { ["text/plain"] }
    var defaultOutputModes: [String] { ["text/plain"] }
    
    func responseType(for params: MessageSendParams) -> AdapterResponseType {
        return .task  // Always return tracked tasks
    }
    
    func handleMessageSend(_ params: MessageSendParams) async throws -> A2AMessage {
        // Not used - this adapter always returns tasks
        fatalError("This adapter always returns tasks")
    }
    
    func handleTaskSend(_ params: MessageSendParams, taskId: String, contextId: String, store: TaskStore) async throws {
        // Mark as working
        await store.updateTaskStatus(
            id: taskId,
            status: TaskStatus(
                state: .working,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        )
        
        // Extract the user's message
        let userMessage = params.message.parts.compactMap {
            if case .text(let text) = $0 { return text }
            return nil
        }.joined(separator: " ")
        
        // Simulate long-running work
        print("Processing complex request: \(userMessage)")
        try await Task.sleep(for: .seconds(2))
        
        // Create artifacts
        let analysisArtifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [.text(text: "Analysis complete for: '\(userMessage)'")],
            name: "analysis-result",
            description: "Detailed analysis results"
        )
        
        await store.updateTaskArtifacts(id: taskId, artifacts: [analysisArtifact])
        
        // Mark completed
        await store.updateTaskStatus(
            id: taskId,
            status: TaskStatus(
                state: .completed,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        )
    }
    
    func handleStream(_ params: MessageSendParams, taskId: String?, contextId: String?, store: TaskStore?, eventSink: @escaping (Encodable) -> Void) async throws {
        // Task-based streaming (taskId, contextId, and store are provided)
        guard let taskId = taskId, let contextId = contextId, let store = store else {
            throw NSError(domain: "LongRunningAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Task streaming requires taskId, contextId, and store"])
        }
        
        // Send working status
        let working = TaskStatus(
            state: .working,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        await store.updateTaskStatus(id: taskId, status: working)
        
        let workingEvent = TaskStatusUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            status: working,
            final: false
        )
        eventSink(SendStreamingMessageSuccessResponse(
            jsonrpc: "2.0",
            id: 1,
            result: MessageResult.taskStatusUpdate(workingEvent)
        ))
        
        // Stream progress updates
        for i in 1...5 {
            try await Task.sleep(for: .seconds(1))
            
            let artifact = Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: "Processing step \(i) of 5...")],
                name: "step-\(i)"
            )
            
            let artifactEvent = TaskArtifactUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                artifact: artifact,
                append: true,
                lastChunk: i == 5
            )
            eventSink(SendStreamingMessageSuccessResponse(
                jsonrpc: "2.0",
                id: 1,
                result: MessageResult.taskArtifactUpdate(artifactEvent)
            ))
        }
        
        // Send completion
        let completed = TaskStatus(
            state: .completed,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        await store.updateTaskStatus(id: taskId, status: completed)
        
        let completedEvent = TaskStatusUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            status: completed,
            final: true
        )
        eventSink(SendStreamingMessageSuccessResponse(
            jsonrpc: "2.0",
            id: 1,
            result: MessageResult.taskStatusUpdate(completedEvent)
        ))
    }
}

// MARK: - Main Example

/// Example demonstrating message vs task responses
/// Note: This is a demonstration file. To run, remove @main from this file or move to a separate module.
func messageVsTaskExample() async throws {
        print("=== Message vs Task Response Example ===\n")
        print("This example demonstrates two adapter patterns:\n")
        print("1. QuickResponseAdapter - Returns simple messages (lightweight)")
        print("2. LongRunningAdapter - Returns tracked tasks (full tracking)\n")
        
        // Choose which adapter to use
        print("Starting servers on different ports...\n")
        
        // Quick response server on port 4245
        let quickAdapter = QuickResponseAdapter()
        let quickServer = A2AServer(port: 4245, adapter: quickAdapter)
        
        Task {
            try await quickServer.start()
        }
        
        print("✓ Quick Response Server started on port 4245")
        print("  - Returns simple messages")
        print("  - No task tracking overhead")
        print("  - Best for: chat, simple Q&A\n")
        
        // Long running server on port 4246
        let longAdapter = LongRunningAdapter()
        let longServer = A2AServer(port: 4246, adapter: longAdapter)
        
        Task {
            try await longServer.start()
        }
        
        print("✓ Long Running Server started on port 4246")
        print("  - Returns tracked tasks")
        print("  - Full progress tracking")
        print("  - Best for: analysis, research, complex work\n")
        
        print("Both servers are now running. Press Ctrl+C to stop.")
        
        // Keep running
        try await Task.sleep(for: .seconds(.infinity))
}

