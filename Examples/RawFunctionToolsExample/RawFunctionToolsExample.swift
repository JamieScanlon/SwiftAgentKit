import Foundation
import SwiftAgentKit
import EasyJSON
import Logging

struct RemoteWeatherProvider: ToolProvider {
    var name: String { "RemoteWeatherProvider" }
    
    func availableTools() async -> [ToolDefinition] {
        [
            ToolDefinition(
                name: "get_weather",
                description: "Remote weather tool",
                parameters: [
                    .init(name: "city", description: "City name", type: "string", required: true)
                ],
                type: .mcpTool
            )
        ]
    }
    
    func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        ToolResult(
            success: true,
            content: "Remote provider result (should be shadowed by local provider)",
            metadata: .object(["source": .string("remote_mcp")]),
            toolCallId: toolCall.id
        )
    }
}

@main
struct RawFunctionToolsExample {
    static func main() async throws {
        LoggingSystem.bootstrap(StreamLogHandler.standardOutput)
        let logger = Logger(label: "RawFunctionToolsExample")
        SwiftAgentKitLogging.bootstrap(logger: logger, level: .debug)
        
        let config = LocalFunctionToolsConfig(functions: [
            LocalFunctionDefinition(
                name: "get_weather",
                description: "Get local weather details for a city",
                parameters: [
                    .init(name: "city", description: "City name", type: "string", required: true),
                    .init(name: "units", description: "Either metric or imperial", type: "string", required: false)
                ]
            )
        ])
        
        let localProvider = LocalFunctionToolProvider(config: config) { toolName, arguments, toolCallId in
            guard toolName == "get_weather" else {
                return ToolResult(success: false, content: "", toolCallId: toolCallId, error: "Unknown local function")
            }
            
            guard case .object(let args) = arguments,
                  case .string(let city) = args["city"] else {
                return ToolResult(
                    success: false,
                    content: "",
                    metadata: .object(["source": .string("local_function")]),
                    toolCallId: toolCallId,
                    error: "Missing required argument: city"
                )
            }
            
            let units: String = {
                if case .string(let value) = args["units"] {
                    return value
                }
                return "metric"
            }()
            
            return ToolResult(
                success: true,
                content: "Local weather for \(city): 21 degrees (\(units))",
                metadata: .object(["source": .string("local_function")]),
                toolCallId: toolCallId
            )
        }
        
        // Include a remote provider with the same tool name to demonstrate collision preference.
        let manager = ToolManager(providers: [RemoteWeatherProvider(), localProvider])
        
        let tools = await manager.allToolsAsync()
        print("Available tools: \(tools.map(\.name))")
        
        let toolCall = ToolCall(
            name: "get_weather",
            arguments: .object([
                "city": .string("Austin"),
                "units": .string("imperial")
            ]),
            id: "call_local_weather_1"
        )
        
        let result = try await manager.executeTool(toolCall)
        print("Success: \(result.success)")
        print("Tool response: \(result.content)")
        if let error = result.error {
            print("Error: \(error)")
        }
        print("Tool call id: \(result.toolCallId ?? "none")")
    }
}
