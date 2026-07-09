import Testing
import MCP
import SwiftAgentKit
@testable import SwiftAgentKitMCP
import EasyJSON

@Suite struct MCPInputSchemaPreservationTests {
    private let complexSchema: JSON = .object([
        "type": .string("object"),
        "additionalProperties": .string("object"),
        "properties": .object([
            "mode": .object([
                "anyOf": .array([
                    .object(["const": .string("fast")]),
                    .object(["const": .string("thorough")])
                ])
            ])
        ])
    ])

    @Test("MCPValueJSONConversion preserves complex inputSchema shape")
    func testValueConversionPreservesShape() {
        let value = MCP.Value.object([
            "type": .string("object"),
            "additionalProperties": .string("object"),
            "properties": .object([
                "mode": .object([
                    "anyOf": .array([
                        .object(["const": .string("fast")]),
                        .object(["const": .string("thorough")])
                    ])
                ])
            ])
        ])
        let json = MCPValueJSONConversion.convert(value)
        guard case .object(let root) = json,
              case .string("object") = root["additionalProperties"] else {
            Issue.record("expected malformed additionalProperties preserved before normalization")
            return
        }
        guard case .object(let properties) = root["properties"],
              case .object(let mode) = properties["mode"],
              case .array = mode["anyOf"] else {
            Issue.record("expected anyOf preserved in mode property")
            return
        }
    }

    @Test("rawInputSchema returns preserved schema while ToolDefinition stays flat")
    func testRawInputSchemaPreservation() async {
        let tool = ToolDefinition(
            name: "search",
            description: "Search",
            parameters: [.init(name: "mode", description: "", type: "string", required: false)],
            type: .mcpTool
        )
        let client = MCPClient(name: "test")
        await client.installToolsForTesting(tools: [tool], inputSchemasByName: ["search": complexSchema])

        let preserved = await client.rawInputSchema(for: "search")
        #expect(preserved != nil)
        guard case .object(let root) = preserved,
              case .object(let properties) = root["properties"],
              case .object(let mode) = properties["mode"],
              case .array = mode["anyOf"] else {
            Issue.record("expected anyOf in preserved schema")
            return
        }

        let flatTools = await client.tools
        #expect(flatTools.count == 1)
        #expect(flatTools[0].parameters.count == 1)
        #expect(flatTools[0].parameters[0].type == "string")
    }

    @Test("malformed MCP schema normalizes with repair when passed to ToolSchemaNormalizer")
    func testPreservedSchemaNormalizedWithRepair() {
        let normalizer = ToolSchemaNormalizer()
        let normalized = normalizer.normalize(
            rawSchema: complexSchema,
            source: .mcp,
            toolName: "search"
        )
        #expect(normalized.report.normalizedVersion == "2")
        #expect(normalized.report.diagnostics.contains(where: { $0.code == "malformed.additionalProperties" }))
        guard case .object(let schema) = normalized.schema,
              case .object(let properties) = schema["properties"],
              case .object(let mode) = properties["mode"],
              case .array(let enumValues) = mode["enum"] else {
            Issue.record("expected mode anyOf collapsed to enum in normalized schema")
            return
        }
        #expect(enumValues.count == 2)
    }
}
