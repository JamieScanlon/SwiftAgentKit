import Foundation
import Testing
import EasyJSON
@testable import SwiftAgentKit

/// Mirror of `ToolResult` as it was before `parts` existed, using synthesized Codable.
private struct LegacyToolResult: Codable {
    let success: Bool
    let content: String
    let metadata: JSON
    let toolCallId: String?
    let error: String?
}

/// Mirror of `Message.Image` before `mediaType` existed.
private struct LegacyMessageImage: Codable {
    var name: String
    var path: String?
    var imageData: Data?
    var thumbData: Data?
}

private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01, 0x02, 0x03])

@Suite("ToolResult content parts")
struct ToolResultContentPartsTests {

    @Test("[text, image(png), text] round-trips through Codable with order, bytes and media type")
    func testPartsRoundTrip() throws {
        let image = ToolResultImage(data: pngBytes, mediaType: "image/png", width: 1280, height: 800)
        let original = ToolResult(
            success: true,
            parts: [.text("before"), .image(image), .text("after")],
            metadata: .object(["source": .string("test")]),
            toolCallId: "call-1"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ToolResult.self, from: encoded)

        #expect(decoded == original)
        #expect(decoded.parts.count == 3)
        guard case .text(let first) = decoded.parts[0],
              case .image(let decodedImage) = decoded.parts[1],
              case .text(let last) = decoded.parts[2] else {
            Issue.record("Unexpected part order: \(decoded.parts)")
            return
        }
        #expect(first == "before")
        #expect(last == "after")
        #expect(decodedImage.data == pngBytes)
        #expect(decodedImage.mediaType == "image/png")
        #expect(decodedImage.width == 1280)
        #expect(decodedImage.height == 800)
        #expect(decoded.content == "before\nafter")
    }

    @Test("Payload encoded before parts existed decodes with parts == [] and the same content")
    func testLegacyPayloadDecodes() throws {
        let legacy = LegacyToolResult(
            success: true,
            content: "legacy text",
            metadata: .object(["k": .string("v")]),
            toolCallId: "call-legacy",
            error: nil
        )
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(ToolResult.self, from: data)

        #expect(decoded.parts == [])
        #expect(decoded.content == "legacy text")
        #expect(decoded.toolCallId == "call-legacy")
        #expect(decoded.contentParts == [.text("legacy text")])
    }

    @Test("Text-only result encodes byte-identically to the pre-parts encoding")
    func testTextOnlyEncodesByteIdentically() throws {
        // Sorted keys: Foundation's JSONEncoder does not guarantee key order otherwise, even run to run.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for error in [nil, "boom"] as [String?] {
            let current = ToolResult(
                success: error == nil,
                content: "hello",
                metadata: .object(["source": .string("local")]),
                toolCallId: "call-2",
                error: error
            )
            let legacy = LegacyToolResult(
                success: error == nil,
                content: "hello",
                metadata: .object(["source": .string("local")]),
                toolCallId: "call-2",
                error: error
            )
            #expect(try encoder.encode(current) == encoder.encode(legacy))
        }
        let nilId = ToolResult(success: true, content: "x", toolCallId: nil)
        let legacyNilId = LegacyToolResult(success: true, content: "x", metadata: .object([:]), toolCallId: nil, error: nil)
        #expect(try encoder.encode(nilId) == encoder.encode(legacyNilId))
    }

    @Test("Existing content: initializer behaves as before")
    func testLegacyInitializer() {
        let result = ToolResult(success: true, content: "plain", toolCallId: "call-3")
        #expect(result.content == "plain")
        #expect(result.parts.isEmpty)
        #expect(result.images.isEmpty)
        #expect(result.messageImages.isEmpty)
        #expect(result.contentParts == [.text("plain")])
        #expect(result == ToolResult(success: true, content: "plain", metadata: .object([:]), toolCallId: "call-3", error: nil))
    }

    @Test("Equality compares parts")
    func testEqualityComparesParts() {
        let a = ToolResult(success: true, parts: [.text("t"), .image(ToolResultImage(data: pngBytes, mediaType: "image/png"))], toolCallId: "c")
        let b = ToolResult(success: true, parts: [.text("t"), .image(ToolResultImage(data: pngBytes, mediaType: "image/jpeg"))], toolCallId: "c")
        let textOnly = ToolResult(success: true, content: "t", toolCallId: "c")
        #expect(a != b)
        #expect(a != textOnly)
    }

    @Test("ToolResult.image builds caption + image parts without base64 in content")
    func testImageConvenience() {
        let result = ToolResult.image(pngBytes, mediaType: "image/png", caption: "Screenshot", width: 10, height: 20, toolCallId: "call-4")
        #expect(result.success)
        #expect(result.content == "Screenshot")
        #expect(result.parts.count == 2)
        #expect(result.images.first?.data == pngBytes)
        #expect(!result.content.contains(pngBytes.base64EncodedString()))

        let messageImages = result.messageImages
        #expect(messageImages.count == 1)
        #expect(messageImages[0].name == "call-4-image-1")
        #expect(messageImages[0].mediaType == "image/png")
        #expect(messageImages[0].imageData == pngBytes)

        let uncaptioned = ToolResult.image(pngBytes, mediaType: "image/png", toolCallId: nil)
        #expect(uncaptioned.content == "")
        #expect(uncaptioned.parts.count == 1)
    }

    @Test("URL image reference maps to Message.Image path")
    func testURLReferenceMapsToPath() {
        let fileURL = URL(fileURLWithPath: "/tmp/shot.png")
        let remoteURL = URL(string: "https://example.com/shot.png")!
        let result = ToolResult(
            success: true,
            parts: [
                .image(ToolResultImage(url: fileURL, mediaType: "image/png")),
                .image(ToolResultImage(url: remoteURL, mediaType: "image/webp"))
            ],
            toolCallId: "c"
        )
        let images = result.messageImages
        #expect(images.map(\.path) == ["/tmp/shot.png", "https://example.com/shot.png"])
        #expect(images.map(\.mediaType) == ["image/png", "image/webp"])
        #expect(images.allSatisfy { $0.imageData == nil })
        #expect(Set(images.map(\.name)).count == 2)
    }
}

