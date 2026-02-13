//
//  LLMResponseFileTests.swift
//  SwiftAgentKitTests
//
//  Comprehensive tests for LLMResponseFile and LLMResponse.files
//

import Foundation
import Testing
import SwiftAgentKit
import EasyJSON

@Suite("LLMResponseFile Tests")
struct LLMResponseFileTests {

    // MARK: - Init (defaults and all parameters)

    @Test("LLMResponseFile init with no arguments has all nil")
    func testInitDefault() throws {
        let f = LLMResponseFile()
        #expect(f.name == nil)
        #expect(f.mimeType == nil)
        #expect(f.data == nil)
        #expect(f.url == nil)
    }

    @Test("LLMResponseFile init with name only")
    func testInitNameOnly() throws {
        let f = LLMResponseFile(name: "doc.pdf")
        #expect(f.name == "doc.pdf")
        #expect(f.mimeType == nil)
        #expect(f.data == nil)
        #expect(f.url == nil)
    }

    @Test("LLMResponseFile init with all parameters")
    func testInitAllParameters() throws {
        let data = Data([0x01, 0x02, 0x03])
        let url = URL(string: "https://example.com/file.pdf")!
        let f = LLMResponseFile(name: "file.pdf", mimeType: "application/pdf", data: data, url: url)
        #expect(f.name == "file.pdf")
        #expect(f.mimeType == "application/pdf")
        #expect(f.data == data)
        #expect(f.url == url)
    }

    @Test("LLMResponseFile init with data only")
    func testInitDataOnly() throws {
        let data = Data([0x25, 0x50, 0x44, 0x46])
        let f = LLMResponseFile(data: data)
        #expect(f.name == nil)
        #expect(f.mimeType == nil)
        #expect(f.data == data)
        #expect(f.url == nil)
    }

    @Test("LLMResponseFile init with url only")
    func testInitURLOnly() throws {
        let url = URL(string: "file:///tmp/out.pdf")!
        let f = LLMResponseFile(url: url)
        #expect(f.name == nil)
        #expect(f.mimeType == nil)
        #expect(f.data == nil)
        #expect(f.url == url)
    }

    // MARK: - Decode from JSON

    @Test("LLMResponseFile init from JSON with all fields")
    func testInitFromJSONAllFields() throws {
        let payload = Data([0x01, 0x02, 0x03])
        let b64 = payload.base64EncodedString()
        let json: JSON = .object([
            "name": .string("a.pdf"),
            "mimeType": .string("application/pdf"),
            "data": .string(b64),
            "url": .string("https://example.com/a.pdf")
        ])
        let f = LLMResponseFile(from: json)
        #expect(f != nil)
        #expect(f?.name == "a.pdf")
        #expect(f?.mimeType == "application/pdf")
        #expect(f?.data == payload)
        #expect(f?.url == URL(string: "https://example.com/a.pdf"))
    }

    @Test("LLMResponseFile init from JSON with only name and url")
    func testInitFromJSONNameAndURL() throws {
        let json: JSON = .object([
            "name": .string("ref.txt"),
            "url": .string("https://example.com/ref.txt")
        ])
        let f = LLMResponseFile(from: json)
        #expect(f != nil)
        #expect(f?.name == "ref.txt")
        #expect(f?.mimeType == nil)
        #expect(f?.data == nil)
        #expect(f?.url == URL(string: "https://example.com/ref.txt"))
    }

    @Test("LLMResponseFile init from JSON with only data base64")
    func testInitFromJSONDataOnly() throws {
        let payload = Data([0x48, 0x65, 0x6c, 0x6c, 0x6f]) // "Hello"
        let json: JSON = .object(["data": .string(payload.base64EncodedString())])
        let f = LLMResponseFile(from: json)
        #expect(f != nil)
        #expect(f?.name == nil)
        #expect(f?.mimeType == nil)
        #expect(f?.data == payload)
        #expect(f?.url == nil)
    }

