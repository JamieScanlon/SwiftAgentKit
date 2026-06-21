import Foundation
import CryptoKit
import EasyJSON

public enum ToolRegistrationSource: String, Sendable, Codable, Equatable {
    case local
    case mcp
    case a2a
    case acp
    case unknown
}

public enum ToolEffectClass: String, Sendable, Codable, Equatable {
    case readOnly
    case mutating
    case unknown
}

public enum ToolExecutionParallelHint: String, Sendable, Codable, Equatable {
    case parallelizable
    case serialOnly
    case unknown
}

public struct ToolPolicyTag: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let sensitive = ToolPolicyTag(rawValue: "sensitive")
    public static let requiresApproval = ToolPolicyTag(rawValue: "requiresApproval")
    public static let elevated = ToolPolicyTag(rawValue: "elevated")
}

public struct ToolDescriptorHints: Sendable, Equatable, Codable {
    public let effectClass: ToolEffectClass
    public let parallelHint: ToolExecutionParallelHint
    public let policyTags: [ToolPolicyTag]
    public let parallelSafety: ToolParallelSafety?

    public init(
        effectClass: ToolEffectClass,
        parallelHint: ToolExecutionParallelHint,
        policyTags: [ToolPolicyTag] = [],
        parallelSafety: ToolParallelSafety? = nil
    ) {
        self.effectClass = effectClass
        self.parallelHint = parallelHint
        self.policyTags = policyTags
        self.parallelSafety = parallelSafety
    }
}

public protocol ToolDescriptorHinting: Sendable {
    var descriptorHintsByToolName: [String: ToolDescriptorHints] { get }
}

public struct ToolSchemaSummary: Sendable, Equatable, Codable {
    public let topLevelType: String
    public let requiredCount: Int
    public let propertyCount: Int
    public let schemaHash: String

    public init(topLevelType: String, requiredCount: Int, propertyCount: Int, schemaHash: String) {
        self.topLevelType = topLevelType
        self.requiredCount = requiredCount
        self.propertyCount = propertyCount
        self.schemaHash = schemaHash
    }
}

public struct ToolSchemaNormalizationReport: Sendable, Equatable, Codable {
    public let warnings: [String]
    public let didFallback: Bool
    public let normalizedVersion: String

    public init(warnings: [String], didFallback: Bool, normalizedVersion: String) {
        self.warnings = warnings
        self.didFallback = didFallback
        self.normalizedVersion = normalizedVersion
    }
}

public struct NormalizedToolSchema: Sendable, Codable {
    public let schema: JSON
    public let summary: ToolSchemaSummary
    public let report: ToolSchemaNormalizationReport
    public let fingerprint: String
    public let originalSchema: JSON?

    public init(
        schema: JSON,
        summary: ToolSchemaSummary,
        report: ToolSchemaNormalizationReport,
        fingerprint: String,
        originalSchema: JSON?
    ) {
        self.schema = schema
        self.summary = summary
        self.report = report
        self.fingerprint = fingerprint
        self.originalSchema = originalSchema
    }
}

extension NormalizedToolSchema: Equatable {
    public static func == (lhs: NormalizedToolSchema, rhs: NormalizedToolSchema) -> Bool {
        lhs.fingerprint == rhs.fingerprint
            && lhs.summary == rhs.summary
            && lhs.report == rhs.report
            && lhs.originalSchema?.canonicalJSONString == rhs.originalSchema?.canonicalJSONString
            && lhs.schema.canonicalJSONString == rhs.schema.canonicalJSONString
    }
}

public struct RegisteredToolDescriptor: Sendable, Codable {
    public let definition: ToolDefinition
    public let source: ToolRegistrationSource
    public let effectClass: ToolEffectClass
    public let parallelHint: ToolExecutionParallelHint
    public let policyTags: [ToolPolicyTag]
    public let normalizedSchema: NormalizedToolSchema

    public var normalizedSchemaFingerprint: String { normalizedSchema.fingerprint }
    public var normalizedSchemaVersion: String { normalizedSchema.report.normalizedVersion }
    public var schemaSummary: ToolSchemaSummary { normalizedSchema.summary }

    public init(
        definition: ToolDefinition,
        source: ToolRegistrationSource,
        effectClass: ToolEffectClass,
        parallelHint: ToolExecutionParallelHint,
        policyTags: [ToolPolicyTag],
        normalizedSchema: NormalizedToolSchema
    ) {
        self.definition = definition
        self.source = source
        self.effectClass = effectClass
        self.parallelHint = parallelHint
        self.policyTags = policyTags
        self.normalizedSchema = normalizedSchema
    }
}

public struct ToolDescriptorValidationIssue: Sendable, Equatable, Codable {
    public let field: String
    public let message: String

    public init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}

