import Foundation
import Testing
import SwiftAgentKit
import EasyJSON

@Suite struct LocalFunctionToolProviderTests {
    
    struct RemoteFunctionProvider: ToolProvider {
        let toolName: String
        let resultContent: String
        
        var name: String { "RemoteFunctionProvider" }
        
        func availableTools() async -> [ToolDefinition] {
            [
                ToolDefinition(
                    name: toolName,
                    description: "Remote tool",
                    parameters: [],
                    type: .mcpTool
                )
            ]
        }
        
        func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
            guard toolCall.name == toolName else {
                return ToolResult(success: false, content: "", toolCallId: toolCall.id, error: "Unknown tool")
            }
            return ToolResult(success: true, content: resultContent, toolCallId: toolCall.id)
        }
    }
    
    @Test("LocalFunctionToolProvider passes EasyJSON arguments to executor")
    func testLocalFunctionProviderUsesEasyJSONArguments() async throws {
        let functionName = "sum_values"
        let expectedArguments: JSON = .object([
            "a": .integer(2),
            "b": .integer(4),
            "options": .object(["round": .boolean(true)])
        ])
        
        actor Capture {
            var toolName: String?
            var arguments: JSON?
            var toolCallId: String?
            
            func set(toolName: String, arguments: JSON, toolCallId: String?) {
                self.toolName = toolName
                self.arguments = arguments
                self.toolCallId = toolCallId
            }
        }
        
        let capture = Capture()
        let provider = LocalFunctionToolProvider(
            config: LocalFunctionToolsConfig(functions: [
                LocalFunctionDefinition(name: functionName, description: "Sums two values")
            ])
        ) { toolName, arguments, toolCallId in
            await capture.set(toolName: toolName, arguments: arguments, toolCallId: toolCallId)
            return ToolResult(success: true, content: "6", toolCallId: toolCallId)
        }
        
        let toolCall = ToolCall(name: functionName, arguments: expectedArguments, id: "call_local_1")
        let result = try await provider.executeTool(toolCall)
        
        #expect(result.success == true)
        #expect(result.content == "6")
        #expect(result.toolCallId == "call_local_1")
        #expect(await capture.toolName == functionName)
        if case .object(let capturedDict) = await capture.arguments,
           case .object(let expectedDict) = expectedArguments {
            #expect(capturedDict.count == expectedDict.count)
            if case .integer(let a) = capturedDict["a"], case .integer(let b) = expectedDict["a"] {
                #expect(a == b)
            } else {
                #expect(Bool(false), "Expected integer argument 'a'")
            }
            if case .integer(let a) = capturedDict["b"], case .integer(let b) = expectedDict["b"] {
                #expect(a == b)
            } else {
                #expect(Bool(false), "Expected integer argument 'b'")
            }
            if case .object(let capturedOptions) = capturedDict["options"],
               case .object(let expectedOptions) = expectedDict["options"],
               case .boolean(let capturedRound) = capturedOptions["round"],
               case .boolean(let expectedRound) = expectedOptions["round"] {
                #expect(capturedRound == expectedRound)
            } else {
                #expect(Bool(false), "Expected object argument 'options.round'")
            }
        } else {
            #expect(Bool(false), "Expected object arguments")
        }
        #expect(await capture.toolCallId == "call_local_1")
    }
    
    @Test("ToolManager prefers local function on name collision")
    func testToolManagerPrefersLocalFunctionOnCollision() async throws {
        let sharedToolName = "search"
        let localProvider = LocalFunctionToolProvider(
            config: LocalFunctionToolsConfig(functions: [
                LocalFunctionDefinition(name: sharedToolName, description: "Local search")
            ])
        ) { _, _, toolCallId in
            ToolResult(success: true, content: "local-result", toolCallId: toolCallId)
        }
        
        let remoteProvider = RemoteFunctionProvider(toolName: sharedToolName, resultContent: "remote-result")
        let manager = ToolManager(providers: [remoteProvider, localProvider])
        
        let tools = await manager.allToolsAsync()
        #expect(tools.count == 1)
        #expect(tools.first?.name == sharedToolName)
        #expect(tools.first?.type == .function)
        
        let result = try await manager.executeTool(ToolCall(name: sharedToolName, arguments: .object([:]), id: "call_1"))
        #expect(result.success == true)
        #expect(result.content == "local-result")
        #expect(result.toolCallId == "call_1")
    }
    
    @Test("Local function provider reports execution failures for LLM replanning")
    func testLocalFunctionProviderFailureIncludesActionableError() async throws {
        let provider = LocalFunctionToolProvider(
            config: LocalFunctionToolsConfig(functions: [
                LocalFunctionDefinition(name: "get_weather", description: "Weather lookup")
            ])
        ) { _, _, _ in
            struct LocalFailure: Error, CustomStringConvertible {
                var description: String { "upstream API unavailable" }
            }
            throw LocalFailure()
        }
        
        let result = try await provider.executeTool(
            ToolCall(name: "get_weather", arguments: .object(["city": .string("Austin")]), id: "call_weather_1")
        )
        
        #expect(result.success == false)
        #expect(result.toolCallId == "call_weather_1")
        #expect(result.error?.contains("Try a different tool or approach.") == true)
    }
    
    // MARK: - ToolManager execution semantics
    
    struct FixedResultToolProvider: ToolProvider {
        let toolName: String
        let result: ToolResult
        
        var name: String { "FixedResultToolProvider" }
        
        func availableTools() async -> [ToolDefinition] {
            [
                ToolDefinition(
                    name: toolName,
                    description: "test",
                    parameters: [],
                    type: .function
                )
            ]
        }
        
        func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
            result
        }
    }
    
    struct ThrowingToolProvider: ToolProvider {
        let toolName: String
        
        struct TestError: Error, Equatable {}
        
        var name: String { "ThrowingToolProvider" }
        
        func availableTools() async -> [ToolDefinition] {
            [
                ToolDefinition(
                    name: toolName,
                    description: "test",
                    parameters: [],
                    type: .function
                )
            ]
        }
        
        func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
            throw TestError()
        }
    }
    
    @Test("ToolManager returns provider failure when exactly one provider lists the tool and returns success false")
    func testToolManagerPropagatesSingleProviderFailure() async throws {
        let expectedError = "validation failed"
        let provider = FixedResultToolProvider(
            toolName: "foo",
            result: ToolResult(success: false, content: "", toolCallId: "c1", error: expectedError)
        )
        let manager = ToolManager(providers: [provider])
        let result = try await manager.executeTool(
            ToolCall(name: "foo", arguments: .object([:]), id: "c1")
        )
        #expect(result.success == false)
        #expect(result.error == expectedError)
    }
    
    @Test("ToolManager propagates throw when exactly one provider lists the tool")
    func testToolManagerPropagatesSingleProviderThrow() async throws {
        let provider = ThrowingToolProvider(toolName: "foo")
        let manager = ToolManager(providers: [provider])
        await #expect(throws: ThrowingToolProvider.TestError.self) {
            try await manager.executeTool(ToolCall(name: "foo", arguments: .object([:]), id: "c1"))
        }
    }
    
    @Test("ToolManager tries next provider when first returns success false and second succeeds")
    func testToolManagerFallbackOnFailureUntilSuccess() async throws {
        let first = FixedResultToolProvider(
            toolName: "foo",
            result: ToolResult(success: false, content: "", toolCallId: "c1", error: "first failed")
        )
        let second = FixedResultToolProvider(
            toolName: "foo",
            result: ToolResult(success: true, content: "ok", toolCallId: "c1", error: nil)
        )
        let manager = ToolManager(providers: [first, second])
        let result = try await manager.executeTool(
            ToolCall(name: "foo", arguments: .object([:]), id: "c1")
        )
        #expect(result.success == true)
        #expect(result.content == "ok")
    }
    
    @Test("ToolManager returns last failure when multiple providers list the tool and all return success false")
    func testToolManagerReturnsLastFailureWhenAllFail() async throws {
        let first = FixedResultToolProvider(
            toolName: "foo",
            result: ToolResult(success: false, content: "", toolCallId: "c1", error: "first failed")
        )
        let second = FixedResultToolProvider(
            toolName: "foo",
            result: ToolResult(success: false, content: "", toolCallId: "c1", error: "second failed")
        )
        let manager = ToolManager(providers: [first, second])
        let result = try await manager.executeTool(
            ToolCall(name: "foo", arguments: .object([:]), id: "c1")
        )
        #expect(result.success == false)
        #expect(result.error == "second failed")
    }
    
    @Test("ToolManager reports not found when no provider lists the tool")
    func testToolManagerNotFoundWhenUnlisted() async throws {
        let provider = FixedResultToolProvider(
            toolName: "foo",
            result: ToolResult(success: true, content: "ok", toolCallId: "c1", error: nil)
        )
        let manager = ToolManager(providers: [provider])
        let result = try await manager.executeTool(
            ToolCall(name: "bar", arguments: .object([:]), id: "c1")
        )
        #expect(result.success == false)
        #expect(result.error == "Tool 'bar' not found in any provider")
    }
}
