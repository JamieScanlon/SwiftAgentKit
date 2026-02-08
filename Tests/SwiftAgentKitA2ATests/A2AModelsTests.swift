import Testing
import Foundation
@testable import SwiftAgentKitA2A

@Suite("A2AMessagePart Tests")
struct A2AMessagePartTests {
    
    @Test("Text message part encoding")
    func testTextMessagePartEncoding() throws {
        // Given
        let messagePart = A2AMessagePart.text(text: "Hello, World!")
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(messagePart)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then
        #expect(json != nil)
        #expect(json?["kind"] as? String == "text")
        #expect(json?["text"] as? String == "Hello, World!")
    }
    
    @Test("Text message part decoding")
    func testTextMessagePartDecoding() throws {
        // Given
        let json = """
        {
            "kind": "text",
            "text": "Hello, World!"
        }
        """.data(using: .utf8)!
        
        // When
        let decoder = JSONDecoder()
        let messagePart = try decoder.decode(A2AMessagePart.self, from: json)
        
        // Then
        #expect(messagePart == .text(text: "Hello, World!"))
    }
    
    @Test("File message part with URL encoding")
    func testFileMessagePartWithURLEncoding() throws {
        // Given
        let url = URL(string: "https://example.com/file.txt")!
        let messagePart = A2AMessagePart.file(data: nil, url: url)
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(messagePart)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then
        #expect(json != nil)
        #expect(json?["kind"] as? String == "file")
        #expect(json?["file"] as? String == "https://example.com/file.txt")
    }
    
    @Test("File message part with data encoding")
    func testFileMessagePartWithDataEncoding() throws {
        // Given
        let testData = "Test content".data(using: .utf8)!
        let messagePart = A2AMessagePart.file(data: testData, url: nil)
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(messagePart)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then
        #expect(json != nil)
        #expect(json?["kind"] as? String == "file")
        #expect(json?["file"] != nil)
        
        let base64String = json?["file"] as? String
        #expect(base64String != nil, "Base64 string should not be nil")
        let decodedData = Data(base64Encoded: base64String!)
        #expect(decodedData != nil, "Failed to decode base64 data")
        #expect(decodedData == testData)
    }
    
    @Test("File message part decoding")
    func testFileMessagePartDecoding() throws {
        // Given
        let json = """
        {
            "kind": "file",
            "file": "https://example.com/file.txt"
        }
        """.data(using: .utf8)!
        
        // When
        let decoder = JSONDecoder()
        let messagePart = try decoder.decode(A2AMessagePart.self, from: json)
        
        // Then
        let expectedURL = URL(string: "https://example.com/file.txt")!
        #expect(messagePart == .file(data: nil, url: expectedURL))
    }
    
    @Test("Data message part encoding")
    func testDataMessagePartEncoding() throws {
        // Given
        let testData = "Test content".data(using: .utf8)!
        let messagePart = A2AMessagePart.data(data: testData)
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(messagePart)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then
        #expect(json != nil)
        #expect(json?["kind"] as? String == "data")
        #expect(json?["data"] != nil)
        
        let base64String = json?["data"] as? String
        #expect(base64String != nil, "Base64 string should not be nil")
        let decodedData = Data(base64Encoded: base64String!)
        #expect(decodedData != nil, "Failed to decode base64 data")
        #expect(decodedData == testData)
    }
    
    @Test("Data message part decoding")
    func testDataMessagePartDecoding() throws {
        // Given
        let testData = "Test content".data(using: .utf8)!
        let base64String = testData.base64EncodedString()
        let json = """
        {
            "kind": "data",
            "data": "\(base64String)"
        }
        """.data(using: .utf8)!
        
        // When
        let decoder = JSONDecoder()
        let messagePart = try decoder.decode(A2AMessagePart.self, from: json)
        
        // Then
        #expect(messagePart == .data(data: testData))
    }
    
