import Foundation
import Logging
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

    @Test("ToolManager registerReadOnlyTool creates canonical descriptor with metadata")
    func testToolManagerRegisterReadOnlyToolDescriptor() async {
        let definition = ToolDefinition(
            name: "list_projects",
            description: "List projects",
            parameters: [
                .init(name: "limit", description: "Max rows", type: "integer", required: false)
            ],
            type: .function
        )
        let manager = ToolManager()
            .registerReadOnlyTool(
                definition: definition,
                source: .local,
                parallelHint: .parallelizable,
                policyTags: [.requiresApproval]
            )
        let descriptors = await manager.allRegisteredToolsAsync()
        #expect(descriptors.count == 1)
        guard let descriptor = descriptors.first else {
            Issue.record("expected one descriptor")
            return
        }
        #expect(descriptor.definition.name == "list_projects")
        #expect(descriptor.source == .local)
        #expect(descriptor.effectClass == .readOnly)
        #expect(descriptor.parallelHint == .parallelizable)
        #expect(descriptor.policyTags.contains(.requiresApproval))
        #expect(!descriptor.normalizedSchemaFingerprint.isEmpty)
        #expect(descriptor.schemaSummary.topLevelType == "object")
    }

    @Test("ToolSchemaNormalizer fingerprint is deterministic across key order")
    func testToolSchemaNormalizerDeterministicFingerprint() throws {
        let normalizer = ToolSchemaNormalizer()
        let schemaA: JSON = .object([
            "type": .string("object"),
            "required": .array([.string("b"), .string("a")]),
            "properties": .object([
                "a": .object(["type": .string("string")]),
                "b": .object(["type": .array([.string("string"), .string("null")])])
            ])
        ])
        let schemaB: JSON = .object([
            "properties": .object([
                "b": .object(["type": .array([.string("null"), .string("string")])]),
                "a": .object(["type": .string("string")])
            ]),
            "required": .array([.string("a"), .string("b")]),
            "type": .string("object")
        ])
        let normalizedA = normalizer.normalize(rawSchema: schemaA, source: .local)
        let normalizedB = normalizer.normalize(rawSchema: schemaB, source: .local)
        #expect(normalizedA.fingerprint == normalizedB.fingerprint)
        #expect(normalizedA.summary.requiredCount == 2)
        #expect(normalizedA.report.warnings.contains(where: { $0.contains("nullable") }))
    }

    @Test("allToolsAsync includes canonical registered descriptors")
    func testAllToolsIncludesRegisteredDescriptors() async throws {
        let def = ToolDefinition(
            name: "registered_tool",
            description: "Registered",
            parameters: [],
            type: .function
        )
        let manager = ToolManager().registerLocalTool(definition: def)
        let tools = await manager.allToolsAsync()
        #expect(tools.contains(where: { $0.name == "registered_tool" }))
    }

    @Test("strict descriptor validation rejects incomplete descriptor metadata")
    func testStrictDescriptorValidationRejectsIncompleteDescriptor() async throws {
        let def = ToolDefinition(
            name: "incomplete_descriptor_tool",
            description: "Incomplete metadata tool",
            parameters: [],
            type: .function
        )
        let manager = ToolManager(descriptorValidationMode: .strict).registerTool(
            definition: def,
            source: .local,
            effectClass: .unknown,
            parallelHint: .unknown,
            policyTags: []
        )
        let descriptors = await manager.allRegisteredToolsAsync()
        #expect(descriptors.isEmpty)
    }

    @Test("warning descriptor validation allows incomplete descriptor metadata")
    func testWarningDescriptorValidationAllowsIncompleteDescriptor() async throws {
        let def = ToolDefinition(
            name: "warning_descriptor_tool",
            description: "Warning metadata tool",
            parameters: [],
            type: .function
        )
        let manager = ToolManager(descriptorValidationMode: .warning).registerTool(
            definition: def,
            source: .local,
            effectClass: .unknown,
            parallelHint: .unknown,
            policyTags: []
        )
        let descriptors = await manager.allRegisteredToolsAsync()
        #expect(descriptors.count == 1)
        #expect(descriptors.first?.definition.name == "warning_descriptor_tool")
    }

    @Test("ForwardingToolProvider forwards descriptor metadata methods")
    func testForwardingToolProviderMetadataForwarding() async throws {
        let provider = MetadataProvider(toolName: "forwarded_tool")
        let wrapped = ForwardingToolProvider(inner: provider)

        let tools = await wrapped.availableTools()
        let tool = try #require(tools.first)

        #expect(await wrapped.registrationSource(for: tool) == .mcp)
        #expect(await wrapped.effectClass(for: tool) == .readOnly)
        #expect(await wrapped.executionParallelHint(for: tool) == .parallelizable)
        #expect(await wrapped.policyTags(for: tool) == [.requiresApproval])
        let wrappedSchema = try #require(await wrapped.rawSchema(for: tool))
        #expect(String(describing: wrappedSchema) == String(describing: provider.schema))
        #expect(await wrapped.parallelSafety(for: ToolCall(name: "forwarded_tool", arguments: .object([:]), id: "fwd")) == .parallelSafe)
    }

    @Test("ToolDescriptorHinting supplies metadata defaults through ToolProvider extension")
    func testToolDescriptorHintingDefaults() async throws {
        let provider = HintingProvider()
        let tool = try #require(await provider.availableTools().first)

        #expect(await provider.effectClass(for: tool) == .readOnly)
        #expect(await provider.executionParallelHint(for: tool) == .parallelizable)
        #expect(await provider.policyTags(for: tool) == [.sensitive])
        #expect(await provider.parallelSafety(for: ToolCall(name: tool.name, arguments: .object([:]), id: "hint")) == .parallelSafe)
    }

    @Test("warning descriptor validation deduplicates repeated warnings")
    func testWarningDescriptorValidationDeduplicatesWarnings() async throws {
        let recorder = TestLogRecorder()
        let logger = Logger(label: "ToolManagerWarningDedup") { _ in
            TestCapturingLogHandler(recorder: recorder)
        }
        let toolName = "warning-dedup-\(UUID().uuidString)"
        let definition = ToolDefinition(
            name: toolName,
            description: "Warning dedup tool",
            parameters: [],
            type: .function
        )

        let manager = ToolManager(
            descriptorValidationMode: .warning,
            logger: logger
        ).registerTool(
            definition: definition,
            source: .local,
            effectClass: .unknown,
            parallelHint: .unknown,
            policyTags: []
        )

        _ = await manager.allRegisteredToolsAsync()
        _ = await manager.allRegisteredToolsAsync()

        let warnings = recorder.records(level: .warning, containing: "Descriptor validation warning")
            .filter { $0.metadata["toolName"] == .string(toolName) }
        #expect(warnings.count == 1)
    }

    @Test("strict descriptor validation rejects invalid metadata and logs errors")
    func testStrictDescriptorValidationLogsAndRejects() async throws {
        let recorder = TestLogRecorder()
        let logger = Logger(label: "ToolManagerStrictValidation") { _ in
            TestCapturingLogHandler(recorder: recorder)
        }
        let toolName = "strict-log-\(UUID().uuidString)"
        let definition = ToolDefinition(
            name: toolName,
            description: "Strict descriptor test tool",
            parameters: [],
            type: .function
        )

        let manager = ToolManager(
            descriptorValidationMode: .strict,
            logger: logger
        ).registerTool(
            definition: definition,
            source: .local,
            effectClass: .unknown,
            parallelHint: .unknown,
            policyTags: []
        )

        let descriptors = await manager.allRegisteredToolsAsync()
        #expect(descriptors.isEmpty)

        let errors = recorder.records(level: .error, containing: "Descriptor validation error; tool descriptor rejected")
            .filter { $0.metadata["toolName"] == .string(toolName) }
        #expect(errors.count >= 1)
    }
}

