import Foundation
import EasyJSON
import Logging

/// Result of a tool execution
public struct ToolResult: Sendable, Equatable, Codable {
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

    public static func == (lhs: ToolResult, rhs: ToolResult) -> Bool {
        lhs.success == rhs.success
            && lhs.content == rhs.content
            && lhs.toolCallId == rhs.toolCallId
            && lhs.error == rhs.error
            && String(describing: lhs.metadata) == String(describing: rhs.metadata)
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
    
    public enum ToolType: String, Codable, Sendable, Equatable {
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
    public let registeredTools: [RegisteredToolDescriptor]
    private let logger: Logger
    private let schemaNormalizer: ToolSchemaNormalizer
    
    public init(
        providers: [ToolProvider] = [],
        registeredTools: [RegisteredToolDescriptor] = [],
        logger: Logger? = nil,
        schemaNormalizer: ToolSchemaNormalizer = ToolSchemaNormalizer()
    ) {
        self.providers = providers
        self.registeredTools = registeredTools
        self.schemaNormalizer = schemaNormalizer
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .core("ToolManager"),
            metadata: SwiftAgentKitLogging.metadata(
                ("providerCount", .stringConvertible(providers.count)),
                ("registeredToolCount", .stringConvertible(registeredTools.count))
            )
        )
    }
    
    public init(providers: [ToolProvider]) {
        self.init(providers: providers, registeredTools: [], logger: nil)
    }
    
    public func allToolsAsync() async -> [ToolDefinition] {
        let descriptors = await allRegisteredToolsAsync()
        var chosenToolsByName: [String: ToolDefinition] = [:]
        var chosenProviderByToolName: [String: String] = [:]
        var chosenIsLocalByToolName: [String: Bool] = [:]
        for descriptor in descriptors {
            let tool = descriptor.definition
            let source = descriptor.source
            let providerIsLocal = source == .local
            if chosenToolsByName[tool.name] != nil {
                let existingIsLocal = chosenIsLocalByToolName[tool.name] ?? false
                let incomingIsLocal = providerIsLocal
                if incomingIsLocal && !existingIsLocal {
                    logCollision(
                        toolName: tool.name,
                        winnerProvider: source.rawValue,
                        overshadowedProvider: chosenProviderByToolName[tool.name] ?? "unknown"
                    )
                    chosenToolsByName[tool.name] = tool
                    chosenProviderByToolName[tool.name] = source.rawValue
                    chosenIsLocalByToolName[tool.name] = true
                } else {
                    logCollision(
                        toolName: tool.name,
                        winnerProvider: chosenProviderByToolName[tool.name] ?? "unknown",
                        overshadowedProvider: source.rawValue
                    )
                }
            } else {
                chosenToolsByName[tool.name] = tool
                chosenProviderByToolName[tool.name] = source.rawValue
                chosenIsLocalByToolName[tool.name] = providerIsLocal
            }
        }
        return Array(chosenToolsByName.values)
    }

    /// Canonical registration rows including normalized schema and execution hints.
    public func allRegisteredToolsAsync() async -> [RegisteredToolDescriptor] {
        var collected: [RegisteredToolDescriptor] = registeredTools
        for provider in providers {
            let providerTools = await provider.availableTools()
            for tool in providerTools {
                let source = await provider.registrationSource(for: tool)
                let effect = await provider.effectClass(for: tool)
                let parallelHint = await provider.executionParallelHint(for: tool)
                let tags = await provider.policyTags(for: tool)
                let rawSchema = await provider.rawSchema(for: tool) ?? tool.inferredSchemaJSON
                let normalized = schemaNormalizer.normalize(rawSchema: rawSchema, source: source)
                collected.append(
                    RegisteredToolDescriptor(
                        definition: tool,
                        source: source,
                        effectClass: effect,
                        parallelHint: parallelHint,
                        policyTags: tags,
                        normalizedSchema: normalized
                    )
                )
            }
        }
        return resolveDescriptorCollisions(collected)
    }

    public func register(_ descriptor: RegisteredToolDescriptor) -> ToolManager {
        ToolManager(
            providers: providers,
            registeredTools: registeredTools + [descriptor],
            logger: logger,
            schemaNormalizer: schemaNormalizer
        )
    }

    public func registerTool(
        definition: ToolDefinition,
        source: ToolRegistrationSource,
        effectClass: ToolEffectClass = .unknown,
        parallelHint: ToolExecutionParallelHint = .unknown,
        policyTags: [ToolPolicyTag] = [],
        rawSchema: JSON? = nil,
        targetProviderCapabilities: ToolSchemaTargetProviderCapabilities = .providerSafe
    ) -> ToolManager {
        let schema = rawSchema ?? definition.inferredSchemaJSON
        let normalized = schemaNormalizer.normalize(
            rawSchema: schema,
            source: source,
            targetProviderCapabilities: targetProviderCapabilities
        )
        return register(RegisteredToolDescriptor(
            definition: definition,
            source: source,
            effectClass: effectClass,
            parallelHint: parallelHint,
            policyTags: policyTags,
            normalizedSchema: normalized
        ))
    }

    public func registerLocalTool(
        definition: ToolDefinition,
        effectClass: ToolEffectClass = .unknown,
        parallelHint: ToolExecutionParallelHint = .unknown,
        policyTags: [ToolPolicyTag] = [],
        rawSchema: JSON? = nil
    ) -> ToolManager {
        registerTool(
            definition: definition,
            source: .local,
            effectClass: effectClass,
            parallelHint: parallelHint,
            policyTags: policyTags,
            rawSchema: rawSchema
        )
    }

    public func registerMCPTool(
        definition: ToolDefinition,
        effectClass: ToolEffectClass = .unknown,
        parallelHint: ToolExecutionParallelHint = .unknown,
        policyTags: [ToolPolicyTag] = [],
        rawSchema: JSON? = nil
    ) -> ToolManager {
        registerTool(
            definition: definition,
            source: .mcp,
            effectClass: effectClass,
            parallelHint: parallelHint,
            policyTags: policyTags,
            rawSchema: rawSchema
        )
    }

    public func registerA2ATool(
        definition: ToolDefinition,
        effectClass: ToolEffectClass = .unknown,
        parallelHint: ToolExecutionParallelHint = .serialOnly,
        policyTags: [ToolPolicyTag] = [],
        rawSchema: JSON? = nil
    ) -> ToolManager {
        registerTool(
            definition: definition,
            source: .a2a,
            effectClass: effectClass,
            parallelHint: parallelHint,
            policyTags: policyTags,
            rawSchema: rawSchema
        )
    }

    public func registerReadOnlyTool(
        definition: ToolDefinition,
        source: ToolRegistrationSource = .local,
        parallelHint: ToolExecutionParallelHint = .parallelizable,
        policyTags: [ToolPolicyTag] = [],
        rawSchema: JSON? = nil
    ) -> ToolManager {
        registerTool(
            definition: definition,
            source: source,
            effectClass: .readOnly,
            parallelHint: parallelHint,
            policyTags: policyTags,
            rawSchema: rawSchema
        )
    }

    public func registerMutatingTool(
        definition: ToolDefinition,
        source: ToolRegistrationSource = .local,
        policyTags: [ToolPolicyTag] = [],
        rawSchema: JSON? = nil
    ) -> ToolManager {
        registerTool(
            definition: definition,
            source: source,
            effectClass: .mutating,
            parallelHint: .serialOnly,
            policyTags: policyTags,
            rawSchema: rawSchema
        )
    }

    public func registerDelegatedTool(
        definition: ToolDefinition,
        source: ToolRegistrationSource = .a2a,
        effectClass: ToolEffectClass = .unknown,
        policyTags: [ToolPolicyTag] = [],
        rawSchema: JSON? = nil
    ) -> ToolManager {
        registerTool(
            definition: definition,
            source: source,
            effectClass: effectClass,
            parallelHint: .serialOnly,
            policyTags: policyTags,
            rawSchema: rawSchema
        )
    }

    private func resolveDescriptorCollisions(_ descriptors: [RegisteredToolDescriptor]) -> [RegisteredToolDescriptor] {
        var chosen: [String: RegisteredToolDescriptor] = [:]
        for descriptor in descriptors {
            if let existing = chosen[descriptor.definition.name] {
                let incomingIsLocal = descriptor.source == .local
                let existingIsLocal = existing.source == .local
                if incomingIsLocal && !existingIsLocal {
                    logCollision(
                        toolName: descriptor.definition.name,
                        winnerProvider: descriptor.source.rawValue,
                        overshadowedProvider: existing.source.rawValue
                    )
                    chosen[descriptor.definition.name] = descriptor
                } else {
                    logCollision(
                        toolName: descriptor.definition.name,
                        winnerProvider: existing.source.rawValue,
                        overshadowedProvider: descriptor.source.rawValue
                    )
                }
            } else {
                chosen[descriptor.definition.name] = descriptor
            }
        }
        return Array(chosen.values)
    }
    
    /// Dispatches to providers that list `toolCall.name`, in ``prioritizedProviders(for:)`` order (local function providers first).
    /// One matching provider: returns its result (including `success: false`) or rethrows. Several: tries in order until `success: true`;
    /// on repeated failure returns the **last** `ToolResult` with `success: false`. Throws from a candidate are skipped so the next provider may run.
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        let outcome = try await executeToolOutcome(toolCall)
        switch outcome {
        case .completed(let result):
            return result
        case .pending(let handle):
            return ToolResult(
                success: true,
                content: "Tool execution accepted and pending (handle: \(handle.handleID)).",
                metadata: .object(["pendingHandleID": .string(handle.handleID), "status": .string("pending")]),
                toolCallId: toolCall.id
            )
        }
    }