    @Test("Invalid message part decoding")
    func testInvalidMessagePartDecoding() throws {
        // Given
        let invalidJson = """
        {
            "kind": "invalid"
        }
        """.data(using: .utf8)!
        
        // When/Then
        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) {
            try decoder.decode(A2AMessagePart.self, from: invalidJson)
        }
    }
    
    // MARK: - File part URL scheme parsing (http, https, file only)
    
    @Test("File part decodes http URL into url parameter with nil data")
    func testFilePartDecodesHttpURL() throws {
        let json = """
        {"kind": "file", "file": "http://example.com/image.png"}
        """.data(using: .utf8)!
        
        let part = try JSONDecoder().decode(A2AMessagePart.self, from: json)
        
        guard case .file(let data, let url) = part else {
            Issue.record("Expected .file part")
            return
        }
        #expect(data == nil)
        #expect(url != nil)
        #expect(url?.absoluteString == "http://example.com/image.png")
        #expect(url?.scheme == "http")
    }
    
    @Test("File part decodes https URL into url parameter with nil data")
    func testFilePartDecodesHttpsURL() throws {
        let json = """
        {"kind": "file", "file": "https://example.com/image.png"}
        """.data(using: .utf8)!
        
        let part = try JSONDecoder().decode(A2AMessagePart.self, from: json)
        
        guard case .file(let data, let url) = part else {
            Issue.record("Expected .file part")
            return
        }
        #expect(data == nil)
        #expect(url != nil)
        #expect(url?.absoluteString == "https://example.com/image.png")
        #expect(url?.scheme == "https")
    }
    
    @Test("File part decodes file URL into url parameter with nil data")
    func testFilePartDecodesFileURL() throws {
        let json = """
        {"kind": "file", "file": "file:///tmp/image.png"}
        """.data(using: .utf8)!
        
        let part = try JSONDecoder().decode(A2AMessagePart.self, from: json)
        
        guard case .file(let data, let url) = part else {
            Issue.record("Expected .file part")
            return
        }
        #expect(data == nil)
        #expect(url != nil)
        #expect(url?.scheme == "file")
        #expect(url?.path == "/tmp/image.png" || url?.absoluteString == "file:///tmp/image.png")
    }
    
    @Test("File part decodes base64 string into data parameter with nil url")
    func testFilePartDecodesBase64IntoDataNotURL() throws {
        let raw = "Test file content"
        let testData = raw.data(using: .utf8)!
        let base64 = testData.base64EncodedString()
        let json = """
        {"kind": "file", "file": "\(base64)"}
        """.data(using: .utf8)!
        
        let part = try JSONDecoder().decode(A2AMessagePart.self, from: json)
        
        guard case .file(let data, let url) = part else {
            Issue.record("Expected .file part")
            return
        }
        #expect(data != nil, "Base64 should be decoded into data")
        #expect(data == testData)
        #expect(url == nil, "Base64 should not be placed in url parameter")
    }
    
    @Test("File part decodes base64 image data into data parameter")
    func testFilePartDecodesBase64ImageIntoData() throws {
        // Minimal valid PNG (1x1 pixel)
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let json = """
        {"kind": "file", "file": "\(pngBase64)"}
        """.data(using: .utf8)!
        
        let part = try JSONDecoder().decode(A2AMessagePart.self, from: json)
        
        guard case .file(let data, let url) = part else {
            Issue.record("Expected .file part")
            return
        }
        #expect(data != nil)
        #expect(url == nil)
        #expect(data?.count ?? 0 > 0)
        // PNG magic bytes
        let pngSignature = Data([0x89, 0x50, 0x4E, 0x47])
        #expect(data?.prefix(4) == pngSignature)
    }
    
    @Test("File part with invalid string throws")
    func testFilePartInvalidStringThrows() throws {
        // Not a valid URL (no scheme), not valid base64
        let json = """
        {"kind": "file", "file": "not-a-url-or-valid-base64!!!"}
        """.data(using: .utf8)!
        
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(A2AMessagePart.self, from: json)
        }
    }
    
    @Test("File part with missing file key throws")
    func testFilePartMissingFileKeyThrows() throws {
        let json = """
        {"kind": "file"}
        """.data(using: .utf8)!
        
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(A2AMessagePart.self, from: json)
        }
    }
    
    @Test("File part with non-string file value throws")
    func testFilePartNonStringFileThrows() throws {
        let json = """
        {"kind": "file", "file": 123}
        """.data(using: .utf8)!
        
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(A2AMessagePart.self, from: json)
        }
    }
    
    @Test("File part data URL scheme is not treated as URL")
    func testFilePartDataURLDecodedAsBase64WhenPossible() throws {
        // data: URLs are valid URLs but we only allow http/https/file. So data:image/png;base64,XXX
        // should not match the URL branch. It would then try base64 - the whole string is not
        // valid base64 (has "data:image/png;base64," prefix). So it might throw or we need to
        // document behavior. Checking current behavior: URL(string: "data:image/png;base64,iVBORw...")
        // has scheme "data", so we don't use the URL branch. Then Data(base64Encoded: "data:image/png;base64,iVBORw...")
        // fails (invalid base64). So decoding would throw. That's acceptable - we only parse raw base64
        // in the file field. If server sends data URI, they should send raw base64 instead.
        // Test: ensure "data:" prefix string is not stored as url (scheme data is not in our list)
        let json = """
        {"kind": "file", "file": "data:image/png;base64,iVBORw0KGgo="}
        """.data(using: .utf8)!
        
        // Should throw because "data:image/png;base64,iVBORw0KGgo=" is not valid base64 (has prefix)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(A2AMessagePart.self, from: json)
        }
    }
    
    // MARK: - Text part edge cases
    
    @Test("Text part decodes empty string")
    func testTextPartDecodesEmptyString() throws {
        let json = """
        {"kind": "text", "text": ""}
        """.data(using: .utf8)!
        
        let part = try JSONDecoder().decode(A2AMessagePart.self, from: json)
        #expect(part == .text(text: ""))
    }
    
    @Test("Text part decodes text with special characters")
    func testTextPartDecodesSpecialCharacters() throws {
        let json = """
        {"kind": "text", "text": "Line1\\nLine2\\tTab \\\"quote\\\""}
        """.data(using: .utf8)!
        
        let part = try JSONDecoder().decode(A2AMessagePart.self, from: json)
        if case .text(let text) = part {
            #expect(text.contains("Line1"))
            #expect(text.contains("Line2"))
            #expect(text.contains("\""))
        } else {
            Issue.record("Expected .text part")
        }
    }
    
    @Test("Text part with missing text key throws")
    func testTextPartMissingTextKeyThrows() throws {
        let json = """
        {"kind": "text"}
        """.data(using: .utf8)!
        
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(A2AMessagePart.self, from: json)
        }
    }
    
    // MARK: - Data part edge cases
    
    @Test("Data part with invalid base64 throws")
    func testDataPartInvalidBase64Throws() throws {
        let json = """
        {"kind": "data", "data": "not-valid-base64!!!"}
        """.data(using: .utf8)!
        
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(A2AMessagePart.self, from: json)
        }
    }
    
    @Test("Data part with missing data key throws")
    func testDataPartMissingDataKeyThrows() throws {
        let json = """
        {"kind": "data"}
        """.data(using: .utf8)!
        
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(A2AMessagePart.self, from: json)
        }
    }
    
    // MARK: - Root structure
    
    @Test("Decoding non-object JSON throws")
    func testDecodingNonObjectThrows() throws {
        let json = """
        ["array", "not", "object"]
        """.data(using: .utf8)!
        
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(A2AMessagePart.self, from: json)
        }
    }
    
    @Test("Decoding object with missing kind throws")
    func testDecodingMissingKindThrows() throws {
        let json = """
        {"text": "hello"}
        """.data(using: .utf8)!
        
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(A2AMessagePart.self, from: json)
        }
    }
    
    // MARK: - Round-trip
    
    @Test("File part with data round-trips")
    func testFilePartWithDataRoundTrips() throws {
        let original = "Round-trip content".data(using: .utf8)!
        let part = A2AMessagePart.file(data: original, url: nil)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(part)
        let decoded = try JSONDecoder().decode(A2AMessagePart.self, from: data)
        
        guard case .file(let dataOut, let urlOut) = decoded else {
            Issue.record("Expected .file after decode")
            return
        }
        #expect(urlOut == nil)
        #expect(dataOut == original)
    }
    
    @Test("File part with http URL round-trips")
    func testFilePartWithHttpURLRoundTrips() throws {
        let url = URL(string: "http://example.com/resource")!
        let part = A2AMessagePart.file(data: nil, url: url)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(part)
        let decoded = try JSONDecoder().decode(A2AMessagePart.self, from: data)
        
        #expect(decoded == .file(data: nil, url: url))
    }
    
    @Test("Text part round-trips")
    func testTextPartRoundTrips() throws {
        let part = A2AMessagePart.text(text: "Round-trip")
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(A2AMessagePart.self, from: data)
        #expect(decoded == part)
    }
    
    @Test("Data part round-trips")
    func testDataPartRoundTrips() throws {
        let original = "Data content".data(using: .utf8)!
        let part = A2AMessagePart.data(data: original)
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(A2AMessagePart.self, from: data)
        #expect(decoded == .data(data: original))
    }
} 
