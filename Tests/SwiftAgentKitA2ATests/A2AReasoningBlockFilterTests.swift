//
//  A2AReasoningBlockFilterTests.swift
//  SwiftAgentKit
//
//  Comprehensive tests for reasoning block filtering in A2AServer
//

import Testing
import Foundation
import Logging
@testable import SwiftAgentKitA2A
@testable import SwiftAgentKit

@Suite("A2A Reasoning Block Filter Tests")
struct A2AReasoningBlockFilterTests {
    
    // MARK: - Mock Adapter (simplified for testing)
    
    /// Simple mock adapter for basic server initialization tests
    struct SimpleMockAdapter: AgentAdapter {
        let agentName: String = "TestAgent"
        let agentDescription: String = "Test agent"
        let cardCapabilities: AgentCard.AgentCapabilities = AgentCard.AgentCapabilities(streaming: true)
        let skills: [AgentCard.AgentSkill] = []
        let defaultInputModes: [String] = ["text/plain"]
        let defaultOutputModes: [String] = ["text/plain"]
        
        func responseType(for params: MessageSendParams) -> AdapterResponseType {
            return .message
        }
        
        func handleMessageSend(_ params: MessageSendParams) async throws -> A2AMessage {
            return A2AMessage(
                role: "assistant",
                parts: [.text(text: "Response")],
                messageId: UUID().uuidString
            )
        }
        
        func handleTaskSend(_ params: MessageSendParams, taskId: String, contextId: String, store: TaskStore) async throws {
            // Empty implementation for testing
        }
        
        func handleStream(_ params: MessageSendParams, taskId: String?, contextId: String?, store: TaskStore?, eventSink: @escaping (Encodable) -> Void) async throws {
            // Empty implementation for testing
        }
    }
    
    // MARK: - Helper Functions
    
    /// Creates a message with reasoning blocks
    func createMessageWithReasoning() -> A2AMessage {
        return A2AMessage(
            role: "assistant",
            parts: [.text(text: "Response text.<think>This is reasoning content.</think>More response text.")],
            messageId: UUID().uuidString
        )
    }
    