    /// Dispatches to providers and allows providers to return `.pending`.
    public func executeToolOutcome(_ toolCall: ToolCall) async throws -> ToolExecutionOutcome {
        let prioritized = await prioritizedProviders(for: toolCall.name)
        var candidates: [ToolProvider] = []
        candidates.reserveCapacity(prioritized.count)
        for provider in prioritized {
            let available = await provider.availableTools()
            guard available.contains(where: { $0.name == toolCall.name }) else { continue }
            candidates.append(provider)
        }
        
        if candidates.count == 1 {
            return try await candidates[0].executeToolOutcome(toolCall)
        }
        
        var lastHandledFailure: ToolResult?
        for provider in candidates {
            do {
                let outcome = try await provider.executeToolOutcome(toolCall)
                switch outcome {
                case .pending:
                    return outcome
                case .completed(let result):
                    if result.success {
                        return outcome
                    }
                    lastHandledFailure = result
                }
            } catch {
                continue
            }
        }
        
        if let lastHandledFailure {
            return .completed(lastHandledFailure)
        }
        
        return .completed(ToolResult(
            success: false,
            content: "",
            toolCallId: toolCall.id,
            error: "Tool '\(toolCall.name)' not found in any provider"
        ))
    }

    /// Returns best-effort parallel safety metadata for a tool call.
    public func parallelSafety(for toolCall: ToolCall) async -> ToolParallelSafety {
        let prioritized = await prioritizedProviders(for: toolCall.name)
        for provider in prioritized {
            let available = await provider.availableTools()
            guard available.contains(where: { $0.name == toolCall.name }) else { continue }
            return await provider.parallelSafety(for: toolCall)
        }
        return .unknown
    }
    
    public func addProvider(_ provider: ToolProvider) -> ToolManager {
        ToolManager(
            providers: providers + [provider],
            registeredTools: registeredTools,
            logger: logger,
            schemaNormalizer: schemaNormalizer
        )
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


