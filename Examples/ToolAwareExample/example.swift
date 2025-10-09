import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitAdapters
import SwiftAgentKitA2A

@main
struct ToolAwareExample {
    static func main() async throws {
        let logger = Logger(label: "ToolAwareExample")
        logger.info("Starting Tool-Aware Adapter Example")
        
        // Create a task store
        let taskStore = TaskStore()
        
        // Create a custom tool provider
        let customToolProvider = CustomToolProvider()
        
        // Create a tool manager
        let toolManager = ToolManager()
        _ = toolManager.addProvider(customToolProvider)
        
        // Create base adapters
        let openAIAdapter = OpenAIAdapter(apiKey: "your-openai-key")
        let anthropicAdapter = AnthropicAdapter(apiKey: "your-anthropic-key")
        
        // Create tool-aware adapters
        let toolAwareOpenAI = ToolProxyAdapter(
            baseAdapter: openAIAdapter,
            toolManager: toolManager
        )
        
        let toolAwareAnthropic = ToolProxyAdapter(
            baseAdapter: anthropicAdapter,
            toolManager: toolManager
        )
        
        // Example 1: Using the builder pattern
        logger.info("Example 1: Using the builder pattern")
        let builderAdapter = AdapterBuilder()
            .withLLM(openAIAdapter)
            .withToolProvider(customToolProvider)
            .build()
        
        let message1 = A2AMessage(
            role: "user",
            parts: [.text(text: "What's the weather like in San Francisco?")],
            messageId: UUID().uuidString,
            taskId: UUID().uuidString,
            contextId: UUID().uuidString
        )
        
        let params1 = MessageSendParams(message: message1)
        let task1 = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(
                state: .submitted,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            history: [params1.message]
        )
        await taskStore.addTask(task: task1)
        
        do {
            try await builderAdapter.handleSend(params1, task: task1, store: taskStore)
            if let responseMessage = task1.status.message,
               let firstPart = responseMessage.parts.first,
               case .text(let text) = firstPart {
                logger.info("Builder response: \(text)")
            }
        } catch {
            logger.error("Builder example failed: \(error)")
        }
        
        // Example 2: Direct tool-aware adapter usage
        logger.info("Example 2: Direct tool-aware adapter usage")
        let message2 = A2AMessage(
            role: "user",
            parts: [.text(text: "Can you tell me about the weather in New York?")],
            messageId: UUID().uuidString,
            taskId: UUID().uuidString,
            contextId: UUID().uuidString
        )
        
        let params2 = MessageSendParams(message: message2)
        let task2 = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(
                state: .submitted,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            history: [params2.message]
        )
        await taskStore.addTask(task: task2)
        
        do {
            try await toolAwareOpenAI.handleSend(params2,task: task2, store: taskStore)
            if let responseMessage = task2.status.message,
               let firstPart = responseMessage.parts.first,
               case .text(let text) = firstPart {
                logger.info("Direct adapter response: \(text)")
            }
        } catch {
            logger.error("Direct adapter example failed: \(error)")
        }
        
        // Example 3: Manual setup without builder
        logger.info("Example 3: Manual setup without builder")
        let message3 = A2AMessage(
            role: "user",
            parts: [.text(text: "Execute the custom_function with input 'test input'")],
            messageId: UUID().uuidString,
            taskId: UUID().uuidString,
            contextId: UUID().uuidString
        )
        
        let params3 = MessageSendParams(message: message3)
        let task3 = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(
                state: .submitted,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            history: [params3.message]
        )
        await taskStore.addTask(task: task3)
        
        do {
            try await toolAwareAnthropic.handleSend(params3, task: task3, store: taskStore)
            if let responseMessage = task3.status.message,
               let firstPart = responseMessage.parts.first,
               case .text(let text) = firstPart {
                logger.info("Manual setup response: \(text)")
            }
        } catch {
            logger.error("Manual setup example failed: \(error)")
        }
        
        // Example 4: Streaming with tools
        logger.info("Example 4: Streaming with tools")
        let message4 = A2AMessage(
            role: "user",
            parts: [.text(text: "Stream a response about the weather in London")],
            messageId: UUID().uuidString,
            taskId: UUID().uuidString,
            contextId: UUID().uuidString
        )
        
        let params4 = MessageSendParams(message: message4)
        let task4 = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(
                state: .submitted,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            history: [params4.message]
        )
        await taskStore.addTask(task: task4)
        
        do {
            try await toolAwareOpenAI.handleStream(params4, task: task4, store: taskStore) { @Sendable event in
                logger.info("Stream event: \(type(of: event))")
            }
        } catch {
            logger.error("Streaming example failed: \(error)")
        }
        
        logger.info("Tool-Aware Adapter Example completed!")
    }
}

// Custom tool provider implementation
struct CustomToolProvider: ToolProvider {
    public var name: String { "Custom Tools" }
    
    public func availableTools() async -> [ToolDefinition] {
        return [
            ToolDefinition(
                name: "custom_function",
                description: "A custom function that does something",
                parameters: [],
                type: .function
            ),
            ToolDefinition(
                name: "weather_tool",
                description: "Get weather information for a location",
                parameters: [.init(name: "latitude", description: "latitude", type: "string", required: true), .init(name: "longitude", description: "longitude", type: "string", required: true)],
                type: .function
            )
        ]
    }
    
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        switch toolCall.name {
        case "custom_function":
            let input: String
            if case .object(let argsDict) = toolCall.arguments,
               case .string(let inputStr) = argsDict["input"] {
                input = inputStr
            } else {
                input = "no input"
            }
            return ToolResult(
                success: true,
                content: "Custom function executed successfully with input: \(input)",
                metadata: .object(["source": .string("custom_function")])
            )
            
        case "weather_tool":
            let location: String
            let units: String
            if case .object(let argsDict) = toolCall.arguments {
                if case .string(let locationStr) = argsDict["location"] {
                    location = locationStr
                } else {
                    location = "unknown"
                }
                if case .string(let unitsStr) = argsDict["units"] {
                    units = unitsStr
                } else {
                    units = "celsius"
                }
            } else {
                location = "unknown"
                units = "celsius"
            }
            return ToolResult(
                success: true,
                content: "Weather in \(location): 22°\(units), sunny with light breeze",
                metadata: .object([
                    "source": .string("weather_tool"),
                    "location": .string(location),
                    "units": .string(units)
                ])
            )
            
        default:
            return ToolResult(
                success: false,
                content: "",
                error: "Unknown tool: \(toolCall.name)"
            )
        }
    }
} 
