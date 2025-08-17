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
    
    func handleSend(_ params: MessageSendParams, task: A2ATask, store: TaskStore) async throws {
        
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [.text(text: "Hello from \(name)!")]
        )
        
        await store.updateTaskArtifacts(id: task.id, artifacts: [artifact])
    }
    
    func handleStream(_ params: MessageSendParams, task: A2ATask, store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws {
        // Simple streaming implementation
        let taskId = UUID().uuidString
        let contextId = UUID().uuidString
        
        let task = A2ATask(
            id: taskId,
            contextId: contextId,
            status: TaskStatus(
                state: .working,
                message: nil,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            history: []
        )
        
        await store.addTask(task: task)
        
        // Stream a simple response
        let responseMessage = A2AMessage(
            role: "assistant",
            parts: [.text(text: "Streaming response from \(name)")],
            messageId: UUID().uuidString,
            taskId: taskId,
            contextId: contextId
        )
        
        let updatedTask = A2ATask(
            id: taskId,
            contextId: contextId,
            status: TaskStatus(
                state: .completed,
                message: responseMessage,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            history: []
        )
        
        await store.updateTaskStatus(id: taskId, status: updatedTask.status)
        
        // Send completion event
        let completionEvent = TaskStatusUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            kind: "status-update",
            status: updatedTask.status,
            final: true
        )
        
        eventSink(completionEvent)
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
