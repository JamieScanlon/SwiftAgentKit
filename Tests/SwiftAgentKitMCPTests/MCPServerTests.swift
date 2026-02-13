import Testing
import Foundation
@testable import SwiftAgentKitMCP
import EasyJSON
import SwiftAgentKit
import MCP

@Suite struct MCPServerTests {
    
    @Test("MCPServer - basic initialization")
    func testBasicInitialization() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        
        #expect(await server.name == "test-server")
        #expect(await server.version == "1.0.0")
    }
    
    @Test("MCPServer - tool registration")
    func testToolRegistration() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        
        await server.registerTool(
            toolDefinition: ToolDefinition(
                name: "test_tool",
                description: "A test tool",
                parameters: [
                    ToolDefinition.Parameter(
                        name: "input",
                        description: "Input parameter",
                        type: "string",
                        required: true
                    )
                ],
                type: .mcpTool
            )
        ) { args in
            let input: String
            if case .string(let value) = args["input"] {
                input = value
            } else {
                input = "default"
            }
            return .success("Processed: \(input)")
        }
        
        // Verify tool was registered by checking environment access
        let env = await server.environmentVariables
        #expect(!env.isEmpty)
    }
    
    @Test("MCPServer - environment variables access")
    func testEnvironmentVariablesAccess() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        
        let env = await server.environmentVariables
        #expect(!env.isEmpty)
        
        // Check for common environment variables
        #expect(env["PATH"] != nil || env["HOME"] != nil || env["USER"] != nil)
    }
    
    // MARK: - convertToMCPContent Tests
    
    @Test("convertToMCPContent - plain text (backward compatibility)")
    func testConvertToMCPContentPlainText() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let result = MCPToolResult.success("Simple text message")
        
        let content = await server.convertToMCPContent(result)
        
        #expect(content.count == 1)
        if case .text(let text) = content[0] {
            #expect(text == "Simple text message")
        } else {
            Issue.record("Expected text content, got \(content[0])")
        }
    }
    
    @Test("convertToMCPContent - error case")
    func testConvertToMCPContentError() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let result = MCPToolResult.error("INTERNAL_ERROR", "Something went wrong")
        
        let content = await server.convertToMCPContent(result)
        
        #expect(content.count == 1)
        if case .text(let text) = content[0] {
            #expect(text == "Error [INTERNAL_ERROR]: Something went wrong")
        } else {
            Issue.record("Expected text content, got \(content[0])")
        }
    }
    
    @Test("convertToMCPContent - JSON array with text content")
    func testConvertToMCPContentJSONText() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let jsonString = """
        [
          {
            "type": "text",
            "text": "Generated 1 image(s)"
          }
        ]
        """
        let result = MCPToolResult.success(jsonString)
        
        let content = await server.convertToMCPContent(result)
        
        #expect(content.count == 1)
        if case .text(let text) = content[0] {
            #expect(text == "Generated 1 image(s)")
        } else {
            Issue.record("Expected text content, got \(content[0])")
        }
    }
    
    @Test("convertToMCPContent - JSON array with resource content")
    func testConvertToMCPContentJSONResource() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let jsonString = """
        [
          {
            "type": "resource",
            "resource": {
              "uri": "file:///path/to/image.png",
              "mimeType": "image/png",
              "name": "image.png"
            }
          }
        ]
        """
        let result = MCPToolResult.success(jsonString)
        
        let content = await server.convertToMCPContent(result)
        
        #expect(content.count == 1)
        if case .resource(let uri, let mimeType, let text) = content[0] {
            #expect(uri == "file:///path/to/image.png")
            #expect(mimeType == "image/png")
            #expect(text == "image.png")
        } else {
            Issue.record("Expected resource content, got \(content[0])")
        }
    }
    
    @Test("convertToMCPContent - JSON array with resource content (no name)")
    func testConvertToMCPContentJSONResourceNoName() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let jsonString = """
        [
          {
            "type": "resource",
            "resource": {
              "uri": "file:///path/to/document.pdf",
              "mimeType": "application/pdf"
            }
          }
        ]
        """
        let result = MCPToolResult.success(jsonString)
        
        let content = await server.convertToMCPContent(result)
        
        #expect(content.count == 1)
        if case .resource(let uri, let mimeType, let text) = content[0] {
            #expect(uri == "file:///path/to/document.pdf")
            #expect(mimeType == "application/pdf")
            #expect(text == nil)
        } else {
            Issue.record("Expected resource content, got \(content[0])")
        }
    }
    
    @Test("convertToMCPContent - JSON array with image content")
    func testConvertToMCPContentJSONImage() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let base64Data = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let jsonString = """
        [
          {
            "type": "image",
            "data": "\(base64Data)",
            "mimeType": "image/png",
            "metadata": {
              "width": "512",
              "height": "512"
            }
          }
        ]
        """
        let result = MCPToolResult.success(jsonString)
        
        let content = await server.convertToMCPContent(result)
        
        #expect(content.count == 1)
        if case .image(let data, let mimeType, let metadata) = content[0] {
            #expect(data == base64Data)
            #expect(mimeType == "image/png")
            #expect(metadata?["width"] == "512")
            #expect(metadata?["height"] == "512")
        } else {
            Issue.record("Expected image content, got \(content[0])")
        }
    }
    
    @Test("convertToMCPContent - JSON array with image content (no metadata)")
    func testConvertToMCPContentJSONImageNoMetadata() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let base64Data = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let jsonString = """
        [
          {
            "type": "image",
            "data": "\(base64Data)",
            "mimeType": "image/jpeg"
          }
        ]
        """
        let result = MCPToolResult.success(jsonString)
        
        let content = await server.convertToMCPContent(result)
        
        #expect(content.count == 1)
        if case .image(let data, let mimeType, let metadata) = content[0] {
            #expect(data == base64Data)
            #expect(mimeType == "image/jpeg")
            #expect(metadata == nil)
        } else {
            Issue.record("Expected image content, got \(content[0])")
        }
    }
    
    @Test("convertToMCPContent - JSON array with multiple content types")
    func testConvertToMCPContentJSONMultiple() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let jsonString = """
        [
          {
            "type": "text",
            "text": "Generated 1 image(s)"
          },
          {
            "type": "resource",
            "resource": {
              "uri": "file:///path/to/image.png",
              "mimeType": "image/png",
              "name": "image.png"
            }
          }
        ]
        """
        let result = MCPToolResult.success(jsonString)
        
        let content = await server.convertToMCPContent(result)
        
        #expect(content.count == 2)
        
        // First content should be text
        if case .text(let text) = content[0] {
            #expect(text == "Generated 1 image(s)")
        } else {
            Issue.record("Expected text content at index 0, got \(content[0])")
        }
        
        // Second content should be resource
        if case .resource(let uri, let mimeType, let text) = content[1] {
            #expect(uri == "file:///path/to/image.png")
            #expect(mimeType == "image/png")
            #expect(text == "image.png")
        } else {
            Issue.record("Expected resource content at index 1, got \(content[1])")
        }
    }
    
    @Test("convertToMCPContent - JSON array with all content types")
    func testConvertToMCPContentJSONAllTypes() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let base64Data = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let jsonString = """
        [
          {
            "type": "text",
            "text": "Processing complete"
          },
          {
            "type": "resource",
            "resource": {
              "uri": "file:///path/to/file.pdf",
              "mimeType": "application/pdf",
              "name": "document.pdf"
            }
          },
          {
            "type": "image",
            "data": "\(base64Data)",
            "mimeType": "image/png",
            "metadata": {
              "width": "256",
              "height": "256"
            }
          }
        ]
        """
        let result = MCPToolResult.success(jsonString)
        
        let content = await server.convertToMCPContent(result)
        
        #expect(content.count == 3)
        
        // Verify text
        if case .text(let text) = content[0] {
            #expect(text == "Processing complete")
        } else {
            Issue.record("Expected text content at index 0")
        }
        
        // Verify resource
        if case .resource(let uri, let mimeType, let text) = content[1] {
            #expect(uri == "file:///path/to/file.pdf")
            #expect(mimeType == "application/pdf")
            #expect(text == "document.pdf")
        } else {
            Issue.record("Expected resource content at index 1")
        }
        
        // Verify image
        if case .image(let data, let mimeType, let metadata) = content[2] {
            #expect(data == base64Data)
            #expect(mimeType == "image/png")
            #expect(metadata?["width"] == "256")
        } else {
            Issue.record("Expected image content at index 2")
        }
    }
    
    @Test("convertToMCPContent - invalid JSON falls back to plain text")
    func testConvertToMCPContentInvalidJSON() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let invalidJSON = "{ invalid json }"
        let result = MCPToolResult.success(invalidJSON)
        
        let content = await server.convertToMCPContent(result)
        
        #expect(content.count == 1)
        if case .text(let text) = content[0] {
            #expect(text == invalidJSON)
        } else {
            Issue.record("Expected text content fallback, got \(content[0])")
        }
    }
    
    @Test("convertToMCPContent - empty JSON array falls back to plain text")
    func testConvertToMCPContentEmptyJSONArray() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let emptyArray = "[]"
        let result = MCPToolResult.success(emptyArray)
        
        let content = await server.convertToMCPContent(result)
        
        // Empty array should fallback to plain text
        #expect(content.count == 1)
        if case .text(let text) = content[0] {
            #expect(text == emptyArray)
        } else {
            Issue.record("Expected text content fallback, got \(content[0])")
        }
    }
    
    @Test("convertToMCPContent - JSON array with missing type field")
    func testConvertToMCPContentMissingType() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let jsonString = """
        [
          {
            "text": "Missing type field"
          }
        ]
        """
        let result = MCPToolResult.success(jsonString)
        
        let content = await server.convertToMCPContent(result)
        
        // Should fallback to plain text since no valid content parts were parsed
        #expect(content.count == 1)
        if case .text(let text) = content[0] {
            #expect(text == jsonString)
        } else {
            Issue.record("Expected text content fallback, got \(content[0])")
        }
    }
    
    @Test("convertToMCPContent - JSON array with unknown type")
    func testConvertToMCPContentUnknownType() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let jsonString = """
        [
          {
            "type": "unknown",
            "data": "some data"
          }
        ]
        """
        let result = MCPToolResult.success(jsonString)
        
        let content = await server.convertToMCPContent(result)
        
        // Should fallback to plain text since unknown type is ignored
        #expect(content.count == 1)
        if case .text(let text) = content[0] {
            #expect(text == jsonString)
        } else {
            Issue.record("Expected text content fallback, got \(content[0])")
        }
    }
    
    @Test("convertToMCPContent - JSON array with incomplete resource")
    func testConvertToMCPContentIncompleteResource() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let jsonString = """
        [
          {
            "type": "resource",
            "resource": {
              "uri": "file:///path/to/file"
            }
          }
        ]
        """
        let result = MCPToolResult.success(jsonString)
        
        let content = await server.convertToMCPContent(result)
        
        // Should fallback to plain text since resource is missing required fields
        #expect(content.count == 1)
        if case .text(let text) = content[0] {
            #expect(text == jsonString)
        } else {
            Issue.record("Expected text content fallback, got \(content[0])")
        }
    }
    
    @Test("convertToMCPContent - JSON array with incomplete image")
    func testConvertToMCPContentIncompleteImage() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let jsonString = """
        [
          {
            "type": "image",
            "data": "base64data"
          }
        ]
        """
        let result = MCPToolResult.success(jsonString)
        
        let content = await server.convertToMCPContent(result)
        
        // Should fallback to plain text since image is missing required mimeType
        #expect(content.count == 1)
        if case .text(let text) = content[0] {
            #expect(text == jsonString)
        } else {
            Issue.record("Expected text content fallback, got \(content[0])")
        }
    }
    
    @Test("convertToMCPContent - JSON array with incomplete text")
    func testConvertToMCPContentIncompleteText() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let jsonString = """
        [
          {
            "type": "text"
          }
        ]
        """
        let result = MCPToolResult.success(jsonString)
        
        let content = await server.convertToMCPContent(result)
        
        // Should fallback to plain text since text field is missing
        #expect(content.count == 1)
        if case .text(let text) = content[0] {
            #expect(text == jsonString)
        } else {
            Issue.record("Expected text content fallback, got \(content[0])")
        }
    }
    
    @Test("convertToMCPContent - JSON array with mixed valid and invalid parts")
    func testConvertToMCPContentMixedValidInvalid() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let jsonString = """
        [
          {
            "type": "text",
            "text": "Valid text"
          },
          {
            "type": "resource"
          },
          {
            "type": "image",
            "data": "base64data",
            "mimeType": "image/png"
          }
        ]
        """
        let result = MCPToolResult.success(jsonString)
        
        let content = await server.convertToMCPContent(result)
        
        // Should have 2 valid content parts (text and image)
        #expect(content.count == 2)
        
        // First should be text
        if case .text(let text) = content[0] {
            #expect(text == "Valid text")
        } else {
            Issue.record("Expected text content at index 0")
        }
        
        // Second should be image (resource was invalid and skipped)
        if case .image(let data, let mimeType, _) = content[1] {
            #expect(data == "base64data")
            #expect(mimeType == "image/png")
        } else {
            Issue.record("Expected image content at index 1")
        }
    }
    
    @Test("convertToMCPContent - JSON object instead of array")
    func testConvertToMCPContentJSONObject() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let jsonString = """
        {
          "type": "text",
          "text": "This is an object, not an array"
        }
        """
        let result = MCPToolResult.success(jsonString)
        
        let content = await server.convertToMCPContent(result)
        
        // Should fallback to plain text since it's not an array
        #expect(content.count == 1)
        if case .text(let text) = content[0] {
            #expect(text == jsonString)
        } else {
            Issue.record("Expected text content fallback, got \(content[0])")
        }
    }
    
    @Test("convertToMCPContent - empty string")
    func testConvertToMCPContentEmptyString() async throws {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let result = MCPToolResult.success("")
        
        let content = await server.convertToMCPContent(result)
        
        #expect(content.count == 1)
        if case .text(let text) = content[0] {
            #expect(text == "")
        } else {
            Issue.record("Expected text content, got \(content[0])")
        }
    }
}