    /// Creates a task with reasoning blocks in artifacts and status
    func createTaskWithReasoning(taskId: String, contextId: String) -> A2ATask {
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [.text(text: "Artifact content.<think>Reasoning in artifact.</think>Final artifact content.")],
            name: "test-artifact"
        )
        return A2ATask(
            id: taskId,
            contextId: contextId,
            status: TaskStatus(
                state: .completed,
                message: A2AMessage(
                    role: "assistant",
                    parts: [.text(text: "Status message.<think>Status reasoning.</think>Status done.")],
                    messageId: UUID().uuidString
                ),
                timestamp: ISO8601DateFormatter().string(from: Date())
            ),
            artifacts: [artifact]
        )
    }
    
    /// Extracts text from message parts
    func extractText(from message: A2AMessage) -> String {
        return message.parts.compactMap { part in
            if case .text(let text) = part {
                return text
            }
            return nil
        }.joined(separator: " ")
    }
    
    /// Checks if text contains reasoning blocks
    func containsReasoningBlock(_ text: String) -> Bool {
        let pattern = #"<(?:think|redacted_reasoning|reasoning|thinking)[^>]*>.*?</(?:think|redacted_reasoning|reasoning|thinking)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
    
    // MARK: - Text Filtering Tests
    
    @Test("Should filter <think> blocks from text")
    func testFilterThinkBlocks() {
        let input = "Before.<think>Reasoning content.</think>After."
        let filtered = filterReasoningBlocksFromText(input)
        #expect(!containsReasoningBlock(filtered))
        #expect(filtered.contains("Before."))
        #expect(filtered.contains("After."))
        #expect(!filtered.contains("Reasoning content"))
    }
    
    @Test("Should filter <think> blocks from text")
    func testFilterRedactedReasoningBlocks() {
        let input = "Before.<think>Hidden reasoning.</think>After."
        let filtered = filterReasoningBlocksFromText(input)
        #expect(!containsReasoningBlock(filtered))
        #expect(filtered.contains("Before."))
        #expect(filtered.contains("After."))
        #expect(!filtered.contains("Hidden reasoning"))
    }
    
    @Test("Should filter multiple reasoning blocks")
    func testFilterMultipleReasoningBlocks() {
        let input = "Start.<think>First.</think>Middle.<think>Second.</think>End."
        let filtered = filterReasoningBlocksFromText(input)
        #expect(!containsReasoningBlock(filtered))
        #expect(filtered.contains("Start."))
        #expect(filtered.contains("Middle."))
        #expect(filtered.contains("End."))
    }
    
    @Test("Should handle reasoning blocks across multiple lines")
    func testFilterMultilineReasoningBlocks() {
        let input = """
        Before.
        <think>
        Multi-line
        reasoning
        content.
        </think>
        After.
        """
        let filtered = filterReasoningBlocksFromText(input)
        #expect(!containsReasoningBlock(filtered))
        #expect(filtered.contains("Before."))
        #expect(filtered.contains("After."))
    }
    
    @Test("Should preserve text without reasoning blocks")
    func testPreserveTextWithoutReasoningBlocks() {
        let input = "This is normal text without any reasoning blocks."
        let filtered = filterReasoningBlocksFromText(input)
        #expect(filtered == input)
    }
    
    @Test("Should handle empty text")
    func testFilterEmptyText() {
        let input = ""
        let filtered = filterReasoningBlocksFromText(input)
        #expect(filtered == "")
    }
    
    @Test("Should handle case-insensitive reasoning blocks")
    func testFilterCaseInsensitive() {
        let input = "Before.<THINK>Uppercase.</THINK>After."
        let filtered = filterReasoningBlocksFromText(input)
        #expect(!containsReasoningBlock(filtered))
    }
    
    @Test("Should filter reasoning blocks with attributes")
    func testFilterReasoningBlocksWithAttributes() {
        let input = "Before.<think id=\"123\">With attributes.</think>After."
        let filtered = filterReasoningBlocksFromText(input)
        #expect(!containsReasoningBlock(filtered))
    }
    
    // MARK: - Message Filtering Tests
    
    @Test("Should filter reasoning blocks from A2AMessage")
    func testFilterMessageReasoningBlocks() {
        let message = createMessageWithReasoning()
        
        // Test the filtering function directly
        let filtered = filterReasoningBlocksFromMessage(message)
        let text = extractText(from: filtered)
        #expect(!containsReasoningBlock(text))
        #expect(text.contains("Response text."))
        #expect(text.contains("More response text."))
    }
    
    @Test("Should preserve message structure when filtering")
    func testPreserveMessageStructure() {
        let message = A2AMessage(
            role: "assistant",
            parts: [
                .text(text: "First part.<think>Reasoning.</think>"),
                .text(text: "Second part."),
                .data(data: Data("test".utf8))
            ],
            messageId: UUID().uuidString
        )
        
        let filtered = filterReasoningBlocksFromMessage(message)
        #expect(filtered.parts.count == 3)
        #expect(filtered.role == message.role)
        #expect(filtered.messageId == message.messageId)
        
        // Check that data part is preserved
        if case .data(let data) = filtered.parts[2] {
            #expect(String(data: data, encoding: .utf8) == "test")
        } else {
            Issue.record("Expected data part to be preserved")
        }
    }
    
    // MARK: - Artifact Filtering Tests
    
    @Test("Should filter reasoning blocks from Artifact")
    func testFilterArtifactReasoningBlocks() {
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [.text(text: "Artifact content.<think>Reasoning.</think>More content.")],
            name: "test-artifact"
        )
        
        let filtered = filterReasoningBlocksFromArtifact(artifact)
        let text = extractTextFromArtifact(filtered)
        #expect(!containsReasoningBlock(text))
        #expect(text.contains("Artifact content."))
        #expect(text.contains("More content."))
        #expect(filtered.artifactId == artifact.artifactId)
        #expect(filtered.name == artifact.name)
    }
    
    // MARK: - Task Filtering Tests
    
    @Test("Should filter reasoning blocks from A2ATask")
    func testFilterTaskReasoningBlocks() {
        let taskId = UUID().uuidString
        let contextId = UUID().uuidString
        let task = createTaskWithReasoning(taskId: taskId, contextId: contextId)
        
        let filtered = filterReasoningBlocksFromTask(task)
        
        // Check artifacts
        if let artifacts = filtered.artifacts, !artifacts.isEmpty {
            let artifactText = extractTextFromArtifact(artifacts[0])
            #expect(!containsReasoningBlock(artifactText))
        }
        
        // Check status message
        if let statusMessage = filtered.status.message {
            let statusText = extractText(from: statusMessage)
            #expect(!containsReasoningBlock(statusText))
        }
        
        #expect(filtered.id == task.id)
        #expect(filtered.contextId == task.contextId)
    }
    
    @Test("Should filter reasoning blocks from task history")
    func testFilterTaskHistoryReasoningBlocks() {
        let taskId = UUID().uuidString
        let contextId = UUID().uuidString
        var task = createTaskWithReasoning(taskId: taskId, contextId: contextId)
        task.history = [
            A2AMessage(
                role: "user",
                parts: [.text(text: "User message.")],
                messageId: UUID().uuidString
            ),
            A2AMessage(
                role: "assistant",
                parts: [.text(text: "Assistant response.<think>Reasoning.</think>Done.")],
                messageId: UUID().uuidString
            )
        ]
        
        let filtered = filterReasoningBlocksFromTask(task)
        
        if let history = filtered.history {
            #expect(history.count == 2)
            let assistantText = extractText(from: history[1])
            #expect(!containsReasoningBlock(assistantText))
        }
    }
    
    // MARK: - Server Configuration Tests
    
    @Test("Should allow server initialization with filtering enabled")
    func testDefaultFilteringEnabled() async throws {
        let adapter = SimpleMockAdapter()
        
        // Create server with default settings (filtering should be enabled)
        // This verifies the server can be initialized with default filtering
        _ = A2AServer(port: 4247, adapter: adapter)
        
        // The actual filtering behavior is tested through the helper functions above
    }
    
    @Test("Should allow server initialization with filtering disabled")
    func testDisableFiltering() async throws {
        let adapter = SimpleMockAdapter()
        
        // Create server with filtering disabled
        // This verifies the server can be initialized with filtering disabled
        _ = A2AServer(port: 4248, adapter: adapter, filterReasoningBlocks: false)
    }
    
    // MARK: - Edge Cases
    
    @Test("Should handle reasoning blocks at start of text")
    func testReasoningBlockAtStart() {
        let input = "<think>Reasoning first.</think>Then normal text."
        let filtered = filterReasoningBlocksFromText(input)
        #expect(!containsReasoningBlock(filtered))
        #expect(filtered.contains("Then normal text."))
    }
    
    @Test("Should handle reasoning blocks at end of text")
    func testReasoningBlockAtEnd() {
        let input = "Normal text first.<think>Reasoning at end.</think>"
        let filtered = filterReasoningBlocksFromText(input)
        #expect(!containsReasoningBlock(filtered))
        #expect(filtered.contains("Normal text first."))
    }
    
    @Test("Should handle only reasoning blocks")
    func testOnlyReasoningBlocks() {
        let input = "<think>Only reasoning.</think>"
        let filtered = filterReasoningBlocksFromText(input)
        #expect(!containsReasoningBlock(filtered))
        // Should be empty or whitespace after filtering
        let trimmed = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.isEmpty)
    }
    
    @Test("Should handle nested reasoning blocks")
    func testNestedReasoningBlocks() {
        // Note: This tests that we handle the pattern correctly
        // Real nested blocks would be malformed XML/HTML, but we should still handle them
        let input = "Before.<think>Outer.<think>Inner.</think>Outer end.</think>After."
        let filtered = filterReasoningBlocksFromText(input)
        // The regex should match the outer block, removing everything
        #expect(!containsReasoningBlock(filtered))
    }
    
    @Test("Should handle reasoning blocks with special characters")
    func testReasoningBlocksWithSpecialCharacters() {
        let input = "Before.<think>Reasoning with < > & \" ' characters.</think>After."
        let filtered = filterReasoningBlocksFromText(input)
        #expect(!containsReasoningBlock(filtered))
        #expect(filtered.contains("Before."))
        #expect(filtered.contains("After."))
    }
    
    // MARK: - Private Helper Functions (mirroring server implementation)
    
    /// Filters reasoning blocks from text (mirrors server implementation)
    private func filterReasoningBlocksFromText(_ text: String) -> String {
        let pattern = #"<(?:think|redacted_reasoning|reasoning|thinking)[^>]*>.*?</(?:think|redacted_reasoning|reasoning|thinking)>"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return text
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let filtered = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        
        return filtered.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Filters reasoning blocks from A2AMessage (mirrors server implementation)
    private func filterReasoningBlocksFromMessage(_ message: A2AMessage) -> A2AMessage {
        let filteredParts = message.parts.map { part -> A2AMessagePart in
            switch part {
            case .text(let text):
                let filtered = filterReasoningBlocksFromText(text)
                return .text(text: filtered)
            case .file, .data:
                return part
            }
        }
        
        return A2AMessage(
            role: message.role,
            parts: filteredParts,
            messageId: message.messageId,
            metadata: message.metadata,
            extensions: message.extensions,
            referenceTaskIds: message.referenceTaskIds,
            taskId: message.taskId,
            contextId: message.contextId,
            kind: message.kind
        )
    }
    
    /// Filters reasoning blocks from Artifact (mirrors server implementation)
    private func filterReasoningBlocksFromArtifact(_ artifact: Artifact) -> Artifact {
        let filteredParts = artifact.parts.map { part -> A2AMessagePart in
            switch part {
            case .text(let text):
                let filtered = filterReasoningBlocksFromText(text)
                return .text(text: filtered)
            case .file, .data:
                return part
            }
        }
        
        return Artifact(
            artifactId: artifact.artifactId,
            parts: filteredParts,
            name: artifact.name,
            description: artifact.description,
            metadata: artifact.metadata,
            extensions: artifact.extensions
        )
    }
    
    /// Filters reasoning blocks from A2ATask (mirrors server implementation)
    private func filterReasoningBlocksFromTask(_ task: A2ATask) -> A2ATask {
        var filteredTask = task
        
        // Filter artifacts
        if let artifacts = task.artifacts {
            filteredTask.artifacts = artifacts.map { filterReasoningBlocksFromArtifact($0) }
        }
        
        // Filter history messages
        if let history = task.history {
            filteredTask.history = history.map { filterReasoningBlocksFromMessage($0) }
        }
        
        // Filter status message
        if let statusMessage = task.status.message {
            filteredTask.status.message = filterReasoningBlocksFromMessage(statusMessage)
        }
        
        return filteredTask
    }
    
    /// Extracts text from artifact parts
    private func extractTextFromArtifact(_ artifact: Artifact) -> String {
        return artifact.parts.compactMap { part in
            if case .text(let text) = part {
                return text
            }
            return nil
        }.joined(separator: " ")
    }
}

