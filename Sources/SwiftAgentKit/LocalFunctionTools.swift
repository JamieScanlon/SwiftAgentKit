import Foundation
import EasyJSON
import Logging

/// Definition for a local function tool exposed to the LLM.
public struct LocalFunctionDefinition: Sendable, Codable {
    public let name: String
    public let description: String
    public let parameters: [ToolDefinition.Parameter]
    public let metadata: JSON?
    
    public init(
        name: String,
        description: String,
        parameters: [ToolDefinition.Parameter] = [],
        metadata: JSON? = nil
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.metadata = metadata
    }
    
    public var asToolDefinition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: description,
            parameters: parameters,
            type: .function
        )
    }
}

/// Configuration container for local function tools.
public struct LocalFunctionToolsConfig: Sendable, Codable {
    public let functions: [LocalFunctionDefinition]
    
    public init(functions: [LocalFunctionDefinition] = []) {
        self.functions = functions
    }
}

/// Executor contract for local function tools using EasyJSON argument payloads.
public typealias LocalFunctionExecutor = @Sendable (_ toolName: String, _ arguments: JSON, _ toolCallId: String?) async throws -> ToolResult

/// Tool provider for local application-defined function tools.
public struct LocalFunctionToolProvider: ToolProvider {
    public let name: String
    public let config: LocalFunctionToolsConfig
    
    private let executor: LocalFunctionExecutor
    private let logger: Logger
    
    public init(
        name: String = "Local Functions",
        config: LocalFunctionToolsConfig,
        executor: @escaping LocalFunctionExecutor,
        logger: Logger? = nil
    ) {
        self.name = name
        self.config = config
        self.executor = executor
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .core("LocalFunctionToolProvider"),
            metadata: SwiftAgentKitLogging.metadata(
                ("providerName", .string(name)),
                ("functionCount", .stringConvertible(config.functions.count))
            )
        )
    }
    
    public func availableTools() async -> [ToolDefinition] {
        config.functions.map(\.asToolDefinition)
    }
    
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        guard config.functions.contains(where: { $0.name == toolCall.name }) else {
            return ToolResult(
                success: false,
                content: "",
                metadata: .object(["source": .string("local_function")]),
                toolCallId: toolCall.id,
                error: "Local function '\(toolCall.name)' is not configured"
            )
        }
        
        do {
            var result = try await executor(toolCall.name, toolCall.arguments, toolCall.id)
            let mergedMetadata = mergeMetadata(result.metadata)
            result = ToolResult(
                success: result.success,
                content: result.content,
                metadata: mergedMetadata,
                toolCallId: result.toolCallId ?? toolCall.id,
                error: result.error
            )
            return result
        } catch {
            logger.warning(
                "Local function execution failed",
                metadata: SwiftAgentKitLogging.metadata(
                    ("toolName", .string(toolCall.name)),
                    ("toolCallId", .string(toolCall.id ?? "")),
                    ("error", .string(String(describing: error)))
                )
            )
            return ToolResult(
                success: false,
                content: "",
                metadata: .object(["source": .string("local_function")]),
                toolCallId: toolCall.id,
                error: "Local function '\(toolCall.name)' failed: \(error). Try a different tool or approach."
            )
        }
    }
    
    private func mergeMetadata(_ metadata: JSON) -> JSON {
        guard case .object(let existing) = metadata else {
            return .object(["source": .string("local_function")])
        }
        var merged = existing
        merged["source"] = .string("local_function")
        return .object(merged)
    }
}