public struct ToolDescriptorValidationResult: Sendable, Equatable, Codable {
    public let isValid: Bool
    public let issues: [ToolDescriptorValidationIssue]

    public init(isValid: Bool, issues: [ToolDescriptorValidationIssue]) {
        self.isValid = isValid
        self.issues = issues
    }
}

public extension RegisteredToolDescriptor {
    func validateCompleteness() -> ToolDescriptorValidationResult {
        var issues: [ToolDescriptorValidationIssue] = []
        if effectClass == .unknown {
            issues.append(.init(field: "effectClass", message: "effectClass must be explicitly set (readOnly|mutating)."))
        }
        if parallelHint == .unknown {
            issues.append(.init(field: "parallelHint", message: "parallelHint must be explicitly set (parallelizable|serialOnly)."))
        }
        if normalizedSchema.fingerprint.isEmpty {
            issues.append(.init(field: "normalizedSchema.fingerprint", message: "normalized schema fingerprint is required."))
        }
        return ToolDescriptorValidationResult(isValid: issues.isEmpty, issues: issues)
    }

    static func readOnly(
        definition: ToolDefinition,
        source: ToolRegistrationSource = .local,
        parallelHint: ToolExecutionParallelHint = .parallelizable,
        policyTags: [ToolPolicyTag] = [],
        normalizedSchema: NormalizedToolSchema
    ) -> RegisteredToolDescriptor {
        RegisteredToolDescriptor(
            definition: definition,
            source: source,
            effectClass: .readOnly,
            parallelHint: parallelHint,
            policyTags: policyTags,
            normalizedSchema: normalizedSchema
        )
    }

    static func mutating(
        definition: ToolDefinition,
        source: ToolRegistrationSource = .local,
        policyTags: [ToolPolicyTag] = [],
        normalizedSchema: NormalizedToolSchema
    ) -> RegisteredToolDescriptor {
        RegisteredToolDescriptor(
            definition: definition,
            source: source,
            effectClass: .mutating,
            parallelHint: .serialOnly,
            policyTags: policyTags,
            normalizedSchema: normalizedSchema
        )
    }
}

extension RegisteredToolDescriptor: Equatable {
    public static func == (lhs: RegisteredToolDescriptor, rhs: RegisteredToolDescriptor) -> Bool {
        lhs.definition.name == rhs.definition.name
            && lhs.definition.description == rhs.definition.description
            && lhs.definition.type == rhs.definition.type
            && lhs.source == rhs.source
            && lhs.effectClass == rhs.effectClass
            && lhs.parallelHint == rhs.parallelHint
            && lhs.policyTags == rhs.policyTags
            && lhs.normalizedSchema == rhs.normalizedSchema
    }
}

public struct ToolIngestionDiagnostic: Sendable, Equatable, Codable {
    public let toolName: String
    public let source: ToolRegistrationSource
    public let message: String
    public let timestamp: Date

    public init(toolName: String, source: ToolRegistrationSource, message: String, timestamp: Date = Date()) {
        self.toolName = toolName
        self.source = source
        self.message = message
        self.timestamp = timestamp
    }
}

public struct ToolSchemaTargetProviderCapabilities: Sendable, Equatable, Codable {
    public let supportsUnionTypes: Bool
    public let supportsNullableTypeArrays: Bool

    public init(
        supportsUnionTypes: Bool = false,
        supportsNullableTypeArrays: Bool = false
    ) {
        self.supportsUnionTypes = supportsUnionTypes
        self.supportsNullableTypeArrays = supportsNullableTypeArrays
    }

    public static let providerSafe = ToolSchemaTargetProviderCapabilities()
}

public struct ToolSchemaNormalizer: Sendable {
    public static let currentVersion = "1"

    public init() {}

    public func normalize(
        rawSchema: JSON,
        source: ToolRegistrationSource,
        targetProviderCapabilities: ToolSchemaTargetProviderCapabilities = .providerSafe
    ) -> NormalizedToolSchema {
        var warnings: [String] = []
        var didFallback = false

        let normalized = normalizeNode(
            rawSchema,
            warnings: &warnings,
            didFallback: &didFallback,
            targetProviderCapabilities: targetProviderCapabilities
        )
        let canonical = normalized.canonicalizedSchemaJSON
        let canonicalString = canonical.canonicalJSONString
        let fingerprint = Self.sha256Hex(canonicalString)
        let summary = Self.makeSummary(schema: canonical, fingerprint: fingerprint)

        return NormalizedToolSchema(
            schema: canonical,
            summary: summary,
            report: ToolSchemaNormalizationReport(
                warnings: warnings,
                didFallback: didFallback,
                normalizedVersion: Self.currentVersion
            ),
            fingerprint: fingerprint,
            originalSchema: rawSchema
        )
    }

