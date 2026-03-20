import Foundation
import EasyJSON
import Logging

/// Result of a tool execution
public struct ToolResult: Sendable {
    public let success: Bool
    public let content: String
    public let metadata: JSON
    public let toolCallId: String?
    public let error: String?
    
    public init(success: Bool, content: String, metadata: JSON = .object([:]), toolCallId: String?, error: String? = nil) {
        self.success = success
        self.content = content
        self.metadata = metadata
        self.toolCallId = toolCallId
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
    
    public func toolCallJson() -> [String: Any] {
        var returnValue: [String: Any] = ["type": "function"]
        var properties: [String: Any] = [:]
        var required: [String] = []
        
        for parameter in parameters {
            properties[parameter.name] = [
                "type": parameter.type,
                "description": parameter.description
            ]
            if parameter.required {
                required.append(parameter.name)
            }
        }
        
        returnValue["function"] = [
            "name": name,
            "description": description,
            "parameters": [
                "type": "object",
                "properties": properties,
                "required": required,
            ]
        ]
        return returnValue
    }
}

/// Simple tool manager that coordinates multiple providers
public struct ToolManager: Sendable {
    public let providers: [ToolProvider]
    private let logger: Logger
    
    public init(providers: [ToolProvider] = [], logger: Logger? = nil) {
        self.providers = providers
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .core("ToolManager"),
            metadata: SwiftAgentKitLogging.metadata(
                ("providerCount", .stringConvertible(providers.count))
            )
        )
    }
    
    public init(providers: [ToolProvider]) {
        self.init(providers: providers, logger: nil)
    }
    
    public func allToolsAsync() async -> [ToolDefinition] {
        var chosenToolsByName: [String: ToolDefinition] = [:]
        var chosenProviderByToolName: [String: String] = [:]
        var chosenIsLocalByToolName: [String: Bool] = [:]
        for provider in providers {
            let providerTools = await provider.availableTools()
            let providerIsLocal = provider is LocalFunctionToolProvider
            for tool in providerTools {
                if chosenToolsByName[tool.name] != nil {
                    let existingIsLocal = chosenIsLocalByToolName[tool.name] ?? false
                    let incomingIsLocal = providerIsLocal
                    if incomingIsLocal && !existingIsLocal {
                        logCollision(toolName: tool.name, winnerProvider: provider.name, overshadowedProvider: chosenProviderByToolName[tool.name] ?? "unknown")
                        chosenToolsByName[tool.name] = tool
                        chosenProviderByToolName[tool.name] = provider.name
                        chosenIsLocalByToolName[tool.name] = true
                    } else {
                        logCollision(toolName: tool.name, winnerProvider: chosenProviderByToolName[tool.name] ?? "unknown", overshadowedProvider: provider.name)
                    }
                } else {
                    chosenToolsByName[tool.name] = tool
                    chosenProviderByToolName[tool.name] = provider.name
                    chosenIsLocalByToolName[tool.name] = providerIsLocal
                }
            }
        }
        return Array(chosenToolsByName.values)
    }
    
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        let providersByPriority = await prioritizedProviders(for: toolCall.name)
        for provider in providersByPriority {
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
            toolCallId: toolCall.id,
            error: "Tool '\(toolCall.name)' not found in any provider"
        )
    }
    
    public func addProvider(_ provider: ToolProvider) -> ToolManager {
        ToolManager(providers: providers + [provider], logger: logger)
    }
    
    private func prioritizedProviders(for toolName: String) async -> [ToolProvider] {
        var localProviders: [ToolProvider] = []
        var nonLocalProviders: [ToolProvider] = []
        var matchingProviderNames: [String] = []
        
        for provider in providers {
            let available = await provider.availableTools()
            guard available.contains(where: { $0.name == toolName }) else {
                nonLocalProviders.append(provider)
                continue
            }
            matchingProviderNames.append(provider.name)
            if provider is LocalFunctionToolProvider {
                localProviders.append(provider)
            } else {
                nonLocalProviders.append(provider)
            }
        }
        
        if !localProviders.isEmpty && matchingProviderNames.count > 1 {
            let localProviderNames = Set(localProviders.map(\.name))
            let overshadowed = matchingProviderNames.filter { !localProviderNames.contains($0) }
            logger.warning(
                "Tool name collision detected; preferring local function provider",
                metadata: SwiftAgentKitLogging.metadata(
                    ("toolName", .string(toolName)),
                    ("winnerProvider", .string(localProviders.first?.name ?? "local_function")),
                    ("overshadowedProviders", .array(overshadowed.map { .string($0) }))
                )
            )
        }
        
        return localProviders + nonLocalProviders
    }
    
    private func logCollision(toolName: String, winnerProvider: String, overshadowedProvider: String) {
        logger.warning(
            "Duplicate tool name detected; retaining preferred provider",
            metadata: SwiftAgentKitLogging.metadata(
                ("toolName", .string(toolName)),
                ("winnerProvider", .string(winnerProvider)),
                ("overshadowedProvider", .string(overshadowedProvider))
            )
        )
    }
} 