@Suite("Message.Image media type")
struct MessageImageMediaTypeTests {

    @Test("mediaType survives toJSON / init(from: [String: Sendable])")
    func testDictionaryRoundTrip() {
        let image = Message.Image(name: "img", imageData: pngBytes, mediaType: "image/png")
        let restored = Message.Image(from: image.toJSON(includeImageData: true))
        #expect(restored == image)
        #expect(restored.mediaType == "image/png")
    }

    @Test("mediaType survives toEasyJSON / init(from: JSON)")
    func testEasyJSONRoundTrip() {
        let image = Message.Image(name: "img", imageData: pngBytes, mediaType: "image/jpeg")
        let restored = Message.Image(from: image.toEasyJSON(includeImageData: true))
        #expect(restored == image)
        #expect(restored.mediaType == "image/jpeg")
    }

    @Test("mediaType survives Codable")
    func testCodableRoundTrip() throws {
        let image = Message.Image(name: "img", path: "/p", imageData: pngBytes, mediaType: "image/gif")
        let decoded = try JSONDecoder().decode(Message.Image.self, from: JSONEncoder().encode(image))
        #expect(decoded == image)
        #expect(decoded.mediaType == "image/gif")
    }

    @Test("Older JSON without mediaType decodes with nil, and nil encodes as before")
    func testOlderJSONDecodesNil() throws {
        let legacy = LegacyMessageImage(name: "old", path: nil, imageData: pngBytes, thumbData: nil)
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(Message.Image.self, from: data)
        #expect(decoded.mediaType == nil)
        #expect(decoded.imageData == pngBytes)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(decoded) == encoder.encode(legacy))

        #expect(Message.Image(from: ["name": "old"] as [String: Sendable]).mediaType == nil)
        #expect(Message.Image(from: JSON.object(["name": .string("old")])).mediaType == nil)
    }

    @Test("Message.fromEasyJSON keeps tool images with media type")
    func testToolMessageEasyJSONRoundTrip() {
        let message = Message(
            id: UUID(),
            role: .tool,
            content: "result",
            images: [Message.Image(name: "call-image-1", imageData: pngBytes, mediaType: "image/png")],
            toolCallId: "call"
        )
        let restored = Message.fromEasyJSON(message.toEasyJSON(includeImageData: true))
        #expect(restored?.images == message.images)
        #expect(restored?.images.first?.mediaType == "image/png")
    }
}
