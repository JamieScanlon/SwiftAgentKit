import Foundation
import EasyJSON
import Logging

private struct NormalizationDiagnosticFingerprint: Hashable {
    let toolName: String
    let source: ToolRegistrationSource
    let code: String
}

private enum NormalizationDiagnosticDeduper {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seenFingerprints: Set<NormalizationDiagnosticFingerprint> = []

    static func shouldLog(_ fingerprint: NormalizationDiagnosticFingerprint) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return seenFingerprints.insert(fingerprint).inserted
    }
}

private struct DescriptorValidationWarningFingerprint: Hashable {
    let toolName: String
    let source: ToolRegistrationSource
    let issues: [String]
}

private enum DescriptorValidationWarningDeduper {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seenFingerprints: Set<DescriptorValidationWarningFingerprint> = []

    static func shouldLog(_ fingerprint: DescriptorValidationWarningFingerprint) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let inserted = seenFingerprints.insert(fingerprint).inserted
        return inserted
    }
}

public enum ToolDescriptorValidationMode: String, Sendable, Codable, Equatable {
    case warning
    case strict
}

/// An image returned by a tool, either inline (`data`) or by reference (`url`) for the host to resolve.
public struct ToolResultImage: Sendable, Codable, Equatable {
    /// Inline image bytes (not base64).
    public var data: Data?
    /// A reference the host resolves instead of inline bytes (file, blob, or remote URL).
    public var url: URL?
    /// IANA media type, e.g. `image/png`, `image/jpeg`, `image/webp`, `image/gif`.
    public var mediaType: String
    public var width: Int?
    public var height: Int?

    public init(data: Data? = nil, url: URL? = nil, mediaType: String, width: Int? = nil, height: Int? = nil) {
        self.data = data
        self.url = url
        self.mediaType = mediaType
        self.width = width
        self.height = height
    }
}

/// One typed piece of a tool result, kept in the order the tool produced it.
public enum ToolResultContentPart: Sendable, Codable, Equatable {
    case text(String)
    case image(ToolResultImage)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case image
    }

    private enum Kind: String, Codable {
        case text
        case image
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .image:
            self = .image(try container.decode(ToolResultImage.self, forKey: .image))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let image):
            try container.encode(Kind.image, forKey: .type)
            try container.encode(image, forKey: .image)
        }
    }
}

/// Result of a tool execution
public struct ToolResult: Sendable, Equatable, Codable {
    public let success: Bool
    /// Text of the result. When built from ``parts``, the text parts joined with newlines; never contains image data.
    public let content: String
    public let metadata: JSON
    public let toolCallId: String?
    public let error: String?
    /// Ordered typed content. Empty for text-only results built with ``init(success:content:metadata:toolCallId:error:)``.
    public let parts: [ToolResultContentPart]

    private enum CodingKeys: String, CodingKey {
        case success
        case content
        case metadata
        case toolCallId
        case error
        case parts
    }
    
    public init(success: Bool, content: String, metadata: JSON = .object([:]), toolCallId: String?, error: String? = nil) {
        self.success = success
        self.content = content
        self.metadata = metadata
        self.toolCallId = toolCallId
        self.error = error
        self.parts = []
    }

    /// Builds a result from ordered typed parts; ``content`` is the text parts joined with `textSeparator`.
    public init(success: Bool, parts: [ToolResultContentPart], metadata: JSON = .object([:]), toolCallId: String?, error: String? = nil, textSeparator: String = "\n") {
        self.success = success
        self.content = parts.compactMap { part in
            if case .text(let text) = part { return text } else { return nil }
        }.joined(separator: textSeparator)
        self.metadata = metadata
        self.toolCallId = toolCallId
        self.error = error
        self.parts = parts
    }

