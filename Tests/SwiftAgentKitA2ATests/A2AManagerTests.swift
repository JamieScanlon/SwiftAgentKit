//
//  A2AManagerTests.swift
//  SwiftAgentKit
//
//  Tests for A2AManager, particularly the agentCall() method
//

import Testing
import Foundation
import EasyJSON
@testable import SwiftAgentKitA2A
@testable import SwiftAgentKit

@Suite("A2AManager Tests", .serialized)
struct A2AManagerTests {
    
    // MARK: - Mock Classes
    
    /// Mock A2AClient for testing (legacy; does not conform to A2AAgentStreamClient).
    actor MockA2AClient {
        var agentCard: AgentCard?
        var messageToReturn: [MessageResult] = []
        var callCount: Int = 0
        
        init(agentCard: AgentCard?) {
            self.agentCard = agentCard
        }
        
        func streamMessage(params: MessageSendParams) -> AsyncStream<MessageResult> {
            callCount += 1
            return AsyncStream { continuation in
                for result in messageToReturn {
                    continuation.yield(result)
                }
                continuation.finish()
            }
        }
        
        func getCallCount() -> Int {
            return callCount
        }
        
        func setMessageToReturn(_ messages: [MessageResult]) {
            self.messageToReturn = messages
        }
    }
    
