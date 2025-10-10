import Foundation
import SwiftAgentKitA2A
import SwiftAgentKitAdapters

// Custom adapter with configurable name and description
struct CustomNamedAdapter: AgentAdapter {
    let name: String
    let description: String
    
    init(name: String, description: String) {
        self.name = name
        self.description = description
    }
    
    var agentName: String { name }
    var agentDescription: String { description }
    
    var cardCapabilities: AgentCard.AgentCapabilities {
        .init(streaming: true, pushNotifications: false, stateTransitionHistory: true)
    }
    
    var skills: [AgentCard.AgentSkill] {
        [
            .init(
                id: "custom-skill",
                name: "Custom Skill",
                description: "A custom skill for demonstration",
                tags: ["custom", "demo"],
                examples: ["Example usage"],
                inputModes: ["text/plain"],
                outputModes: ["text/plain"]
            )
        ]
    }
    
    var defaultInputModes: [String] { ["text/plain"] }
    var defaultOutputModes: [String] { ["text/plain"] }
    
    func responseType(for params: MessageSendParams) -> AdapterResponseType {
        return .task
    }
    
    func handleMessageSend(_ params: MessageSendParams) async throws -> A2AMessage {
        fatalError("This adapter always returns tasks")
    }
    
    func handleTaskSend(_ params: MessageSendParams, taskId: String, contextId: String, store: TaskStore) async throws {
        
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [.text(text: "Hello from \(name)!")]
        )
        
        await store.updateTaskArtifacts(id: taskId, artifacts: [artifact])
        await store.updateTaskStatus(id: taskId, status: TaskStatus(state: .completed, timestamp: ISO8601DateFormatter().string(from: .init())))
    }
    
    func handleStream(_ params: MessageSendParams, taskId: String?, contextId: String?, store: TaskStore?, eventSink: @escaping (Encodable) -> Void) async throws {
        guard let taskId = taskId, let contextId = contextId, let store = store else {
            throw NSError(domain: "CustomNamedAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "This adapter requires task tracking for streaming"])
        }
        // Stream a simple response
        let responseMessage = A2AMessage(
            role: "assistant",
            parts: [.text(text: "Streaming response from \(name)")],
            messageId: UUID().uuidString,
            taskId: taskId,
            contextId: contextId
        )
        
        let completedStatus = TaskStatus(
            state: .completed,
            message: responseMessage,
            timestamp: ISO8601DateFormatter().string(from: .init())
        )
        
        await store.updateTaskStatus(id: taskId, status: completedStatus)
        
        // Send completion event
        let completionEvent = TaskStatusUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            kind: "status-update",
            status: completedStatus,
            final: true
        )
        
        eventSink(SendStreamingMessageSuccessResponse(jsonrpc: "2.0", id: 1, result: MessageResult.taskStatusUpdate(completionEvent)))
    }
}

struct AgentCardConfigExample {
    static func main() async {
        print("=== Agent Card Configuration Example ===\n")
        
        // Create adapters with different names and descriptions
        let weatherAgent = CustomNamedAdapter(
            name: "Weather Agent",
            description: "An A2A-compliant agent that provides weather information and forecasts for any location worldwide."
        )
        
        let codeAgent = CustomNamedAdapter(
            name: "Code Assistant",
            description: "A specialized A2A agent that helps with code generation, debugging, and software development tasks."
        )
        
        let researchAgent = CustomNamedAdapter(
            name: "Research Assistant",
            description: "An A2A agent designed to help with research tasks, data analysis, and information synthesis."
        )
        
        // Create servers with these adapters (using underscore to indicate they're not used in this demo)
        _ = A2AServer(port: 4245, adapter: weatherAgent)
        _ = A2AServer(port: 4246, adapter: codeAgent)
        _ = A2AServer(port: 4247, adapter: researchAgent)
        
        print("Created servers with configurable agent cards:")
        print("1. \(weatherAgent.agentName) - \(weatherAgent.agentDescription)")
        print("2. \(codeAgent.agentName) - \(codeAgent.agentDescription)")
        print("3. \(researchAgent.agentName) - \(researchAgent.agentDescription)")
        print("\nEach server will expose its agent card at /.well-known/agent.json")
        print("The agent card will contain the custom name and description specified in the adapter.")
        print("\nThis demonstrates how the A2AServer now uses configurable agent card metadata")
        print("instead of hardcoded values, allowing each agent to properly identify itself")
        print("and communicate its purpose to other agents in the A2A network.")
        
        print("\nTo test the agent cards, you can:")
        print("1. Start one of the servers (e.g., weatherServer.start())")
        print("2. Access the agent card at http://localhost:4245/.well-known/agent.json")
        print("3. See the custom name and description in the response")
    }
}