    /// A successful result carrying one image, optionally preceded by a text caption.
    public static func image(
        _ data: Data,
        mediaType: String,
        caption: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        metadata: JSON = .object([:]),
        toolCallId: String?
    ) -> ToolResult {
        var parts: [ToolResultContentPart] = []
        if let caption, !caption.isEmpty {
            parts.append(.text(caption))
        }
        parts.append(.image(ToolResultImage(data: data, mediaType: mediaType, width: width, height: height)))
        return ToolResult(success: true, parts: parts, metadata: metadata, toolCallId: toolCallId)
    }

    /// ``parts`` when present, otherwise ``content`` as a single text part.
    public var contentParts: [ToolResultContentPart] {
        parts.isEmpty ? [.text(content)] : parts
    }

    /// The image parts, in result order.
    public var images: [ToolResultImage] {
        parts.compactMap { part in
            if case .image(let image) = part { return image } else { return nil }
        }
    }

    /// The image parts as ``Message/Image`` values for a `.tool` message, in result order.
    /// Names are `"<toolCallId or tool>-image-<n>"` so they stay unique within the message.
    public var messageImages: [Message.Image] {
        let prefix = toolCallId ?? "tool"
        return images.enumerated().map { index, image in
            Message.Image(toolResultImage: image, name: "\(prefix)-image-\(index + 1)")
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.success = try container.decode(Bool.self, forKey: .success)
        self.content = try container.decode(String.self, forKey: .content)
        self.metadata = try container.decode(JSON.self, forKey: .metadata)
        self.toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
        self.parts = try container.decodeIfPresent([ToolResultContentPart].self, forKey: .parts) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(content, forKey: .content)
        try container.encode(metadata, forKey: .metadata)
        try container.encodeIfPresent(toolCallId, forKey: .toolCallId)
        try container.encodeIfPresent(error, forKey: .error)
        // Omitted when empty so text-only results encode exactly as before `parts` existed.
        if !parts.isEmpty {
            try container.encode(parts, forKey: .parts)
        }
    }

    public static func == (lhs: ToolResult, rhs: ToolResult) -> Bool {
        lhs.success == rhs.success
            && lhs.content == rhs.content
            && lhs.toolCallId == rhs.toolCallId
            && lhs.error == rhs.error
            && lhs.parts == rhs.parts
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
        case acpAgent = "acp_agent"
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
    public let descriptorValidationMode: ToolDescriptorValidationMode
    private let logger: Logger
    private let schemaNormalizer: ToolSchemaNormalizer
    
    public init(
        providers: [ToolProvider] = [],
        registeredTools: [RegisteredToolDescriptor] = [],
        descriptorValidationMode: ToolDescriptorValidationMode = .warning,
        logger: Logger? = nil,
        schemaNormalizer: ToolSchemaNormalizer = ToolSchemaNormalizer()
    ) {
        self.providers = providers
        self.registeredTools = registeredTools
        self.descriptorValidationMode = descriptorValidationMode
        self.schemaNormalizer = schemaNormalizer
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .core("ToolManager"),
            metadata: SwiftAgentKitLogging.metadata(
                ("providerCount", .stringConvertible(providers.count)),
                ("registeredToolCount", .stringConvertible(registeredTools.count))
            )
        )
    }

    public init(
        providers: [ToolProvider],
        registeredTools: [RegisteredToolDescriptor],
        logger: Logger?,
        schemaNormalizer: ToolSchemaNormalizer
    ) {
        self.init(
            providers: providers,
            registeredTools: registeredTools,
            descriptorValidationMode: .warning,
            logger: logger,
            schemaNormalizer: schemaNormalizer
        )
    }
    
    public init(providers: [ToolProvider]) {
        self.init(providers: providers, registeredTools: [], descriptorValidationMode: .warning, logger: nil)
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
                let normalized = schemaNormalizer.normalize(
                    rawSchema: rawSchema,
                    source: source,
                    toolName: tool.name
                )
                for diagnostic in normalized.report.diagnostics {
                    logNormalizationDiagnostic(diagnostic, source: source)
                }
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
        return resolveDescriptorCollisions(validateDescriptors(collected))
    }

    public func register(_ descriptor: RegisteredToolDescriptor) -> ToolManager {
        let validated = validateDescriptors([descriptor])
        guard !validated.isEmpty else {
            return self
        }
        return ToolManager(
            providers: providers,
            registeredTools: registeredTools + validated,
            descriptorValidationMode: descriptorValidationMode,
            logger: logger,
            schemaNormalizer: schemaNormalizer
        )
    }

    public func registerTool(
        definition: ToolDefinition,
        source: ToolRegistrationSource,
        effectClass: ToolEffectClass,
        parallelHint: ToolExecutionParallelHint,
        policyTags: [ToolPolicyTag] = [],
        rawSchema: JSON? = nil,
        targetProviderCapabilities: ToolSchemaTargetProviderCapabilities = .providerSafe
    ) -> ToolManager {
        let schema = rawSchema ?? definition.inferredSchemaJSON
        let normalized = schemaNormalizer.normalize(
            rawSchema: schema,
            source: source,
            toolName: definition.name,
            targetProviderCapabilities: targetProviderCapabilities
        )
        for diagnostic in normalized.report.diagnostics {
            logNormalizationDiagnostic(diagnostic, source: source)
        }
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
        effectClass: ToolEffectClass = .readOnly,
        parallelHint: ToolExecutionParallelHint = .parallelizable,
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
        effectClass: ToolEffectClass = .readOnly,
        parallelHint: ToolExecutionParallelHint = .parallelizable,
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
        effectClass: ToolEffectClass = .readOnly,
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
        effectClass: ToolEffectClass = .mutating,
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
            descriptorValidationMode: descriptorValidationMode,
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

    private func logNormalizationDiagnostic(
        _ diagnostic: ToolSchemaNormalizationDiagnostic,
        source: ToolRegistrationSource
    ) {
        let fingerprint = NormalizationDiagnosticFingerprint(
            toolName: diagnostic.toolName,
            source: source,
            code: diagnostic.code
        )
        guard NormalizationDiagnosticDeduper.shouldLog(fingerprint) else { return }
        let metadata = SwiftAgentKitLogging.metadata(
            ("toolName", .string(diagnostic.toolName)),
            ("source", .string(source.rawValue)),
            ("fieldPath", .string(diagnostic.fieldPath)),
            ("code", .string(diagnostic.code)),
            ("message", .string(diagnostic.message))
        )
        switch diagnostic.severity {
        case .warning:
            logger.warning("Tool schema normalization diagnostic", metadata: metadata)
        case .error:
            logger.error("Tool schema normalization diagnostic", metadata: metadata)
        }
    }

    private func validateDescriptors(_ descriptors: [RegisteredToolDescriptor]) -> [RegisteredToolDescriptor] {
        var accepted: [RegisteredToolDescriptor] = []
        accepted.reserveCapacity(descriptors.count)
        for descriptor in descriptors {
            let validation = descriptor.validateCompleteness()
            if validation.isValid {
                accepted.append(descriptor)
                continue
            }
            let issueText = validation.issues.map { "\($0.field): \($0.message)" }.joined(separator: "; ")
            switch descriptorValidationMode {
            case .warning:
                let normalizedIssues = validation.issues
                    .map { "\($0.field): \($0.message)" }
                    .sorted()
                let fingerprint = DescriptorValidationWarningFingerprint(
                    toolName: descriptor.definition.name,
                    source: descriptor.source,
                    issues: normalizedIssues
                )
                if DescriptorValidationWarningDeduper.shouldLog(fingerprint) {
                    logger.warning(
                        "Descriptor validation warning",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("toolName", .string(descriptor.definition.name)),
                            ("source", .string(descriptor.source.rawValue)),
                            ("issues", .string(issueText))
                        )
                    )
                }
                accepted.append(descriptor)
            case .strict:
                logger.error(
                    "Descriptor validation error; tool descriptor rejected",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("toolName", .string(descriptor.definition.name)),
                        ("source", .string(descriptor.source.rawValue)),
                        ("issues", .string(issueText))
                    )
                )
            }
        }
        return accepted
    }
} 