private struct MetadataProvider: ToolProvider {
    let toolName: String
    let schema: JSON = .object(["type": .string("object"), "properties": .object([:])])

    var name: String { "MetadataProvider" }

    func availableTools() async -> [ToolDefinition] {
        [
            ToolDefinition(
                name: toolName,
                description: "Metadata provider tool",
                parameters: [],
                type: .function
            )
        ]
    }

    func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        ToolResult(success: true, content: "ok", toolCallId: toolCall.id)
    }

    func registrationSource(for definition: ToolDefinition) async -> ToolRegistrationSource { .mcp }
    func effectClass(for definition: ToolDefinition) async -> ToolEffectClass { .readOnly }
    func executionParallelHint(for definition: ToolDefinition) async -> ToolExecutionParallelHint { .parallelizable }
    func policyTags(for definition: ToolDefinition) async -> [ToolPolicyTag] { [.requiresApproval] }
    func rawSchema(for definition: ToolDefinition) async -> JSON? { schema }
    func parallelSafety(for toolCall: ToolCall) async -> ToolParallelSafety { .parallelSafe }
}

private struct HintingProvider: ToolProvider, ToolDescriptorHinting {
    var name: String { "HintingProvider" }

    var descriptorHintsByToolName: [String : ToolDescriptorHints] {
        [
            "hinted_tool": ToolDescriptorHints(
                effectClass: .readOnly,
                parallelHint: .parallelizable,
                policyTags: [.sensitive]
            )
        ]
    }

    func availableTools() async -> [ToolDefinition] {
        [
            ToolDefinition(
                name: "hinted_tool",
                description: "Hinted metadata tool",
                parameters: [],
                type: .function
            )
        ]
    }

    func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        ToolResult(success: true, content: "ok", toolCallId: toolCall.id)
    }
}

private struct TestLogRecord: Sendable {
    let level: Logger.Level
    let message: String
    let metadata: Logger.Metadata
}

private final class TestLogRecorder {
    private let lock = NSLock()
    private var allRecords: [TestLogRecord] = []

    func append(_ record: TestLogRecord) {
        lock.lock()
        defer { lock.unlock() }
        allRecords.append(record)
    }

    func records(level: Logger.Level, containing text: String) -> [TestLogRecord] {
        lock.lock()
        defer { lock.unlock() }
        return allRecords.filter { $0.level == level && $0.message.contains(text) }
    }
}

extension TestLogRecorder: @unchecked Sendable {}

private struct TestCapturingLogHandler: LogHandler {
    private let recorder: TestLogRecorder
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace

    init(recorder: TestLogRecorder) {
        self.recorder = recorder
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata additionalMetadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        var combined = metadata
        if let additionalMetadata {
            for (key, value) in additionalMetadata {
                combined[key] = value
            }
        }
        recorder.append(TestLogRecord(level: level, message: message.description, metadata: combined))
    }
}
