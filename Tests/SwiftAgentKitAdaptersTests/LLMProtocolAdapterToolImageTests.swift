import Foundation
import Testing
import Logging
import EasyJSON
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitAdapters

private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x13, 0x37])

/// Records every message list the adapter sends to the LLM.
private actor SentMessagesRecorder {
    private(set) var invocations: [[Message]] = []
    func append(_ messages: [Message]) { invocations.append(messages) }

    /// The `.tool` messages from the first request that contained any.
    func toolMessages() -> [Message] {
        invocations.lazy.map { $0.filter { $0.role == .tool } }.first { !$0.isEmpty } ?? []
    }
}

/// Requests `toolCall` first, then finishes once a tool message is in the conversation.
private struct RecordingToolCallLLM: LLMProtocol {
    let toolCall: ToolCall
    let recorder: SentMessagesRecorder
    let logger = Logger(label: "RecordingToolCallLLM")

    func getModelName() -> String { "recording-model" }
    func getCapabilities() -> [LLMCapability] { [.completion, .tools] }

    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
        await recorder.append(messages)
        if messages.contains(where: { $0.role == .tool }) {
            return LLMResponse.complete(content: "Done")
        }
        return LLMResponse.withToolCalls(content: "", toolCalls: [toolCall])
    }

    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(.complete(try await send(messages, config: config)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/// Returns a fixed `ToolResult` for one tool name.
private struct FixedToolResultProvider: ToolProvider {
    let toolName: String
    let result: @Sendable (String?) -> ToolResult

    var name: String { "FixedToolResultProvider" }

    func availableTools() async -> [ToolDefinition] {
        [ToolDefinition(name: toolName, description: "Returns a fixed result", parameters: [], type: .function)]
    }

    func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        result(toolCall.id)
    }
}

enum ToolImageAdapterLoop: CaseIterable, CustomTestStringConvertible {
    case taskSend
    case stream

    var testDescription: String { self == .taskSend ? "handleTaskSendWithTools" : "handleStreamWithTools" }
}

/// Runs one tool round trip through the chosen adapter loop and returns the `.tool` messages sent back to the LLM.
private func toolMessagesSentToLLM(via loop: ToolImageAdapterLoop, provider: FixedToolResultProvider, toolCallId: String) async throws -> [Message] {
    let recorder = SentMessagesRecorder()
    let llm = RecordingToolCallLLM(
        toolCall: ToolCall(name: provider.toolName, arguments: .object([:]), id: toolCallId),
        recorder: recorder
    )
    let adapter = LLMProtocolAdapter(llm: llm, model: "recording-model")
    let store = TaskStore()
    let task = A2ATask(id: UUID().uuidString, contextId: UUID().uuidString, status: TaskStatus(state: .submitted))
    await store.addTask(task: task)
    let params = MessageSendParams(message: A2AMessage(
        role: "user",
        parts: [.text(text: "Take a screenshot")],
        messageId: UUID().uuidString
    ))

    switch loop {
    case .taskSend:
        try await adapter.handleTaskSendWithTools(params, taskId: task.id, contextId: task.contextId, toolProviders: [provider], store: store)
    case .stream:
        try await adapter.handleStreamWithTools(params, taskId: task.id, contextId: task.contextId, toolProviders: [provider], store: store) { _ in }
    }
    return await recorder.toolMessages()
}

@Suite("LLMProtocolAdapter tool result images")
struct LLMProtocolAdapterToolImageTests {

    @Test("Image parts reach the tool message with media type, in result order", arguments: ToolImageAdapterLoop.allCases)
    func testImagePartsOnToolMessage(loop: ToolImageAdapterLoop) async throws {
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let provider = FixedToolResultProvider(toolName: "computer_observe") { id in
            ToolResult(
                success: true,
                parts: [
                    .text("Screen after click"),
                    .image(ToolResultImage(data: pngBytes, mediaType: "image/png", width: 1280, height: 800)),
                    .image(ToolResultImage(data: jpegBytes, mediaType: "image/jpeg"))
                ],
                toolCallId: id
            )
        }
        let toolMessages = try await toolMessagesSentToLLM(via: loop, provider: provider, toolCallId: "call-observe")

        #expect(toolMessages.count == 1)
        let toolMessage = try #require(toolMessages.first)
        #expect(toolMessage.toolCallId == "call-observe")
        #expect(toolMessage.content.contains("Screen after click"))
        #expect(toolMessage.images.map(\.imageData) == [pngBytes, jpegBytes])
        #expect(toolMessage.images.map(\.mediaType) == ["image/png", "image/jpeg"])
        #expect(toolMessage.images.map(\.name) == ["call-observe-image-1", "call-observe-image-2"])
        #expect(!toolMessage.content.contains(pngBytes.base64EncodedString()))
        #expect(!toolMessage.content.contains(jpegBytes.base64EncodedString()))
    }

    @Test("Text-only tool result produces a tool message without images", arguments: ToolImageAdapterLoop.allCases)
    func testTextOnlyToolMessage(loop: ToolImageAdapterLoop) async throws {
        let provider = FixedToolResultProvider(toolName: "plain_tool") { id in
            ToolResult(success: true, content: "plain result", toolCallId: id)
        }
        let toolMessage = try #require(try await toolMessagesSentToLLM(via: loop, provider: provider, toolCallId: "call-plain").first)

        #expect(toolMessage.content.contains("plain result"))
        #expect(toolMessage.images.isEmpty)
    }

    @Test("Failed tool result does not attach images", arguments: ToolImageAdapterLoop.allCases)
    func testFailedResultHasNoImages(loop: ToolImageAdapterLoop) async throws {
        let provider = FixedToolResultProvider(toolName: "failing_tool") { id in
            ToolResult(
                success: false,
                parts: [.text("capture failed"), .image(ToolResultImage(data: pngBytes, mediaType: "image/png"))],
                toolCallId: id,
                error: "capture failed"
            )
        }
        let toolMessage = try #require(try await toolMessagesSentToLLM(via: loop, provider: provider, toolCallId: "call-fail").first)

        #expect(toolMessage.content.contains("Error Executing Tool"))
        #expect(toolMessage.images.isEmpty)
    }
}
