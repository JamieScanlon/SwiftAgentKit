import Foundation
import EasyJSON

/// Result of a tool execution
public struct ToolResult: Sendable {
    public let success: Bool
    public let content: String
    public let metadata: JSON
    public let error: String?
    
    public init(success: Bool, content: String, metadata: JSON = .object([:]), error: String? = nil) {
        self.success = success
        self.content = content
        self.metadata = metadata
        self.error = error
    }
}

/// Definition of an available tool
public struct ToolDefinition: Sendable, Codable {

    public struct Parameter: Sendable, Codable {
        public let name: String
        public let description: String
        public let type: String
        public let required: Bool

        public init(name: String, description: String, type: String, required: Bool) {
            self.name = name
            self.description = description
            self.type = type
            self.required = required
        }
    }

    public let name: String
    public let description: String
    public let parameters: [Parameter]
    public let type: ToolType
   
    
    public init(name: String, description: String, parameters: [Parameter], type: ToolType) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.type = type
    }
    
    public enum ToolType: String, Codable, Sendable {
        case a2aAgent = "a2a_agent"
        case mcpTool = "mcp_tool"
        case function = "function"
    }
}

/// Simple tool manager that coordinates multiple providers
public struct ToolManager: Sendable {
    private let providers: [ToolProvider]
    
    public init(providers: [ToolProvider] = []) {
        self.providers = providers
    }
    
    public func allToolsAsync() async -> [ToolDefinition] {
        var allTools: [ToolDefinition] = []
        for provider in providers {
            allTools.append(contentsOf: await provider.availableTools())
        }
        return allTools
    }
    
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        for provider in providers {
            do {
                let result = try await provider.executeTool(toolCall)
                if result.success {
                    return result
                }
            } catch {
                // Continue to next provider
                continue
            }
        }
        
        return ToolResult(
            success: false,
            content: "",
            error: "Tool '\(toolCall.name)' not found in any provider"
        )
    }
    
    public func addProvider(_ provider: ToolProvider) -> ToolManager {
        ToolManager(providers: providers + [provider])
    }
} 
