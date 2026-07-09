import Testing
import SwiftAgentKit
import EasyJSON

@Suite struct ToolSchemaNormalizerV2Tests {
    private let normalizer = ToolSchemaNormalizer()

    @Test("malformed additionalProperties string is repaired with diagnostic")
    func testMalformedAdditionalProperties() {
        let schema: JSON = .object([
            "type": .string("object"),
            "additionalProperties": .string("object"),
            "properties": .object([:])
        ])
        let normalized = normalizer.normalize(
            rawSchema: schema,
            source: .mcp,
            toolName: "web_search"
        )
        guard case .object(let output) = normalized.schema,
              case .boolean(let value) = output["additionalProperties"] else {
            Issue.record("expected boolean additionalProperties")
            return
        }
        #expect(value == false)
        #expect(normalized.report.diagnostics.contains(where: { $0.code == "malformed.additionalProperties" }))
        #expect(normalized.report.warnings.contains(where: { $0.contains("malformed.additionalProperties") }))
    }

    @Test("string-encoded schema node is parsed with diagnostic")
    func testMalformedStringNode() {
        let inner = """
        {"type":"object","properties":{"mode":{"type":"string"}}}
        """
        let schema: JSON = .string(inner)
        let normalized = normalizer.normalize(
            rawSchema: schema,
            source: .local,
            toolName: "nested"
        )
        guard case .object(let output) = normalized.schema,
              case .object = output["properties"] else {
            Issue.record("expected parsed object schema")
            return
        }
        #expect(normalized.report.diagnostics.contains(where: { $0.code == "malformed.stringNode" }))
    }

    @Test("bare object receives empty properties with diagnostic")
    func testMalformedBareObject() {
        let schema: JSON = .object([
            "type": .string("object")
        ])
        let normalized = normalizer.normalize(
            rawSchema: schema,
            source: .local,
            toolName: "bare"
        )
        guard case .object(let output) = normalized.schema,
              case .object(let properties) = output["properties"] else {
            Issue.record("expected properties object")
            return
        }
        #expect(properties.isEmpty)
        #expect(normalized.report.diagnostics.contains(where: { $0.code == "malformed.bareObject" }))
    }

    @Test("anyOf constants collapse to enum")
    func testAnyOfCollapsedToEnum() {
        let schema: JSON = .object([
            "type": .string("string"),
            "anyOf": .array([
                .object(["const": .string("a")]),
                .object(["const": .string("b")])
            ])
        ])
        let normalized = normalizer.normalize(
            rawSchema: schema,
            source: .local,
            toolName: "mode_tool"
        )
        guard case .object(let output) = normalized.schema,
              case .array(let enumValues) = output["enum"] else {
            Issue.record("expected enum array")
            return
        }
        #expect(enumValues.count == 2)
        #expect(output["anyOf"] == nil)
        #expect(normalized.report.diagnostics.contains(where: { $0.code == "union.collapsedToEnum" }))
    }

    @Test("anyOf object branches flatten to first candidate")
    func testAnyOfFirstCandidate() {
        let schema: JSON = .object([
            "anyOf": .array([
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "a": .object(["type": .string("string")])
                    ])
                ]),
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "b": .object(["type": .string("integer")])
                    ])
                ])
            ])
        ])
        let normalized = normalizer.normalize(
            rawSchema: schema,
            source: .local,
            toolName: "branch_tool"
        )
        guard case .object(let output) = normalized.schema,
              case .object(let properties) = output["properties"] else {
            Issue.record("expected first branch properties")
            return
        }
        #expect(properties["a"] != nil)
        #expect(properties["b"] == nil)
        #expect(normalized.report.diagnostics.contains(where: { $0.code == "union.firstCandidate" }))
    }

    @Test("diagnostic logLine format is stable")
    func testDiagnosticLogLineFormat() {
        let diagnostic = ToolSchemaNormalizationDiagnostic(
            toolName: "web_search",
            fieldPath: "parameters.properties.mode",
            code: "union.unsupported",
            message: "anyOf unsupported",
            severity: .error
        )
        #expect(diagnostic.logLine == "tool[web_search].parameters.properties.mode: anyOf unsupported (union.unsupported)")
    }

    @Test("normalizer version is 2")
    func testNormalizerVersion() {
        let schema: JSON = .object([
            "type": .string("object"),
            "properties": .object([:])
        ])
        let normalized = normalizer.normalize(rawSchema: schema, source: .local)
        #expect(normalized.report.normalizedVersion == "2")
        #expect(ToolSchemaNormalizer.currentVersion == "2")
    }

    @Test("list_projects inferred schema normalizes without crash")
    func testListProjectsInferredSchema() {
        let definition = ToolDefinition(
            name: "list_projects",
            description: "List projects",
            parameters: [
                .init(name: "limit", description: "Max rows", type: "integer", required: false)
            ],
            type: .function
        )
        let normalized = normalizer.normalize(
            rawSchema: definition.inferredSchemaJSON,
            source: .local,
            toolName: definition.name
        )
        #expect(!normalized.fingerprint.isEmpty)
    }
}