    @Test("LLMResponseFile init from JSON empty object")
    func testInitFromJSONEmptyObject() throws {
        let json: JSON = .object([:])
        let f = LLMResponseFile(from: json)
        #expect(f != nil)
        #expect(f?.name == nil)
        #expect(f?.mimeType == nil)
        #expect(f?.data == nil)
        #expect(f?.url == nil)
    }

    @Test("LLMResponseFile init from JSON non-object returns nil")
    func testInitFromJSONNonObjectReturnsNil() throws {
        #expect(LLMResponseFile(from: .string("x")) == nil)
        #expect(LLMResponseFile(from: .array([])) == nil)
        #expect(LLMResponseFile(from: .integer(1)) == nil)
    }

    @Test("LLMResponseFile init from JSON invalid base64 data yields nil data")
    func testInitFromJSONInvalidBase64() throws {
        let json: JSON = .object([
            "name": .string("x"),
            "data": .string("not-valid-base64!!!")
        ])
        let f = LLMResponseFile(from: json)
        #expect(f != nil)
        #expect(f?.name == "x")
        #expect(f?.data == nil)
    }

    @Test("LLMResponseFile init from JSON invalid url yields nil url")
    func testInitFromJSONInvalidURL() throws {
        // Empty string and other strings that URL(string:) cannot parse return nil
        let json: JSON = .object(["url": .string("")])
        let f = LLMResponseFile(from: json)
        #expect(f != nil)
        #expect(f?.url == nil)
    }

    @Test("LLMResponseFile init from JSON file URL")
    func testInitFromJSONFileURL() throws {
        let json: JSON = .object(["url": .string("file:///tmp/local.pdf")])
        let f = LLMResponseFile(from: json)
        #expect(f != nil)
        #expect(f?.url == URL(string: "file:///tmp/local.pdf"))
    }

    // MARK: - Encode to JSON (toJSON)

    @Test("LLMResponseFile toJSON round-trip with all fields")
    func testToJSONRoundTripAllFields() throws {
        let data = Data([0x01, 0x02])
        let url = URL(string: "https://ex.com/f")!
        let original = LLMResponseFile(name: "f", mimeType: "application/octet-stream", data: data, url: url)
        let json = original.toJSON()
        let decoded = LLMResponseFile(from: json)
        #expect(decoded != nil)
        #expect(decoded?.name == original.name)
        #expect(decoded?.mimeType == original.mimeType)
        #expect(decoded?.data == original.data)
        #expect(decoded?.url == original.url)
    }

    @Test("LLMResponseFile toJSON round-trip with data only")
    func testToJSONRoundTripDataOnly() throws {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let original = LLMResponseFile(data: data)
        let json = original.toJSON()
        let decoded = LLMResponseFile(from: json)
        #expect(decoded != nil)
        #expect(decoded?.data == data)
    }

    @Test("LLMResponseFile toJSON omits nil fields")
    func testToJSONOmitsNilFields() throws {
        let f = LLMResponseFile()
        let json = f.toJSON()
        guard case .object(let dict) = json else {
            Issue.record("Expected object")
            return
        }
        #expect(dict.isEmpty)
    }

    @Test("LLMResponseFile toJSON includes only set fields")
    func testToJSONIncludesOnlySetFields() throws {
        let f = LLMResponseFile(name: "n", mimeType: "text/plain")
        let json = f.toJSON()
        guard case .object(let dict) = json else {
            Issue.record("Expected object")
            return
        }
        #expect(dict["name"] != nil)
        #expect(dict["mimeType"] != nil)
        #expect(dict["data"] == nil)
        #expect(dict["url"] == nil)
    }

    // MARK: - LLMResponse.files from metadata

    @Test("LLMResponse files returns empty when metadata nil")
    func testResponseFilesEmptyWhenMetadataNil() throws {
        let response = LLMResponse.complete(content: "Hi")
        #expect(response.metadata == nil)
        #expect(response.files.isEmpty)
    }