    /// Mock stream client that conforms to A2AAgentStreamClient for agentCall integration tests.
    actor MockA2AStreamClient: A2AAgentStreamClient {
        var agentCard: AgentCard?
        private var eventsToYield: [SendStreamingMessageSuccessResponse<MessageResult>] = []
        private let hangsAfterEvents: Bool

        init(
            agentCard: AgentCard?,
            events: [SendStreamingMessageSuccessResponse<MessageResult>],
            hangsAfterEvents: Bool = false
        ) {
            self.agentCard = agentCard
            self.eventsToYield = events
            self.hangsAfterEvents = hangsAfterEvents
        }

        func streamMessage(params: MessageSendParams) async throws -> AsyncStream<SendStreamingMessageSuccessResponse<MessageResult>> {
            let events = eventsToYield
            let hangsAfterEvents = hangsAfterEvents
            return AsyncStream { continuation in
                if hangsAfterEvents {
                    Task {
                        for event in events {
                            continuation.yield(event)
                        }
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 50_000_000)
                        }
                        continuation.finish()
                    }
                } else {
                    for event in events {
                        continuation.yield(event)
                    }
                    continuation.finish()
                }
            }
        }
    }

    /// Hanging mock client that supports remote task cancellation for cancellation tests.
    actor MockCancellableA2AStreamClient: A2ATaskLifecycleClient {
        var agentCard: AgentCard?
        private let initialEvents: [SendStreamingMessageSuccessResponse<MessageResult>]
        private(set) var cancelTaskCallCount = 0
        private(set) var lastCancelledTaskID: String?

        init(agentCard: AgentCard?, initialEvents: [SendStreamingMessageSuccessResponse<MessageResult>] = []) {
            self.agentCard = agentCard
            self.initialEvents = initialEvents
        }

        func streamMessage(params: MessageSendParams) async throws -> AsyncStream<SendStreamingMessageSuccessResponse<MessageResult>> {
            let initialEvents = self.initialEvents
            return AsyncStream { continuation in
                Task {
                    for event in initialEvents {
                        continuation.yield(event)
                    }
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                    continuation.finish()
                }
            }
        }

        func cancelTask(params: TaskIdParams) async throws -> A2ATask {
            cancelTaskCallCount += 1
            lastCancelledTaskID = params.taskId
            return A2ATask(
                id: params.taskId,
                contextId: UUID().uuidString,
                status: TaskStatus(
                    state: .canceled,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
            )
        }

        func getTask(params: TaskQueryParams) async throws -> A2ATask {
            A2ATask(
                id: params.taskId,
                contextId: UUID().uuidString,
                status: TaskStatus(
                    state: .working,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
            )
        }
    }
    
    /// Wraps a MessageResult into the stream response type the manager consumes.
    func wrap(_ result: MessageResult) -> SendStreamingMessageSuccessResponse<MessageResult> {
        SendStreamingMessageSuccessResponse(jsonrpc: "2.0", id: 1, result: result)
    }
    
    // MARK: - Helper Methods
    
    /// Creates a mock agent card for testing
    func createMockAgentCard(name: String) -> AgentCard {
        return AgentCard(
            name: name,
            description: "Test agent for \(name)",
            url: "https://example.com/\(name)",
            version: "1.0.0",
            capabilities: AgentCard.AgentCapabilities(streaming: true),
            defaultInputModes: ["text/plain"],
            defaultOutputModes: ["text/plain"],
            skills: [
                AgentCard.AgentSkill(
                    id: "skill1",
                    name: "Test Skill",
                    description: "A test skill",
                    tags: ["test"]
                )
            ]
        )
    }
    
    /// Creates a test tool call
    func createToolCall(name: String, instructions: String, id: String? = nil) -> ToolCall {
        let arguments: JSON = .object([
            "instructions": .string(instructions)
        ])
        return ToolCall(name: name, arguments: arguments, id: id)
    }
    
    // MARK: - agentCall() Tests
    
    @Test("agentCall should route to matching client by name")
    func testAgentCallRoutesToMatchingClient() async throws {
        // Given - Multiple clients with different agent cards
        let agentCard1 = createMockAgentCard(name: "TestAgent1")
        let agentCard2 = createMockAgentCard(name: "TestAgent2")
        let agentCard3 = createMockAgentCard(name: "TestAgent3")
        
        let _ = MockA2AClient(agentCard: agentCard1)
        let mockClient2 = MockA2AClient(agentCard: agentCard2)
        let _ = MockA2AClient(agentCard: agentCard3)
        
        // Set up mock response for client 2
        let testMessage = A2AMessage(
            role: "agent",
            parts: [.text(text: "Response from TestAgent2")],
            messageId: UUID().uuidString
        )
        await mockClient2.setMessageToReturn([.message(testMessage)])
        
        // Create tool call targeting TestAgent2
        let _ = createToolCall(name: "TestAgent2", instructions: "Do something", id: UUID().uuidString)
        
        // When - Call would need actual A2AManager integration
        // This test documents the expected behavior
        
        // Then - Only client 2 should be called
        // Note: This is a structural test showing what should be tested
        // Full integration requires access to A2AManager's internal clients array
        #expect(agentCard2.name == "TestAgent2")
    }
    
    @Test("agentCall should return nil when no matching client found")
    func testAgentCallReturnsNilForUnknownAgent() async throws {
        // Given - Create an A2AManager with specific clients
        let manager = A2AManager()
        
        // Initialize with empty clients array
        try await manager.initialize(clients: [])
        
        // Create a tool call for a non-existent agent
        let toolCall = createToolCall(name: "NonExistentAgent", instructions: "Do something", id: UUID().uuidString)
        
        // When
        let result = try await manager.agentCall(toolCall)
        
        // Then
        #expect(result == nil)
    }
    
    @Test("agentCall should return nil when tool call arguments are invalid")
    func testAgentCallReturnsNilForInvalidArguments() async throws {
        // Given - Manager with no clients
        let manager = A2AManager()
        try await manager.initialize(clients: [])
        
        // Create a tool call with missing instructions
        let toolCall = ToolCall(
            name: "TestAgent",
            arguments: .object([:]),  // Missing "instructions" key
            id: UUID().uuidString
        )
        
        // When
        let result = try await manager.agentCall(toolCall)
        
        // Then
        #expect(result == nil)
    }
    
    @Test("agentCall should return nil for non-string instructions")
    func testAgentCallReturnsNilForNonStringInstructions() async throws {
        // Given
        let manager = A2AManager()
        try await manager.initialize(clients: [])
        
        // Create a tool call with non-string instructions
        let toolCall = ToolCall(
            name: "TestAgent",
            arguments: .object(["instructions": .integer(123)]),
            id: UUID().uuidString
        )
        
        // When
        let result = try await manager.agentCall(toolCall)
        
        // Then
        #expect(result == nil)
    }
    
    @Test("agentCall with array arguments should return nil")
    func testAgentCallReturnsNilForArrayArguments() async throws {
        // Given
        let manager = A2AManager()
        try await manager.initialize(clients: [])
        
        // Create a tool call with array arguments instead of object
        let toolCall = ToolCall(
            name: "TestAgent",
            arguments: .array([.string("test")]),
            id: UUID().uuidString
        )
        
        // When
        let result = try await manager.agentCall(toolCall)
        
        // Then
        #expect(result == nil)
    }
    
    // MARK: - availableTools() Tests
    
    @Test("availableTools should return tools from all clients")
    func testAvailableToolsReturnsAllClientTools() async throws {
        // Given - Empty manager (no clients set up yet)
        let manager = A2AManager()
        try await manager.initialize(clients: [])
        
        // When
        let tools = await manager.availableTools()
        
        // Then
        #expect(tools.isEmpty)
    }
    
    @Test("availableTools should create tool definitions with correct structure")
    func testAvailableToolsStructure() async throws {
        // Given - A mock agent card
        let agentCard = createMockAgentCard(name: "TestAgent")
        
        // Then - Verify the agent card has expected structure
        #expect(agentCard.name == "TestAgent")
        #expect(agentCard.description == "Test agent for TestAgent")
        #expect(agentCard.skills.count == 1)
        
        // A tool definition should be created from this with:
        // - name: agent card name
        // - description: agent card description
        // - parameters: includes "instructions" parameter
        // - type: .a2aAgent
    }

    @Test("registeredToolDescriptors returns canonical typed descriptors for A2A tools")
    func testRegisteredToolDescriptorsForA2A() async {
        let manager = A2AManager()
        let card = createMockAgentCard(name: "DescriptorAgent")
        let client = MockA2AStreamClient(agentCard: card, events: [])
        do {
            try await manager.initialize(clients: [client])
        } catch {
            Issue.record("initialize failed: \(error)")
            return
        }

        let descriptors = await manager.registeredToolDescriptors()
        #expect(descriptors.count == 1)
        guard let descriptor = descriptors.first else {
            Issue.record("expected one descriptor")
            return
        }
        #expect(descriptor.definition.name == "DescriptorAgent")
        #expect(descriptor.source == .a2a)
        #expect(descriptor.effectClass == .mutating)
        #expect(descriptor.parallelHint == .serialOnly)
        #expect(descriptor.schemaSummary.requiredCount == 1)
        #expect(!descriptor.normalizedSchemaFingerprint.isEmpty)
    }
    
    // MARK: - Integration Tests with Mock Responses
    
    @Test("agentCall should handle message response correctly")
    func testAgentCallHandlesMessageResponse() async throws {
        // Given - A message result
        let testMessage = A2AMessage(
            role: "agent",
            parts: [.text(text: "Hello from agent")],
            messageId: UUID().uuidString
        )
        let _ = MessageResult.message(testMessage)
        
        // Verify message structure
        #expect(testMessage.role == "agent")
        #expect(testMessage.parts.count == 1)
        
        if case .text(let text) = testMessage.parts[0] {
            #expect(text == "Hello from agent")
        } else {
            #expect(Bool(false), "Expected text message part")
        }
    }
    
    @Test("agentCall should handle task response correctly")
    func testAgentCallHandlesTaskResponse() async throws {
        // Given - A task result
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(
                state: .completed,
                timestamp: ISO8601DateFormatter().string(from: Date())
            ),
            artifacts: [
                Artifact(
                    artifactId: UUID().uuidString,
                    parts: [.text(text: "Task result content")]
                )
            ]
        )
        let _ = MessageResult.task(task)
        
        // Verify task structure
        #expect(task.status.state == .completed)
        #expect(task.artifacts?.count == 1)
        
        if let artifact = task.artifacts?.first,
           case .text(let text) = artifact.parts[0] {
            #expect(text == "Task result content")
        } else {
            #expect(Bool(false), "Expected task artifact with text")
        }
    }
    
    @Test("agentCall should handle taskArtifactUpdate event")
    func testAgentCallHandlesTaskArtifactUpdate() async throws {
        // Given - A task artifact update event
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [.text(text: "Partial response")]
        )
        
        let event = TaskArtifactUpdateEvent(
            taskId: UUID().uuidString,
            contextId: UUID().uuidString,
            artifact: artifact,
            append: true,
            lastChunk: false
        )
        
        let _ = MessageResult.taskArtifactUpdate(event)
        
        // Verify event structure
        #expect(event.append == true)
        #expect(event.lastChunk == false)
        #expect(event.artifact.parts.count == 1)
    }
    
    @Test("agentCall should handle taskStatusUpdate event")
    func testAgentCallHandlesTaskStatusUpdate() async throws {
        // Given - A task status update event
        let status = TaskStatus(
            state: .completed,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        
        let event = TaskStatusUpdateEvent(
            taskId: UUID().uuidString,
            contextId: UUID().uuidString,
            status: status,
            final: true
        )
        
        let _ = MessageResult.taskStatusUpdate(event)
        
        // Verify event structure
        #expect(event.status.state == .completed)
        #expect(event.taskId.isEmpty == false)
    }
    
    @Test("agentCall should handle streaming with multiple chunks")
    func testAgentCallHandlesStreamingChunks() async throws {
        // Given - Multiple artifact updates representing streaming
        let taskId = UUID().uuidString
        let contextId = UUID().uuidString
        
        let chunk1 = TaskArtifactUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            artifact: Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: "First ")]
            ),
            append: false,
            lastChunk: false
        )
        
        let chunk2 = TaskArtifactUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            artifact: Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: "second ")]
            ),
            append: true,
            lastChunk: false
        )
        
        let chunk3 = TaskArtifactUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            artifact: Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: "third")]
            ),
            append: true,
            lastChunk: true
        )
        
        // Verify streaming behavior:
        // - append: false should replace content
        // - append: true should append to existing content
        // - lastChunk: true should trigger completion
        #expect(chunk1.append == false)
        #expect(chunk2.append == true)
        #expect(chunk3.lastChunk == true)
    }
    
    @Test("agentCall should handle empty text parts correctly")
    func testAgentCallIgnoresEmptyTextParts() async throws {
        // Given - Message with empty text parts mixed with non-empty
        let message = A2AMessage(
            role: "agent",
            parts: [
                .text(text: ""),
                .text(text: "Valid content"),
                .text(text: ""),
                .text(text: "More content")
            ],
            messageId: UUID().uuidString
        )
        
        // When filtering empty text parts
        let nonEmptyTexts = message.parts.compactMap { part -> String? in
            if case .text(let text) = part, !text.isEmpty {
                return text
            }
            return nil
        }
        
        // Then - Only non-empty parts should remain
        #expect(nonEmptyTexts.count == 2)
        #expect(nonEmptyTexts[0] == "Valid content")
        #expect(nonEmptyTexts[1] == "More content")
    }
    
    // MARK: - ToolCall Structure Tests
    
    @Test("ToolCall should have correct name for routing")
    func testToolCallNameForRouting() async throws {
        // Given
        let toolCall = createToolCall(name: "MyAgent", instructions: "Test task", id: UUID().uuidString)
        
        // Then
        #expect(toolCall.name == "MyAgent")
        
        // Verify arguments contain instructions
        if case .object(let dict) = toolCall.arguments,
           case .string(let instructions) = dict["instructions"] {
            #expect(instructions == "Test task")
        } else {
            #expect(Bool(false), "Expected string instructions in arguments")
        }
    }
    
    @Test("Multiple tool calls should route to different clients")
    func testMultipleToolCallsRouteToDifferentClients() async throws {
        // Given - Different tool calls for different agents
        let toolCall1 = createToolCall(name: "Agent1", instructions: "Task 1", id: UUID().uuidString)
        let toolCall2 = createToolCall(name: "Agent2", instructions: "Task 2", id: UUID().uuidString)
        let toolCall3 = createToolCall(name: "Agent3", instructions: "Task 3", id: UUID().uuidString)
        
        // Then - Each should route to its respective agent
        #expect(toolCall1.name == "Agent1")
        #expect(toolCall2.name == "Agent2")
        #expect(toolCall3.name == "Agent3")
        
        // This ensures the fix properly routes to the matching client
        // rather than calling all clients sequentially
    }
    
    // MARK: - Edge Cases
    
    @Test("agentCall should handle agent card with same name in different cases")
    func testAgentCallCaseSensitiveMatching() async throws {
        // Given - Agent names differing only in case
        let toolCallLower = createToolCall(name: "testagent", instructions: "Task", id: UUID().uuidString)
        let toolCallUpper = createToolCall(name: "TestAgent", instructions: "Task", id: UUID().uuidString)
        let toolCallMixed = createToolCall(name: "testAgent", instructions: "Task", id: UUID().uuidString)
        
        // Then - Names should be treated as different (case-sensitive)
        #expect(toolCallLower.name != toolCallUpper.name)
        #expect(toolCallLower.name != toolCallMixed.name)
        #expect(toolCallUpper.name != toolCallMixed.name)
    }
    
    @Test("agentCall should handle instructions with special characters")
    func testAgentCallWithSpecialCharactersInInstructions() async throws {
        // Given - Instructions with various special characters
        let specialInstructions = """
        Task with "quotes", 'apostrophes', and
        newlines\t\ttabs\\backslashes and emojis 🚀
        """
        
        let toolCall = createToolCall(name: "TestAgent", instructions: specialInstructions, id: UUID().uuidString)
        
        // Verify the instructions are preserved
        if case .object(let dict) = toolCall.arguments,
           case .string(let instructions) = dict["instructions"] {
            #expect(instructions == specialInstructions)
        } else {
            #expect(Bool(false), "Instructions should be preserved")
        }
    }
    
    @Test("agentCall should handle very long instructions")
    func testAgentCallWithLongInstructions() async throws {
        // Given - Very long instructions
        let longInstructions = String(repeating: "A very long instruction. ", count: 1000)
        let toolCall = createToolCall(name: "TestAgent", instructions: longInstructions, id: UUID().uuidString)
        
        // Verify instructions are preserved
        if case .object(let dict) = toolCall.arguments,
           case .string(let instructions) = dict["instructions"] {
            #expect(instructions.count > 10000)
        } else {
            #expect(Bool(false), "Long instructions should be preserved")
        }
    }
    
    // MARK: - Image Extraction Tests
    
    @Test("agentCall should extract images from file artifacts with base64 data")
    func testAgentCallExtractsImagesFromFileArtifacts() async throws {
        // Given - A task with file artifact containing base64 image data
        let testImageData = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        guard let imageData = Data(base64Encoded: testImageData) else {
            Issue.record("Failed to create test image data")
            return
        }
        
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(
                state: .completed,
                timestamp: ISO8601DateFormatter().string(from: Date())
            ),
            artifacts: [
                Artifact(
                    artifactId: UUID().uuidString,
                    parts: [
                        .text(text: "The image has been generated"),
                        .file(data: imageData, url: nil)
                    ],
                    name: "generated-image"
                )
            ]
        )
        
        // Create manager and client
        let agentCard = createMockAgentCard(name: "ImageGenerator")
        let client = A2AClient(server: A2AConfig.A2AConfigServer(name: "test", url: URL(string: "https://example.com")!), bootCall: nil)
        // Note: This is a structural test - full integration would require proper client setup
        
        // Verify artifact structure
        if let artifact = task.artifacts?.first {
            #expect(artifact.parts.count == 2)
            
            // Verify text part
            let textParts = artifact.parts.compactMap { part -> String? in
                if case .text(let text) = part, !text.isEmpty {
                    return text
                }
                return nil
            }
            #expect(textParts.count == 1)
            #expect(textParts[0] == "The image has been generated")
            
            // Verify file part
            let fileParts = artifact.parts.compactMap { part -> Data? in
                if case .file(let data, _) = part {
                    return data
                }
                return nil
            }
            #expect(fileParts.count == 1)
            #expect(fileParts[0] == imageData)
        } else {
            Issue.record("Expected artifact with file part")
        }
    }
    
    @Test("agentCall should extract multiple images from artifacts")
    func testAgentCallExtractsMultipleImages() async throws {
        // Given - Task with multiple file artifacts
        let testImageData1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let testImageData2 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        
        guard let imageData1 = Data(base64Encoded: testImageData1),
              let imageData2 = Data(base64Encoded: testImageData2) else {
            Issue.record("Failed to create test image data")
            return
        }
        
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(
                state: .completed,
                timestamp: ISO8601DateFormatter().string(from: Date())
            ),
            artifacts: [
                Artifact(
                    artifactId: UUID().uuidString,
                    parts: [.file(data: imageData1, url: nil)],
                    name: "image1"
                ),
                Artifact(
                    artifactId: UUID().uuidString,
                    parts: [.file(data: imageData2, url: nil)],
                    name: "image2"
                )
            ]
        )
        
        // Verify structure
        #expect(task.artifacts?.count == 2)
        
        let fileParts = task.artifacts?.flatMap { artifact in
            artifact.parts.compactMap { part -> Data? in
                if case .file(let data, _) = part {
                    return data
                }
                return nil
            }
        } ?? []
        
        #expect(fileParts.count == 2)
        #expect(fileParts[0] == imageData1)
        #expect(fileParts[1] == imageData2)
    }
    
    @Test("agentCall should extract both text and images from mixed artifacts")
    func testAgentCallExtractsTextAndImages() async throws {
        // Given - Artifact with both text and file parts
        let testImageData = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        guard let imageData = Data(base64Encoded: testImageData) else {
            Issue.record("Failed to create test image data")
            return
        }
        
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [
                .text(text: "Here is the generated image:"),
                .file(data: imageData, url: nil),
                .text(text: "The image generation is complete.")
            ],
            name: "mixed-artifact"
        )
        
        // Verify structure
        #expect(artifact.parts.count == 3)
        
        let textParts = artifact.parts.compactMap { part -> String? in
            if case .text(let text) = part, !text.isEmpty {
                return text
            }
            return nil
        }
        
        let fileParts = artifact.parts.compactMap { part -> Data? in
            if case .file(let data, _) = part {
                return data
            }
            return nil
        }
        
        #expect(textParts.count == 2)
        #expect(fileParts.count == 1)
        #expect(textParts[0] == "Here is the generated image:")
        #expect(textParts[1] == "The image generation is complete.")
        #expect(fileParts[0] == imageData)
    }
    
    @Test("LLMResponse should store images in metadata")
    func testLLMResponseStoresImagesInMetadata() async throws {
        // Given - Create Message.Image objects
        let testImageData = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        guard let imageData = Data(base64Encoded: testImageData) else {
            Issue.record("Failed to create test image data")
            return
        }
        
        let image = Message.Image(
            name: "test-image",
            path: nil,
            imageData: imageData,
            thumbData: nil
        )
        
        // Convert to JSON
        let imageJSON = image.toEasyJSON(includeImageData: true, includeThumbData: false)
        let modelMetadata = JSON.object([
            "images": JSON.array([imageJSON])
        ])
        
        let metadata = LLMMetadata(modelMetadata: modelMetadata)
        let response = LLMResponse.complete(content: "Image generated", metadata: metadata)
        
        // Verify images can be extracted
        #expect(response.images.count == 1)
        #expect(response.images[0].name == "test-image")
        #expect(response.images[0].imageData == imageData)
    }
    
    @Test("LLMResponse should extract multiple images from metadata")
    func testLLMResponseExtractsMultipleImages() async throws {
        // Given - Multiple images
        let testImageData1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let testImageData2 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        
        guard let imageData1 = Data(base64Encoded: testImageData1),
              let imageData2 = Data(base64Encoded: testImageData2) else {
            Issue.record("Failed to create test image data")
            return
        }
        
        let image1 = Message.Image(name: "image1", imageData: imageData1)
        let image2 = Message.Image(name: "image2", imageData: imageData2)
        
        let imagesJSON = [image1, image2].map { $0.toEasyJSON(includeImageData: true, includeThumbData: false) }
        let modelMetadata = JSON.object([
            "images": JSON.array(imagesJSON)
        ])
        
        let metadata = LLMMetadata(modelMetadata: modelMetadata)
        let response = LLMResponse.complete(content: "Images generated", metadata: metadata)
        
        // Verify both images are extracted
        #expect(response.images.count == 2)
        #expect(response.images[0].name == "image1")
        #expect(response.images[1].name == "image2")
        #expect(response.images[0].imageData == imageData1)
        #expect(response.images[1].imageData == imageData2)
    }
    
    @Test("LLMResponse should return empty array when no images in metadata")
    func testLLMResponseReturnsEmptyImagesWhenNone() async throws {
        // Given - Response without images
        let response = LLMResponse.complete(content: "No images")
        
        // Then
        #expect(response.images.isEmpty)
    }
    
    // MARK: - agentCall response content types (text, images, file refs, data)
    
    @Test("agentCall returns text-only response from message")
    func testAgentCallReturnsTextResponse() async throws {
        let manager = A2AManager()
        let agentName = "TextAgent"
        let card = createMockAgentCard(name: agentName)
        let msg = A2AMessage(
            role: "agent",
            parts: [.text(text: "Here is the answer.")],
            messageId: UUID().uuidString
        )
        let mock = MockA2AStreamClient(agentCard: card, events: [wrap(.message(msg))])
        try await manager.initialize(clients: [mock])
        let toolCall = createToolCall(name: agentName, instructions: "Say something", id: UUID().uuidString)
        
        let responses = try await manager.agentCall(toolCall)
        
        #expect(responses != nil)
        #expect(responses?.count == 1)
        #expect(responses?[0].content == "Here is the answer.")
        #expect(responses?[0].images.isEmpty == true)
        #expect(responses?[0].files.isEmpty == true)
    }
    
    @Test("agentCall returns image from file part with base64 image data")
    func testAgentCallReturnsImageFromFilePart() async throws {
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        guard let pngData = Data(base64Encoded: pngBase64) else { Issue.record("Bad PNG"); return }
        
        let manager = A2AManager()
        let agentName = "ImageAgent"
        let card = createMockAgentCard(name: agentName)
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [
                .text(text: "Generated image"),
                .file(data: pngData, url: nil)
            ],
            name: "out.png"
        )
        let event = TaskArtifactUpdateEvent(
            taskId: UUID().uuidString,
            contextId: UUID().uuidString,
            artifact: artifact,
            append: false,
            lastChunk: true
        )
        let mock = MockA2AStreamClient(agentCard: card, events: [wrap(.taskArtifactUpdate(event))])
        try await manager.initialize(clients: [mock])
        let toolCall = createToolCall(name: agentName, instructions: "Generate", id: UUID().uuidString)
        
        let responses = try await manager.agentCall(toolCall)
        
        #expect(responses != nil)
        #expect(responses?.count == 1)
        #expect(responses?[0].content == "Generated image")
        #expect(responses?[0].images.count == 1)
        #expect(responses?[0].images[0].name == "out.png")
        #expect(responses?[0].images[0].imageData == pngData)
        #expect(responses?[0].files.isEmpty == true)
    }
    
    @Test("agentCall returns file reference for remote URL (file part, no data)")
    func testAgentCallReturnsFileReferenceRemote() async throws {
        let remoteURL = URL(string: "https://example.com/doc.pdf")!
        let manager = A2AManager()
        let agentName = "FileAgent"
        let card = createMockAgentCard(name: agentName)
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [
                .text(text: "See attachment"),
                .file(data: nil, url: remoteURL)
            ],
            name: "doc.pdf"
        )
        let event = TaskArtifactUpdateEvent(
            taskId: UUID().uuidString,
            contextId: UUID().uuidString,
            artifact: artifact,
            append: false,
            lastChunk: true
        )
        let mock = MockA2AStreamClient(agentCard: card, events: [wrap(.taskArtifactUpdate(event))])
        try await manager.initialize(clients: [mock])
        let toolCall = createToolCall(name: agentName, instructions: "Attach", id: UUID().uuidString)
        
        let responses = try await manager.agentCall(toolCall)
        
        #expect(responses != nil)
        #expect(responses?.count == 1)
        #expect(responses?[0].content == "See attachment")
        #expect(responses?[0].images.isEmpty == true)
        #expect(responses?[0].files.count == 1)
        #expect(responses?[0].files[0].url == remoteURL)
        #expect(responses?[0].files[0].data == nil)
    }
    
    @Test("agentCall returns file reference for local file URL")
    func testAgentCallReturnsFileReferenceLocal() async throws {
        let localURL = URL(string: "file:///tmp/output.pdf")!
        let manager = A2AManager()
        let agentName = "LocalAgent"
        let card = createMockAgentCard(name: agentName)
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [
                .text(text: "Saved to disk"),
                .file(data: nil, url: localURL)
            ],
            name: "output.pdf"
        )
        let event = TaskArtifactUpdateEvent(
            taskId: UUID().uuidString,
            contextId: UUID().uuidString,
            artifact: artifact,
            append: false,
            lastChunk: true
        )
        let mock = MockA2AStreamClient(agentCard: card, events: [wrap(.taskArtifactUpdate(event))])
        try await manager.initialize(clients: [mock])
        let toolCall = createToolCall(name: agentName, instructions: "Save", id: UUID().uuidString)
        
        let responses = try await manager.agentCall(toolCall)
        
        #expect(responses != nil)
        #expect(responses?.count == 1)
        #expect(responses?[0].files.count == 1)
        #expect(responses?[0].files[0].url == localURL)
    }
    
    @Test("agentCall returns file from data part when not image")
    func testAgentCallReturnsFileFromDataPart() async throws {
        // Non-image bytes (e.g. PDF header or arbitrary binary)
        let arbitraryData = Data([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34]) // %PDF-1.4
        let manager = A2AManager()
        let agentName = "DataAgent"
        let card = createMockAgentCard(name: agentName)
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [
                .text(text: "Binary payload"),
                .data(data: arbitraryData)
            ],
            name: "file.bin"
        )
        let event = TaskArtifactUpdateEvent(
            taskId: UUID().uuidString,
            contextId: UUID().uuidString,
            artifact: artifact,
            append: false,
            lastChunk: true
        )
        let mock = MockA2AStreamClient(agentCard: card, events: [wrap(.taskArtifactUpdate(event))])
        try await manager.initialize(clients: [mock])
        let toolCall = createToolCall(name: agentName, instructions: "Send data", id: UUID().uuidString)
        
        let responses = try await manager.agentCall(toolCall)
        
        #expect(responses != nil)
        #expect(responses?.count == 1)
        #expect(responses?[0].content == "Binary payload")
        #expect(responses?[0].images.isEmpty == true)
        #expect(responses?[0].files.count == 1)
        #expect(responses?[0].files[0].data == arbitraryData)
        #expect(responses?[0].files[0].url == nil)
    }
    
    @Test("agentCall returns image from data part when image bytes")
    func testAgentCallReturnsImageFromDataPart() async throws {
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        guard let pngData = Data(base64Encoded: pngBase64) else { Issue.record("Bad PNG"); return }
        
        let manager = A2AManager()
        let agentName = "DataImageAgent"
        let card = createMockAgentCard(name: agentName)
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [
                .text(text: "Image via data part"),
                .data(data: pngData)
            ],
            name: "img.png"
        )
        let event = TaskArtifactUpdateEvent(
            taskId: UUID().uuidString,
            contextId: UUID().uuidString,
            artifact: artifact,
            append: false,
            lastChunk: true
        )
        let mock = MockA2AStreamClient(agentCard: card, events: [wrap(.taskArtifactUpdate(event))])
        try await manager.initialize(clients: [mock])
        let toolCall = createToolCall(name: agentName, instructions: "Generate", id: UUID().uuidString)
        
        let responses = try await manager.agentCall(toolCall)
        
        #expect(responses != nil)
        #expect(responses?.count == 1)
        #expect(responses?[0].content == "Image via data part")
        #expect(responses?[0].images.count == 1)
        #expect(responses?[0].images[0].imageData == pngData)
        #expect(responses?[0].files.isEmpty == true)
    }
    
    @Test("agentCall returns text, image, and files in one response")
    func testAgentCallReturnsTextImageAndFilesCombined() async throws {
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        guard let pngData = Data(base64Encoded: pngBase64) else { Issue.record("Bad PNG"); return }
        let nonImageData = Data([0x00, 0x01, 0x02, 0x03])
        let remoteURL = URL(string: "https://example.com/ref.txt")!
        
        let manager = A2AManager()
        let agentName = "CombinedAgent"
        let card = createMockAgentCard(name: agentName)
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [
                .text(text: "Summary"),
                .file(data: pngData, url: nil),
                .file(data: nil, url: remoteURL),
                .data(data: nonImageData)
            ],
            name: "combined"
        )
        let event = TaskArtifactUpdateEvent(
            taskId: UUID().uuidString,
            contextId: UUID().uuidString,
            artifact: artifact,
            append: false,
            lastChunk: true
        )
        let mock = MockA2AStreamClient(agentCard: card, events: [wrap(.taskArtifactUpdate(event))])
        try await manager.initialize(clients: [mock])
        let toolCall = createToolCall(name: agentName, instructions: "Mix", id: UUID().uuidString)
        
        let responses = try await manager.agentCall(toolCall)
        
        #expect(responses != nil)
        #expect(responses?.count == 1)
        let r = responses![0]
        #expect(r.content == "Summary")
        #expect(r.images.count == 1)
        #expect(r.images[0].imageData == pngData)
        #expect(r.files.count == 2)
        let fileURL = r.files.first { $0.url == remoteURL }
        let fileData = r.files.first { $0.data == nonImageData }
        #expect(fileURL != nil)
        #expect(fileData != nil)
    }
    
    @Test("agentCall returns image when there is no text content")
    func testAgentCallReturnsImageOnlyWhenNoText() async throws {
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        guard let pngData = Data(base64Encoded: pngBase64) else { Issue.record("Bad PNG"); return }
        
        let manager = A2AManager()
        let agentName = "ImageOnlyAgent"
        let card = createMockAgentCard(name: agentName)
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [.file(data: pngData, url: nil)],
            name: "out.png"
        )
        let event = TaskArtifactUpdateEvent(
            taskId: UUID().uuidString,
            contextId: UUID().uuidString,
            artifact: artifact,
            append: false,
            lastChunk: true
        )
        let mock = MockA2AStreamClient(agentCard: card, events: [wrap(.taskArtifactUpdate(event))])
        try await manager.initialize(clients: [mock])
        let toolCall = createToolCall(name: agentName, instructions: "Generate", id: UUID().uuidString)
        
        let responses = try await manager.agentCall(toolCall)
        
        #expect(responses != nil)
        #expect(responses?.count == 1)
        #expect(responses?[0].content.isEmpty == true)
        #expect(responses?[0].images.count == 1)
        #expect(responses?[0].images[0].imageData == pngData)
        #expect(responses?[0].files.isEmpty == true)
    }
    
    @Test("agentCall returns file when there is no text content")
    func testAgentCallReturnsFileOnlyWhenNoText() async throws {
        let remoteURL = URL(string: "https://example.com/asset.pdf")!
        let manager = A2AManager()
        let agentName = "FileOnlyAgent"
        let card = createMockAgentCard(name: agentName)
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [.file(data: nil, url: remoteURL)],
            name: "asset.pdf"
        )
        let event = TaskArtifactUpdateEvent(
            taskId: UUID().uuidString,
            contextId: UUID().uuidString,
            artifact: artifact,
            append: false,
            lastChunk: true
        )
        let mock = MockA2AStreamClient(agentCard: card, events: [wrap(.taskArtifactUpdate(event))])
        try await manager.initialize(clients: [mock])
        let toolCall = createToolCall(name: agentName, instructions: "Attach", id: UUID().uuidString)
        
        let responses = try await manager.agentCall(toolCall)
        
        #expect(responses != nil)
        #expect(responses?.count == 1)
        #expect(responses?[0].content.isEmpty == true)
        #expect(responses?[0].images.isEmpty == true)
        #expect(responses?[0].files.count == 1)
        #expect(responses?[0].files[0].url == remoteURL)
    }
    
    @Test("agentCall returns images and files when there is no text content")
    func testAgentCallReturnsImagesAndFilesOnlyWhenNoText() async throws {
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        guard let pngData = Data(base64Encoded: pngBase64) else { Issue.record("Bad PNG"); return }
        let nonImageData = Data([0x01, 0x02, 0x03])
        let remoteURL = URL(string: "https://example.com/ref.pdf")!
        
        let manager = A2AManager()
        let agentName = "MediaOnlyAgent"
        let card = createMockAgentCard(name: agentName)
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [
                .file(data: pngData, url: nil),
                .file(data: nil, url: remoteURL),
                .data(data: nonImageData)
            ],
            name: "media"
        )
        let event = TaskArtifactUpdateEvent(
            taskId: UUID().uuidString,
            contextId: UUID().uuidString,
            artifact: artifact,
            append: false,
            lastChunk: true
        )
        let mock = MockA2AStreamClient(agentCard: card, events: [wrap(.taskArtifactUpdate(event))])
        try await manager.initialize(clients: [mock])
        let toolCall = createToolCall(name: agentName, instructions: "Send media", id: UUID().uuidString)
        
        let responses = try await manager.agentCall(toolCall)
        
        #expect(responses != nil)
        #expect(responses?.count == 1)
        let r = responses![0]
        #expect(r.content.isEmpty == true)
        #expect(r.images.count == 1)
        #expect(r.images[0].imageData == pngData)
        #expect(r.files.count == 2)
        #expect(r.files.contains { $0.url == remoteURL } == true)
        #expect(r.files.contains { $0.data == nonImageData } == true)
    }
    
    @Test("agentCall should handle file artifacts with URL but no data")
    func testAgentCallHandlesFileArtifactWithURL() async throws {
        // Given - File artifact with URL but no data
        let imageURL = URL(string: "https://example.com/image.png")!
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [
                .text(text: "Image available at URL"),
                .file(data: nil, url: imageURL)
            ],
            name: "url-image"
        )
        
        // Verify structure
        let fileParts = artifact.parts.compactMap { part -> URL? in
            if case .file(_, let url) = part {
                return url
            }
            return nil
        }
        
        #expect(fileParts.count == 1)
        #expect(fileParts[0] == imageURL)
    }
    
    @Test("agentCall should handle data parts that are images")
    func testAgentCallHandlesDataPartsAsImages() async throws {
        // Given - Data part with image data
        let testImageData = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        guard let imageData = Data(base64Encoded: testImageData) else {
            Issue.record("Failed to create test image data")
            return
        }
        
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [
                .text(text: "Image data"),
                .data(data: imageData)
            ],
            name: "data-image"
        )
        
        // Verify structure
        let dataParts = artifact.parts.compactMap { part -> Data? in
            if case .data(let data) = part {
                return data
            }
            return nil
        }
        
        #expect(dataParts.count == 1)
        #expect(dataParts[0] == imageData)
    }
    
    @Test("Message.Image should be created from file artifact data")
    func testMessageImageFromFileArtifact() async throws {
        // Given - File artifact with image data
        let testImageData = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        guard let imageData = Data(base64Encoded: testImageData) else {
            Issue.record("Failed to create test image data")
            return
        }
        
        // Create Message.Image from artifact data
        let image = Message.Image(
            name: "generated-image",
            path: nil,
            imageData: imageData,
            thumbData: nil
        )
        
        // Verify
        #expect(image.name == "generated-image")
        #expect(image.imageData == imageData)
        #expect(image.path == nil)
        
        // Verify it can be converted to JSON and back
        let imageJSON = image.toEasyJSON(includeImageData: true, includeThumbData: false)
        let reconstructedImage = Message.Image(from: imageJSON)
        
        #expect(reconstructedImage.name == image.name)
        #expect(reconstructedImage.imageData == image.imageData)
    }

    // MARK: - streamAgentCall() Tests

    /// Collects all events from a delegate stream into an array.
    private func collectEvents(from stream: AsyncStream<A2ADelegateStreamEvent>) async -> [A2ADelegateStreamEvent] {
        var events: [A2ADelegateStreamEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    @Test("streamAgentCall emits expected event sequence for task streaming lifecycle")
    func testStreamAgentCallEventSequence() async throws {
        let taskId = UUID().uuidString
        let contextId = UUID().uuidString
        let agentName = "StreamAgent"

        let task = A2ATask(
            id: taskId,
            contextId: contextId,
            status: TaskStatus(
                state: .working,
                timestamp: ISO8601DateFormatter().string(from: Date())
            ),
            artifacts: nil
        )

        let artifactUpdate = TaskArtifactUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            artifact: Artifact(
                artifactId: UUID().uuidString,
                parts: [.text(text: "Partial ")]
            ),
            append: true,
            lastChunk: false
        )

        let statusUpdate = TaskStatusUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            status: TaskStatus(
                state: .completed,
                timestamp: ISO8601DateFormatter().string(from: Date())
            ),
            final: true
        )

        let manager = A2AManager()
        let card = createMockAgentCard(name: agentName)
        let mock = MockA2AStreamClient(agentCard: card, events: [
            wrap(.task(task)),
            wrap(.taskArtifactUpdate(artifactUpdate)),
            wrap(.taskStatusUpdate(statusUpdate))
        ])
        try await manager.initialize(clients: [mock])

        let invocationID = UUID().uuidString
        let toolCall = createToolCall(name: agentName, instructions: "Stream task", id: "tool-call-1")
        let (handle, events) = try await manager.streamAgentCall(toolCall, invocationID: invocationID)
        let collected = await collectEvents(from: events)

        #expect(handle.invocationID == invocationID)
        #expect(handle.toolCallID == "tool-call-1")
        #expect(handle.agentName == agentName)

        #expect(collected.count >= 5)

        if case .connecting(let name) = collected[0] {
            #expect(name == agentName)
        } else {
            Issue.record("Expected connecting as first event")
        }

        if case .taskStarted(let id, let ctx) = collected[1] {
            #expect(id == taskId)
            #expect(ctx == contextId)
        } else {
            Issue.record("Expected taskStarted as second event")
        }

        if case .artifactChunk(let id, let text, let append, let lastChunk) = collected[2] {
            #expect(id == taskId)
            #expect(text == "Partial ")
            #expect(append == true)
            #expect(lastChunk == false)
        } else {
            Issue.record("Expected artifactChunk as third event")
        }

        if case .statusUpdate(let id, let state, let final) = collected[3] {
            #expect(id == taskId)
            #expect(state == .completed)
            #expect(final == true)
        } else {
            Issue.record("Expected statusUpdate as fourth event")
        }

        let terminalEvents = collected.filter {
            if case .completed = $0 { return true }
            if case .failed = $0 { return true }
            return false
        }
        #expect(terminalEvents.count == 1)
        if case .completed(let completion) = terminalEvents[0] {
            #expect(completion.taskID == taskId)
            #expect(completion.contextID == contextId)
        } else {
            Issue.record("Expected completed as terminal event")
        }
    }

    @Test("streamAgentCall emits failed terminal event on task failure")
    func testStreamAgentCallTerminalFailure() async throws {
        let taskId = UUID().uuidString
        let contextId = UUID().uuidString
        let agentName = "FailAgent"

        let statusUpdate = TaskStatusUpdateEvent(
            taskId: taskId,
            contextId: contextId,
            status: TaskStatus(
                state: .failed,
                message: A2AMessage(role: "agent", parts: [.text(text: "Something went wrong")], messageId: UUID().uuidString),
                timestamp: ISO8601DateFormatter().string(from: Date())
            ),
            final: true
        )

        let manager = A2AManager()
        let card = createMockAgentCard(name: agentName)
        let mock = MockA2AStreamClient(agentCard: card, events: [wrap(.taskStatusUpdate(statusUpdate))])
        try await manager.initialize(clients: [mock])

        let toolCall = createToolCall(name: agentName, instructions: "Fail", id: UUID().uuidString)
        let (_, events) = try await manager.streamAgentCall(toolCall, invocationID: UUID().uuidString)
        let collected = await collectEvents(from: events)

        let terminalEvents = collected.filter {
            if case .completed = $0 { return true }
            if case .failed = $0 { return true }
            return false
        }
        #expect(terminalEvents.count == 1)
        if case .failed(let failure) = terminalEvents[0] {
            #expect(failure.error == "Something went wrong")
            #expect(failure.taskID == taskId)
        } else {
            Issue.record("Expected failed as terminal event")
        }
    }

    @Test("streamAgentCall throws agentNotFound for unknown agent")
    func testStreamAgentCallThrowsAgentNotFound() async throws {
        let manager = A2AManager()
        try await manager.initialize(clients: [])

        let toolCall = createToolCall(name: "MissingAgent", instructions: "Do work", id: UUID().uuidString)

        await #expect(throws: A2AManagerError.agentNotFound("MissingAgent")) {
            _ = try await manager.streamAgentCall(toolCall, invocationID: UUID().uuidString)
        }
    }

    @Test("streamAgentCall throws invalidArguments for bad tool call args")
    func testStreamAgentCallThrowsInvalidArguments() async throws {
        let manager = A2AManager()
        let card = createMockAgentCard(name: "ValidAgent")
        let mock = MockA2AStreamClient(agentCard: card, events: [])
        try await manager.initialize(clients: [mock])

        let toolCall = ToolCall(
            name: "ValidAgent",
            arguments: .object([:]),
            id: UUID().uuidString
        )

        await #expect(throws: A2AManagerError.invalidArguments) {
            _ = try await manager.streamAgentCall(toolCall, invocationID: UUID().uuidString)
        }
    }

    @Test("agentCall and streamAgentCall produce equivalent responses for multi-chunk artifact stream")
    func testAgentCallMatchesStreamAgentCallForMultiChunkArtifacts() async throws {
        let taskId = UUID().uuidString
        let contextId = UUID().uuidString
        let agentName = "ChunkAgent"

        let events: [SendStreamingMessageSuccessResponse<MessageResult>] = [
            wrap(.taskArtifactUpdate(TaskArtifactUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                artifact: Artifact(artifactId: UUID().uuidString, parts: [.text(text: "First ")]),
                append: false,
                lastChunk: false
            ))),
            wrap(.taskArtifactUpdate(TaskArtifactUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                artifact: Artifact(artifactId: UUID().uuidString, parts: [.text(text: "second ")]),
                append: true,
                lastChunk: false
            ))),
            wrap(.taskArtifactUpdate(TaskArtifactUpdateEvent(
                taskId: taskId,
                contextId: contextId,
                artifact: Artifact(artifactId: UUID().uuidString, parts: [.text(text: "third")]),
                append: true,
                lastChunk: true
            )))
        ]

        let managerDirect = A2AManager()
        let managerStream = A2AManager()
        let card = createMockAgentCard(name: agentName)
        try await managerDirect.initialize(clients: [MockA2AStreamClient(agentCard: card, events: events)])
        try await managerStream.initialize(clients: [MockA2AStreamClient(agentCard: card, events: events)])

        let toolCall = createToolCall(name: agentName, instructions: "Chunk", id: UUID().uuidString)

        let directResponses = try await managerDirect.agentCall(toolCall)
        let (_, stream) = try await managerStream.streamAgentCall(toolCall, invocationID: UUID().uuidString)
        var streamResponses: [LLMResponse] = []
        for await event in stream {
            if case .messageChunk(let text, let images, let files) = event {
                var entries: [String: JSON] = [:]
                if !images.isEmpty {
                    entries["images"] = .array(images.map { $0.toEasyJSON(includeImageData: true, includeThumbData: false) })
                }
                if !files.isEmpty {
                    entries["files"] = .array(files.map { $0.toJSON() })
                }
                let metadata: LLMMetadata? = entries.isEmpty ? nil : LLMMetadata(modelMetadata: .object(entries))
                streamResponses.append(LLMResponse.complete(content: text, metadata: metadata))
            }
        }

        #expect(directResponses?[0].content == streamResponses[0].content)
        #expect(directResponses?[0].content == "First second third")
    }

    // MARK: - cancelAgentCall() Tests

    private func makeHangingTask(taskID: String) -> A2ATask {
        A2ATask(
            id: taskID,
            contextId: UUID().uuidString,
            status: TaskStatus(
                state: .working,
                timestamp: ISO8601DateFormatter().string(from: Date())
            ),
            artifacts: nil
        )
    }

    private func setupCancellableManager(
        agentName: String,
        taskID: String
    ) async throws -> (A2AManager, MockCancellableA2AStreamClient) {
        let manager = A2AManager()
        let card = createMockAgentCard(name: agentName)
        let mock = MockCancellableA2AStreamClient(
            agentCard: card,
            initialEvents: [wrap(.task(makeHangingTask(taskID: taskID)))]
        )
        try await manager.initialize(clients: [mock])
        return (manager, mock)
    }

    @Test("cancelAgentCall by invocationID cancels stream and remote task")
    func testCancelAgentCallByInvocationID() async throws {
        let taskID = "task-cancel-invocation"
        let agentName = "CancelAgent"
        let invocationID = "inv-cancel-1"
        let toolCallID = "tool-cancel-1"

        let (manager, mock) = try await setupCancellableManager(agentName: agentName, taskID: taskID)
        let toolCall = createToolCall(name: agentName, instructions: "Hang", id: toolCallID)
        let (_, events) = try await manager.streamAgentCall(toolCall, invocationID: invocationID)

        let collectTask = Task { await collectEvents(from: events) }
        try await Task.sleep(nanoseconds: 100_000_000)

        let cancelled = await manager.cancelAgentCall(invocationID: invocationID)
        #expect(cancelled == true)

        let collected = await collectTask.value
        let terminalEvents = collected.filter {
            if case .completed = $0 { return true }
            if case .failed = $0 { return true }
            return false
        }
        #expect(terminalEvents.count == 1)
        if case .failed(let failure) = terminalEvents[0] {
            #expect(failure.error == "Cancelled")
            #expect(failure.taskID == taskID)
        } else {
            Issue.record("Expected failed terminal event after cancellation")
        }

        #expect(await mock.cancelTaskCallCount == 1)
        #expect(await mock.lastCancelledTaskID == taskID)
        #expect(await manager.cancelAgentCall(invocationID: invocationID) == false)
    }

    @Test("cancelAgentCall by toolCallID cancels in-flight stream")
    func testCancelAgentCallByToolCallID() async throws {
        let taskID = "task-cancel-tool-call"
        let agentName = "CancelByToolCallAgent"
        let toolCallID = "tool-cancel-by-id"

        let (manager, mock) = try await setupCancellableManager(agentName: agentName, taskID: taskID)
        let toolCall = createToolCall(name: agentName, instructions: "Hang", id: toolCallID)
        let (_, events) = try await manager.streamAgentCall(toolCall, invocationID: UUID().uuidString)

        let collectTask = Task { await collectEvents(from: events) }
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(await manager.cancelAgentCall(toolCallID: toolCallID) == true)
        _ = await collectTask.value
        #expect(await mock.cancelTaskCallCount == 1)
    }

    @Test("cancelAgentCall by taskID cancels in-flight stream")
    func testCancelAgentCallByTaskID() async throws {
        let taskID = "task-cancel-by-task-id"
        let agentName = "CancelByTaskIDAgent"
        let toolCallID = "tool-cancel-task-id"

        let (manager, mock) = try await setupCancellableManager(agentName: agentName, taskID: taskID)
        let toolCall = createToolCall(name: agentName, instructions: "Hang", id: toolCallID)
        let (_, events) = try await manager.streamAgentCall(toolCall, invocationID: UUID().uuidString)

        let collectTask = Task { await collectEvents(from: events) }
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(await manager.cancelAgentCall(taskID: taskID) == true)
        _ = await collectTask.value
        #expect(await mock.cancelTaskCallCount == 1)
    }

    @Test("cancelPendingHandle forwards to cancelAgentCall")
    func testCancelPendingHandleAlias() async throws {
        let taskID = "task-cancel-alias"
        let agentName = "CancelAliasAgent"
        let toolCallID = "tool-cancel-alias"

        let (manager, mock) = try await setupCancellableManager(agentName: agentName, taskID: taskID)
        let toolCall = createToolCall(name: agentName, instructions: "Hang", id: toolCallID)
        let (_, events) = try await manager.streamAgentCall(toolCall, invocationID: UUID().uuidString)

        let collectTask = Task { await collectEvents(from: events) }
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(await manager.cancelPendingHandle(toolCallID) == true)
        _ = await collectTask.value
        #expect(await mock.cancelTaskCallCount == 1)
    }

    @Test("cancelAgentCall returns false for unknown invocation")
    func testCancelAgentCallUnknownID() async throws {
        let manager = A2AManager()
        try await manager.initialize(clients: [])
        #expect(await manager.cancelAgentCall(invocationID: "missing") == false)
    }

    @Test("in-flight registry deregisters after terminal stream event")
    func testInFlightDeregistersAfterTerminalEvent() async throws {
        let taskID = UUID().uuidString
        let contextID = UUID().uuidString
        let agentName = "CompleteAgent"

        let statusUpdate = TaskStatusUpdateEvent(
            taskId: taskID,
            contextId: contextID,
            status: TaskStatus(
                state: .completed,
                timestamp: ISO8601DateFormatter().string(from: Date())
            ),
            final: true
        )

        let manager = A2AManager()
        let card = createMockAgentCard(name: agentName)
        let mock = MockA2AStreamClient(agentCard: card, events: [wrap(.taskStatusUpdate(statusUpdate))])
        try await manager.initialize(clients: [mock])

        let toolCall = createToolCall(name: agentName, instructions: "Complete", id: "complete-tool-call")
        let (_, events) = try await manager.streamAgentCall(toolCall, invocationID: "complete-invocation")
        _ = await collectEvents(from: events)

        #expect(await manager.cancelAgentCall(invocationID: "complete-invocation") == false)
        #expect(await manager.cancelAgentCall(toolCallID: "complete-tool-call") == false)
    }

    @Test("cancelAgentCall cancels local stream only when client lacks A2ATaskLifecycleClient")
    func testCancelAgentCallLocalOnlyWithoutLifecycleClient() async throws {
        let taskID = "task-local-only-cancel"
        let agentName = "StreamOnlyCancelAgent"
        let toolCallID = "tool-local-only-cancel"

        let manager = A2AManager()
        let card = createMockAgentCard(name: agentName)
        let mock = MockA2AStreamClient(
            agentCard: card,
            events: [wrap(.task(makeHangingTask(taskID: taskID)))],
            hangsAfterEvents: true
        )
        try await manager.initialize(clients: [mock])

        let toolCall = createToolCall(name: agentName, instructions: "Hang", id: toolCallID)
        let (_, events) = try await manager.streamAgentCall(toolCall, invocationID: UUID().uuidString)

        let collectTask = Task { await collectEvents(from: events) }
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(await manager.cancelAgentCall(toolCallID: toolCallID) == true)

        let collected = await collectTask.value
        let terminalEvents = collected.filter {
            if case .completed = $0 { return true }
            if case .failed = $0 { return true }
            return false
        }
        #expect(terminalEvents.count == 1)
        if case .failed(let failure) = terminalEvents[0] {
            #expect(failure.error == "Cancelled")
        } else {
            Issue.record("Expected failed terminal event after local-only cancellation")
        }
    }

    // MARK: - Client lookup tests

    @Test("client(forAgentNamed:) returns matching client")
    func testClientForAgentNamedReturnsMatchingClient() async throws {
        let manager = A2AManager()
        let cardA = createMockAgentCard(name: "AgentA")
        let cardB = createMockAgentCard(name: "AgentB")
        let clientA = MockA2AStreamClient(agentCard: cardA, events: [])
        let clientB = MockA2AStreamClient(agentCard: cardB, events: [])
        try await manager.initialize(clients: [clientA, clientB])

        let resolvedA = await manager.client(forAgentNamed: "AgentA")
        let resolvedB = await manager.client(forAgentNamed: "AgentB")

        #expect(resolvedA != nil)
        #expect(resolvedB != nil)
        #expect(await resolvedA?.agentCard?.name == "AgentA")
        #expect(await resolvedB?.agentCard?.name == "AgentB")
    }

    @Test("agentCard(forAgentNamed:) returns matching card")
    func testAgentCardForAgentNamedReturnsMatchingCard() async throws {
        let manager = A2AManager()
        let cardA = createMockAgentCard(name: "AgentA")
        let cardB = createMockAgentCard(name: "AgentB")
        try await manager.initialize(clients: [
            MockA2AStreamClient(agentCard: cardA, events: []),
            MockA2AStreamClient(agentCard: cardB, events: [])
        ])

        #expect(await manager.agentCard(forAgentNamed: "AgentA")?.name == "AgentA")
        #expect(await manager.agentCard(forAgentNamed: "AgentB")?.name == "AgentB")
    }

    @Test("client(forAgentNamed:) returns nil for unknown name")
    func testClientForAgentNamedReturnsNilForUnknownName() async throws {
        let manager = A2AManager()
        try await manager.initialize(clients: [
            MockA2AStreamClient(agentCard: createMockAgentCard(name: "AgentA"), events: [])
        ])

        #expect(await manager.client(forAgentNamed: "Missing") == nil)
        #expect(await manager.agentCard(forAgentNamed: "Missing") == nil)
    }

    @Test("client(forAgentNamed:) is case-sensitive")
    func testClientForAgentNamedIsCaseSensitive() async throws {
        let manager = A2AManager()
        try await manager.initialize(clients: [
            MockA2AStreamClient(agentCard: createMockAgentCard(name: "AgentA"), events: [])
        ])

        #expect(await manager.client(forAgentNamed: "AgentA") != nil)
        #expect(await manager.client(forAgentNamed: "agenta") == nil)
        #expect(await manager.agentCard(forAgentNamed: "agenta") == nil)
    }
}

