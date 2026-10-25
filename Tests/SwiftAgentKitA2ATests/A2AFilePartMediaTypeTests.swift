import Foundation
import Testing
import EasyJSON
@testable import SwiftAgentKitA2A

private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01])

@Suite("A2A file part media type")
struct A2AFilePartMediaTypeTests {

    private func decodePart(_ json: String) throws -> A2AMessagePart {
        try JSONDecoder().decode(A2AMessagePart.self, from: Data(json.utf8))
    }

    @Test("mimeType and name round-trip through Codable")
    func testRoundTrip() throws {
        let part = A2AMessagePart.file(data: pngBytes, url: nil, mimeType: "image/png", name: "shot.png")
        let decoded = try JSONDecoder().decode(A2AMessagePart.self, from: JSONEncoder().encode(part))
        #expect(decoded == part)
    }

    @Test("A file part without mimeType or name encodes exactly as before")
    func testLegacyEncodingUnchanged() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(A2AMessagePart.file(data: pngBytes, url: nil))
        let expected = try encoder.encode(["kind": "file", "file": pngBytes.base64EncodedString()])
        #expect(encoded == expected)
    }

    @Test("Legacy string-form file part decodes with nil mimeType and name")
    func testLegacyDecode() throws {
        let part = try decodePart(#"{"kind":"file","file":"\#(pngBytes.base64EncodedString())"}"#)
        #expect(part == .file(data: pngBytes, url: nil, mimeType: nil, name: nil))
    }

    @Test("A2A spec object-form FilePart decodes bytes or uri with mimeType and name")
    func testSpecObjectFormDecode() throws {
        let bytesPart = try decodePart(
            #"{"kind":"file","file":{"bytes":"\#(pngBytes.base64EncodedString())","mimeType":"image/png","name":"shot.png"}}"#
        )
        #expect(bytesPart == .file(data: pngBytes, url: nil, mimeType: "image/png", name: "shot.png"))

        let uriPart = try decodePart(#"{"kind":"file","file":{"uri":"https://example.com/a.jpg","mimeType":"image/jpeg"}}"#)
        #expect(uriPart == .file(data: nil, url: URL(string: "https://example.com/a.jpg"), mimeType: "image/jpeg", name: nil))
    }
}
