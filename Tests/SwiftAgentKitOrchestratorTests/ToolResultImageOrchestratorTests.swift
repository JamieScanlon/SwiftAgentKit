import Foundation
import Testing
import Logging
import EasyJSON
import SwiftAgentKit
import SwiftAgentKitOrchestrator

private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x42, 0x42])

/// Returns a fixed `ToolResult` for one tool name.
private struct FixedResultToolProvider: ToolProvider {
    let toolName: String
    let result: @Sendable (String?) -> ToolResult

    var name: String { "FixedResultToolProvider" }

    func availableTools() async -> [ToolDefinition] {
        [ToolDefinition(name: toolName, description: "Returns a fixed result", parameters: [], type: .function)]
    }

    func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        result(toolCall.id)
    }
}

/// Runs one tool round trip through the orchestrator and returns the `.tool` message the LLM received.
private func toolMessageSentToLLM(for provider: FixedResultToolProvider, toolCallId: String) async throws -> Message? {
    let capture = SendCapture()
    let llm = CapturingMockLLM(
        logger: Logger(label: "ToolResultImageOrchestratorTests"),
        toolCallsToReturn: [ToolCall(name: provider.toolName, arguments: .object([:]), id: toolCallId)],
        capture: capture
    )
    let config = OrchestratorConfig(streamingEnabled: false, mcpEnabled: false, a2aEnabled: false)
    let orchestrator = SwiftAgentKitOrchestrator(llm: llm, config: config, toolManager: ToolManager(providers: [provider]))

    let messageStream = await orchestrator.messageStream
    let drain = Task {
        for await _ in messageStream {
            if Task.isCancelled { break }
        }
    }
    defer { drain.cancel() }
    try await orchestrator.updateConversation(
        [Message(id: UUID(), role: .user, content: "Take a screenshot")],
        availableTools: []
    )
    try? await Task.sleep(nanoseconds: 15_000_000)

    let invocations = await capture.getInvocations()
    return invocations.lazy.compactMap { messages in messages.first { $0.role == .tool } }.first
}

@Suite("Orchestrator tool result images")
struct ToolResultImageOrchestratorTests {

    @Test("ToolResult with an image part becomes a .tool Message with one image, media type set, content unchanged")
    func testImagePartReachesToolMessage() async throws {
        let provider = FixedResultToolProvider(toolName: "computer_observe") { id in
            ToolResult.image(pngBytes, mediaType: "image/png", caption: "Screen after click", toolCallId: id)
        }
        let toolMessage = try #require(await toolMessageSentToLLM(for: provider, toolCallId: "call-observe"))

        #expect(toolMessage.toolCallId == "call-observe")
        #expect(toolMessage.content == "Screen after click")
        #expect(toolMessage.images.count == 1)
        #expect(toolMessage.images.first?.mediaType == "image/png")
        #expect(toolMessage.images.first?.imageData == pngBytes)
        #expect(!toolMessage.content.contains(pngBytes.base64EncodedString()))
    }

    @Test("Legacy metadata.images side channel is still read, after image parts")
    func testLegacyMetadataImagesStillRead() async throws {
        let legacyImage = Message.Image(name: "legacy", imageData: Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]))
        let provider = FixedResultToolProvider(toolName: "legacy_tool") { id in
            ToolResult(
                success: true,
                parts: [.text("both"), .image(ToolResultImage(data: pngBytes, mediaType: "image/png"))],
                metadata: .object(["images": .array([legacyImage.toEasyJSON(includeImageData: true)])]),
                toolCallId: id
            )
        }
        let toolMessage = try #require(await toolMessageSentToLLM(for: provider, toolCallId: "call-legacy"))

        #expect(toolMessage.content == "both")
        #expect(toolMessage.images.map(\.name) == ["call-legacy-image-1", "legacy"])
        #expect(toolMessage.images.map(\.mediaType) == ["image/png", nil])
    }

    @Test("Text-only ToolResult still produces a .tool Message without images")
    func testTextOnlyUnchanged() async throws {
        let provider = FixedResultToolProvider(toolName: "plain_tool") { id in
            ToolResult(success: true, content: "plain", toolCallId: id)
        }
        let toolMessage = try #require(await toolMessageSentToLLM(for: provider, toolCallId: "call-plain"))
        #expect(toolMessage.content == "plain")
        #expect(toolMessage.images.isEmpty)
    }
}
