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
} 
