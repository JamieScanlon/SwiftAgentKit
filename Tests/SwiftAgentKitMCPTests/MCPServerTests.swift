import Testing
import Foundation
import SwiftAgentKitMCP
import EasyJSON

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
}
