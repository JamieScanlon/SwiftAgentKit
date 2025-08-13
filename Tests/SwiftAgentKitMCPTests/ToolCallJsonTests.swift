import Testing
import Foundation
import MCP
@testable import SwiftAgentKitMCP

@Suite struct ToolCallJsonTests {

	@Test("toolCallJson - basic single required string param")
	func testToolCallJsonBasic() throws {
		let tool = Tool(
			name: "test_tool",
			description: "A test tool",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"input": .object([
						"type": .string("string"),
						"description": .string("Input parameter")
					])
				]),
				"required": .array([.string("input")])
			])
		)

		let json = tool.toolCallJson()
		#expect(json["type"] as? String == "function")
		let fn = (json["function"] as? [String: Any]) ?? [:]
		#expect(fn["name"] as? String == "test_tool")
		#expect(fn["description"] as? String == "A test tool")
		let params = (fn["parameters"] as? [String: Any]) ?? [:]
		let properties = (params["properties"] as? [String: Any]) ?? [:]
		let input = (properties["input"] as? [String: Any]) ?? [:]
		#expect(input["type"] as? String == "string")
		#expect(input["description"] as? String == "Input parameter")
		let required = (params["required"] as? [String]) ?? []
		#expect(required == ["input"])
	}

	@Test("toolCallJson - multiple params with subset required")
	func testToolCallJsonMultipleParameters() throws {
		let tool = Tool(
			name: "complex_tool",
			description: "Has multiple params",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"name": .object([
						"type": .string("string"),
						"description": .string("The name parameter")
					]),
					"age": .object([
						"type": .string("integer"),
						"description": .string("The age parameter")
					]),
					"active": .object([
						"type": .string("boolean"),
						"description": .string("Whether active")
					])
				]),
				"required": .array([.string("name"), .string("age")])
			])
		)

		let json = tool.toolCallJson()
		let fn = (json["function"] as? [String: Any]) ?? [:]
		let params = (fn["parameters"] as? [String: Any]) ?? [:]
		let properties = (params["properties"] as? [String: Any]) ?? [:]
		let required = Set(((params["required"] as? [String]) ?? []))
		#expect(required == Set(["name", "age"]))
		#expect(((properties["name"] as? [String: Any])?["type"] as? String) == "string")
		#expect(((properties["age"] as? [String: Any])?["type"] as? String) == "integer")
		#expect(((properties["active"] as? [String: Any])?["type"] as? String) == "boolean")
	}

	@Test("toolCallJson - no required field yields empty required array")
	func testToolCallJsonNoRequired() throws {
		let tool = Tool(
			name: "optional_tool",
			description: "Only optional params",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"opt1": .object([
						"type": .string("string"),
						"description": .string("First optional")
					])
				])
			])
		)

		let json = tool.toolCallJson()
		let fn = (json["function"] as? [String: Any]) ?? [:]
		let params = (fn["parameters"] as? [String: Any]) ?? [:]
		#expect(((params["required"] as? [String]) ?? []).isEmpty == true)
	}

	@Test("toolCallJson - missing properties yields empty properties")
	func testToolCallJsonMissingProperties() throws {
		let tool = Tool(
			name: "no_props_tool",
			description: "No properties",
			inputSchema: .object([
				"type": .string("object")
			])
		)

		let json = tool.toolCallJson()
		let fn = (json["function"] as? [String: Any]) ?? [:]
		let params = (fn["parameters"] as? [String: Any]) ?? [:]
		let properties = (params["properties"] as? [String: Any]) ?? [:]
		#expect(properties.isEmpty == true)
	}

	@Test("toolCallJson - non-object inputSchema yields empty properties and required")
	func testToolCallJsonNonObjectSchema() throws {
		let tool = Tool(
			name: "bad_schema_tool",
			description: "Non-object schema",
			inputSchema: .string("string")
		)

		let json = tool.toolCallJson()
		let fn = (json["function"] as? [String: Any]) ?? [:]
		let params = (fn["parameters"] as? [String: Any]) ?? [:]
		#expect(((params["required"] as? [String]) ?? []).isEmpty == true)
		#expect(((params["properties"] as? [String: Any]) ?? [:]).isEmpty == true)
	}

	@Test("toolCallJson - non-object properties ignored")
	func testToolCallJsonNonObjectProperties() throws {
		let tool = Tool(
			name: "non_object_props_tool",
			description: "properties as string",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .string("not an object")
			])
		)

		let json = tool.toolCallJson()
		let fn = (json["function"] as? [String: Any]) ?? [:]
		let params = (fn["parameters"] as? [String: Any]) ?? [:]
		let properties = (params["properties"] as? [String: Any]) ?? [:]
		#expect(properties.isEmpty == true)
	}

	@Test("toolCallJson - non-object parameter values ignored")
	func testToolCallJsonNonObjectParameterValues() throws {
		let tool = Tool(
			name: "mixed_param_values_tool",
			description: "One valid, one invalid",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"valid": .object([
						"type": .string("string"),
						"description": .string("A valid parameter")
					]),
					"invalid": .string("not an object")
				]),
				"required": .array([.string("valid")])
			])
		)

		let json = tool.toolCallJson()
		let fn = (json["function"] as? [String: Any]) ?? [:]
		let params = (fn["parameters"] as? [String: Any]) ?? [:]
		let properties = (params["properties"] as? [String: Any]) ?? [:]
		#expect(Array(properties.keys).sorted() == ["valid"]) // invalid should be dropped
	}

	@Test("toolCallJson - missing type and description defaults applied")
	func testToolCallJsonMissingTypeAndDescription() throws {
		let tool = Tool(
			name: "incomplete_params_tool",
			description: "Missing fields",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"param1": .object([:]),
					"param2": .object([
						"type": .string("string")
					]),
					"param3": .object([
						"description": .string("Some description")
					])
				])
			])
		)

		let json = tool.toolCallJson()
		let fn = (json["function"] as? [String: Any]) ?? [:]
		let params = (fn["parameters"] as? [String: Any]) ?? [:]
		let properties = (params["properties"] as? [String: Any]) ?? [:]
		let p1 = (properties["param1"] as? [String: Any]) ?? [:]
		let p2 = (properties["param2"] as? [String: Any]) ?? [:]
		let p3 = (properties["param3"] as? [String: Any]) ?? [:]
		#expect(p1["type"] as? String == "string") // default
		#expect(p1["description"] as? String == "")
		#expect(p2["type"] as? String == "string")
		#expect(p2["description"] as? String == "") // default when missing
		#expect(p3["type"] as? String == "string") // default when missing
		#expect(p3["description"] as? String == "Some description")
	}

	@Test("toolCallJson - non-string values in required are ignored")
	func testToolCallJsonNonStringRequiredValues() throws {
		let tool = Tool(
			name: "mixed_required_tool",
			description: "Mixed types in required",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"a": .object(["type": .string("string")]),
					"b": .object(["type": .string("number")])
				]),
				"required": .array([.string("a"), .int(42), .bool(true), .string("b")])
			])
		)

		let json = tool.toolCallJson()
		let fn = (json["function"] as? [String: Any]) ?? [:]
		let params = (fn["parameters"] as? [String: Any]) ?? [:]
		let required = Set(((params["required"] as? [String]) ?? []))
		#expect(required == Set(["a", "b"]))
	}
}