    @Test("LLMResponse files returns empty when modelMetadata nil")
    func testResponseFilesEmptyWhenModelMetadataNil() throws {
        let metadata = LLMMetadata(promptTokens: 1, completionTokens: 2)
        let response = LLMResponse.complete(content: "Hi", metadata: metadata)
        #expect(response.files.isEmpty)
    }

    @Test("LLMResponse files returns empty when files key missing")
    func testResponseFilesEmptyWhenFilesKeyMissing() throws {
        let metadata = LLMMetadata(modelMetadata: .object(["other": .string("value")]))
        let response = LLMResponse.complete(content: "Hi", metadata: metadata)
        #expect(response.files.isEmpty)
    }

    @Test("LLMResponse files returns empty when files is empty array")
    func testResponseFilesEmptyWhenFilesEmptyArray() throws {
        let metadata = LLMMetadata(modelMetadata: .object(["files": .array([])]))
        let response = LLMResponse.complete(content: "Hi", metadata: metadata)
        #expect(response.files.isEmpty)
    }

    @Test("LLMResponse files extracts single file from metadata")
    func testResponseFilesExtractsSingleFile() throws {
        let url = URL(string: "https://example.com/doc.pdf")!
        let file = LLMResponseFile(name: "doc.pdf", mimeType: "application/pdf", data: nil, url: url)
        let modelMetadata = JSON.object(["files": .array([file.toJSON()])])
        let metadata = LLMMetadata(modelMetadata: modelMetadata)
        let response = LLMResponse.complete(content: "Done", metadata: metadata)
        #expect(response.files.count == 1)
        #expect(response.files[0].name == "doc.pdf")
        #expect(response.files[0].mimeType == "application/pdf")
        #expect(response.files[0].url == url)
        #expect(response.files[0].data == nil)
    }

    @Test("LLMResponse files extracts multiple files from metadata")
    func testResponseFilesExtractsMultipleFiles() throws {
        let f1 = LLMResponseFile(name: "a", url: URL(string: "https://a.com")!)
        let f2 = LLMResponseFile(name: "b", data: Data([0x01]))
        let modelMetadata = JSON.object(["files": .array([f1.toJSON(), f2.toJSON()])])
        let metadata = LLMMetadata(modelMetadata: modelMetadata)
        let response = LLMResponse.complete(content: "Done", metadata: metadata)
        #expect(response.files.count == 2)
        #expect(response.files[0].name == "a")
        #expect(response.files[1].name == "b")
        #expect(response.files[1].data == Data([0x01]))
    }

    @Test("LLMResponse files skips invalid array elements")
    func testResponseFilesSkipsInvalidElements() throws {
        let valid = LLMResponseFile(name: "valid", url: URL(string: "https://v.com")!)
        let modelMetadata = JSON.object([
            "files": .array([
                .string("not an object"),
                valid.toJSON(),
                .object([:])  // valid empty object
            ])
        ])
        let metadata = LLMMetadata(modelMetadata: modelMetadata)
        let response = LLMResponse.complete(content: "Done", metadata: metadata)
        #expect(response.files.count == 2)
        #expect(response.files.contains { $0.name == "valid" })
    }

    @Test("LLMResponse files and images can coexist in metadata")
    func testResponseFilesAndImagesCoexist() throws {
        let file = LLMResponseFile(name: "f", url: URL(string: "https://f.com")!)
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let image = Message.Image(name: "img", imageData: imageData)
        let modelMetadata = JSON.object([
            "files": .array([file.toJSON()]),
            "images": .array([image.toEasyJSON(includeImageData: true, includeThumbData: false)])
        ])
        let metadata = LLMMetadata(modelMetadata: modelMetadata)
        let response = LLMResponse.complete(content: "Done", metadata: metadata)
        #expect(response.files.count == 1)
        #expect(response.files[0].name == "f")
        #expect(response.images.count == 1)
        #expect(response.images[0].name == "img")
    }
}