    private func normalizeNode(
        _ node: JSON,
        warnings: inout [String],
        didFallback: inout Bool,
        targetProviderCapabilities: ToolSchemaTargetProviderCapabilities
    ) -> JSON {
        guard case .object(let object) = node else {
            return node
        }
        var output = object

        if let type = object["type"] {
            switch type {
            case .array(let arr):
                let typeStrings = arr.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
                let nonNull = typeStrings.filter { $0 != "null" }
                if typeStrings.contains("null"), !targetProviderCapabilities.supportsNullableTypeArrays {
                    warnings.append("Flattened nullable type array into x-nullable.")
                    output["x-nullable"] = .boolean(true)
                    if let first = nonNull.first {
                        output["type"] = .string(first)
                    } else {
                        output["type"] = .string("string")
                        didFallback = true
                    }
                }
            default:
                break
            }
        }

        if !targetProviderCapabilities.supportsUnionTypes {
            if let oneOf = object["oneOf"] {
                warnings.append("Flattened unsupported oneOf into first candidate.")
                output.removeValue(forKey: "oneOf")
                if case .array(let options) = oneOf, let first = options.first {
                    let firstNormalized = normalizeNode(
                        first,
                        warnings: &warnings,
                        didFallback: &didFallback,
                        targetProviderCapabilities: targetProviderCapabilities
                    )
                    if case .object(let firstObject) = firstNormalized {
                        firstObject.forEach { output[$0.key] = $0.value }
                    }
                } else {
                    output["type"] = .string("string")
                    didFallback = true
                }
            }
            if let anyOf = object["anyOf"] {
                warnings.append("Flattened unsupported anyOf into first candidate.")
                output.removeValue(forKey: "anyOf")
                if case .array(let options) = anyOf, let first = options.first {
                    let firstNormalized = normalizeNode(
                        first,
                        warnings: &warnings,
                        didFallback: &didFallback,
                        targetProviderCapabilities: targetProviderCapabilities
                    )
                    if case .object(let firstObject) = firstNormalized {
                        firstObject.forEach { output[$0.key] = $0.value }
                    }
                } else {
                    output["type"] = .string("string")
                    didFallback = true
                }
            }
        }

        if case .object(let properties) = output["properties"] {
            var normalizedProperties: [String: JSON] = [:]
            for (key, value) in properties {
                normalizedProperties[key] = normalizeNode(
                    value,
                    warnings: &warnings,
                    didFallback: &didFallback,
                    targetProviderCapabilities: targetProviderCapabilities
                )
            }
            output["properties"] = .object(normalizedProperties)
        }

        if case .array(let requiredValues) = output["required"] {
            let requiredStrings = requiredValues.compactMap { value -> String? in
                if case .string(let stringValue) = value { return stringValue }
                return nil
            }
            output["required"] = .array(requiredStrings.sorted().map(JSON.string))
        }
        return .object(output)
    }

    private static func makeSummary(schema: JSON, fingerprint: String) -> ToolSchemaSummary {
        let topLevelType: String
        if case .object(let dict) = schema, case .string(let t) = dict["type"] {
            topLevelType = t
        } else {
            topLevelType = "object"
        }
        let requiredCount: Int
        let propertyCount: Int
        if case .object(let dict) = schema {
            if case .array(let required) = dict["required"] {
                requiredCount = required.count
            } else {
                requiredCount = 0
            }
            if case .object(let properties) = dict["properties"] {
                propertyCount = properties.count
            } else {
                propertyCount = 0
            }
        } else {
            requiredCount = 0
            propertyCount = 0
        }
        return ToolSchemaSummary(
            topLevelType: topLevelType,
            requiredCount: requiredCount,
            propertyCount: propertyCount,
            schemaHash: fingerprint
        )
    }

    private static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public extension ToolDefinition {
    var inferredSchemaJSON: JSON {
        let properties: [String: JSON] = Dictionary(uniqueKeysWithValues: parameters.map { parameter in
            (
                parameter.name,
                .object([
                    "type": .string(parameter.type),
                    "description": .string(parameter.description)
                ])
            )
        })
        let required = parameters.filter(\.required).map(\.name).sorted().map(JSON.string)
        return .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required)
        ])
    }
}

private extension JSON {
    var canonicalizedSchemaJSON: JSON {
        switch self {
        case .boolean, .integer, .double, .string:
            return self
        case .array(let array):
            return .array(array.map { $0.canonicalizedSchemaJSON })
        case .object(let object):
            let sorted = object.keys.sorted()
            var normalized: [String: JSON] = [:]
            for key in sorted {
                normalized[key] = object[key]?.canonicalizedSchemaJSON
            }
            return .object(normalized)
        }
    }

    var canonicalJSONString: String {
        let canonical = canonicalizedSchemaJSON.literalValue
        guard JSONSerialization.isValidJSONObject(canonical),
              let data = try? JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: self)
        }
        return string
    }
}
