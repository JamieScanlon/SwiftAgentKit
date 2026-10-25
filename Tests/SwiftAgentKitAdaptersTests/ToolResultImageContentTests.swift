import Foundation
import Testing
import MCP
import EasyJSON
import SwiftAgentKit
import SwiftAgentKitA2A
@testable import SwiftAgentKitAdapters
@testable import SwiftAgentKitMCP

private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0xDE, 0xAD, 0xBE, 0xEF])
private let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])

/// Starts an in-process MCP server exposing `screenshot` ([text, image/png, text]) and
/// `render` ([embedded image/jpeg resource blob]), and returns a connected `MCPClient` with tools listed.
private func connectedImageServerClient() async throws -> (client: MCPClient, server: Server) {
    let server = Server(name: "image-server", version: "1.0", capabilities: .init(tools: .init()))
    await server.withMethodHandler(ListTools.self) { _ in
        ListTools.Result(tools: [
            Tool(name: "screenshot", description: "Returns a screenshot", inputSchema: .object(["type": .string("object")])),
            Tool(name: "render", description: "Returns a rendered image resource", inputSchema: .object(["type": .string("object")]))
        ])
    }
    await server.withMethodHandler(CallTool.self) { params in
        switch params.name {
        case "screenshot":
            return CallTool.Result(content: [
                .text(text: "Captured screen", annotations: nil, _meta: nil),
                .image(
                    data: pngBytes.base64EncodedString(),
                    mimeType: "image/png",
                    annotations: nil,
                    _meta: Metadata(additionalFields: ["width": .int(1280), "height": .int(800)])
                ),
                .text(text: "1280x800", annotations: nil, _meta: nil)
            ])
        case "render":
            return CallTool.Result(content: [
                .resource(resource: .binary(jpegBytes, uri: "render://chart", mimeType: "image/jpeg")),
                .resource(resource: .binary(Data([0x01, 0x02]), uri: "render://raw", mimeType: "application/octet-stream"))
            ])
        default:
            return CallTool.Result(content: [], isError: true)
        }
    }

    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
    try await server.start(transport: serverTransport)
    let client = MCPClient(name: "image-client", connectionTimeout: 5, toolCallTimeout: 5)
    try await client.connect(transport: clientTransport)
    try await client.getTools()
    return (client, server)
}

@Suite("Tool result image content", .serialized)
struct ToolResultImageContentTests {

    // MARK: MCP

    @Test("MCPToolProvider yields [text, image/png, text] parts in order with decoded bytes")
    func testMCPToolProviderImageParts() async throws {
        let (client, server) = try await connectedImageServerClient()
        defer { Task { await client.shutdown(); await server.stop() } }

        let provider = MCPToolProvider(clients: [client])
        let result = try await provider.executeTool(ToolCall(name: "screenshot", arguments: .object([:]), id: "call-shot"))

        #expect(result.success)
        #expect(result.parts.count == 3)
        guard result.parts.count == 3,
              case .text(let first) = result.parts[0],
              case .image(let image) = result.parts[1],
              case .text(let last) = result.parts[2] else {
            Issue.record("Unexpected parts: \(result.parts)")
            return
        }
        #expect(first == "Captured screen")
        #expect(last == "1280x800")
        #expect(image.data == pngBytes)
        #expect(image.mediaType == "image/png")
        #expect(image.width == 1280)
        #expect(image.height == 800)
        #expect(result.content == "Captured screen\n1280x800")
        #expect(!result.content.contains(pngBytes.base64EncodedString()))
    }

    @Test("MCP embedded image/* resource with a blob becomes an image part; other resources do not")
    func testMCPEmbeddedImageResource() async throws {
        let (client, server) = try await connectedImageServerClient()
        defer { Task { await client.shutdown(); await server.stop() } }

        let provider = MCPToolProvider(clients: [client])
        let result = try await provider.executeTool(ToolCall(name: "render", arguments: .object([:]), id: "call-render"))

        #expect(result.success)
        #expect(result.images.count == 1)
        #expect(result.images.first?.data == jpegBytes)
        #expect(result.images.first?.mediaType == "image/jpeg")
        #expect(result.content == "")
    }

    @Test("MCPManager.toolCall yields a tool Message with one image carrying its media type")
    func testMCPManagerToolCallImage() async throws {
        let (client, server) = try await connectedImageServerClient()
        defer { Task { await server.stop() } }

        let manager = MCPManager(connectionTimeout: 5)
        try await manager.initialize(clients: [client])
        defer { Task { await manager.shutdown() } }

        let responses = try #require(await manager.toolCall(ToolCall(name: "screenshot", arguments: .object([:]), id: "call-mgr")))
        #expect(responses.map(\.content) == ["Captured screen", "1280x800"])
        #expect(responses.flatMap(\.images).count == 1)

        // Same conversion the orchestrator applies to each MCP response.
        let toolMessages = responses.map { response in
            Message(id: UUID(), role: .tool, content: response.content, images: response.images, toolCallId: "call-mgr")
        }
        let imageMessages = toolMessages.filter { !$0.images.isEmpty }
        #expect(imageMessages.count == 1)
        let image = try #require(imageMessages.first?.images.first)
        #expect(image.mediaType == "image/png")
        #expect(image.imageData == pngBytes)
        #expect(toolMessages.allSatisfy { !$0.content.contains(pngBytes.base64EncodedString()) })
    }

    @Test("MCPManager.llmResponses carries image-only results on an empty-content response")
    func testMCPManagerImageOnlyResponse() {
        let responses = MCPManager.llmResponses(
            from: [.resource(resource: .binary(jpegBytes, uri: "render://chart", mimeType: "image/jpeg"))],
            toolCallId: "call-img"
        )
        #expect(responses.count == 1)
        #expect(responses.first?.content == "")
        #expect(responses.first?.images.first?.mediaType == "image/jpeg")
        #expect(responses.first?.images.first?.imageData == jpegBytes)
    }

    // MARK: A2A

    @Test("A2A file part with an image/* media type becomes an image part")
    func testA2AImageFilePart() {
        let message = A2AMessage(
            role: "agent",
            parts: [
                .text(text: "Here is the chart"),
                .file(data: pngBytes, url: nil, mimeType: "image/png", name: "chart.png"),
                .text(text: "done")
            ],
            messageId: "m1"
        )
        let result = A2AToolProvider.toolResult(from: message, toolCallId: "call-a2a")
        #expect(result.parts.count == 3)
        #expect(result.images.first?.data == pngBytes)
        #expect(result.images.first?.mediaType == "image/png")
        #expect(result.content == "Here is the chart done")
        #expect(!result.content.contains(pngBytes.base64EncodedString()))
        #expect(result.messageImages.first?.mediaType == "image/png")
    }

    @Test("A2A file part without a media type behaves as before")
    func testA2AFilePartWithoutMediaType() {
        let message = A2AMessage(
            role: "agent",
            parts: [.text(text: "a"), .file(data: pngBytes, url: nil), .text(text: "b")],
            messageId: "m2"
        )
        let result = A2AToolProvider.toolResult(from: message, toolCallId: "call-a2a")
        #expect(result == ToolResult(success: true, content: "a b", metadata: .object(["source": .string("a2a_agent")]), toolCallId: "call-a2a"))
        #expect(result.parts.isEmpty)
    }
}
