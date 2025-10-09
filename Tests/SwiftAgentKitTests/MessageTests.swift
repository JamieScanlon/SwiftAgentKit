import Testing
import Foundation
import EasyJSON
@testable import SwiftAgentKit

// Helper functions for comparing JSON values
fileprivate func expectJSONString(_ json: JSON?, equals expected: String, sourceLocation: SourceLocation = #_sourceLocation) {
    guard case .string(let value) = json else {
        Issue.record("Expected .string(\"\(expected)\"), got \(String(describing: json))", sourceLocation: sourceLocation)
        return
    }
    #expect(value == expected, sourceLocation: sourceLocation)
}

fileprivate func expectJSONIsNil(_ json: JSON?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(json == nil, sourceLocation: sourceLocation)
}

fileprivate func expectJSONArray(_ json: JSON?, hasCount expected: Int, sourceLocation: SourceLocation = #_sourceLocation) {
    guard case .array(let array) = json else {
        Issue.record("Expected array with \(expected) elements, got \(String(describing: json))", sourceLocation: sourceLocation)
        return
    }
    #expect(array.count == expected, sourceLocation: sourceLocation)
}

@Suite("Message Tests")
struct MessageTests {
    
    // MARK: - Message.Image EasyJSON Tests
    
    @Test("Image init(from: JSON) - Valid JSON with all fields")
    func testImageInitFromJSONWithAllFields() throws {
        let imageData = "test-image-data".data(using: .utf8)!
        let thumbData = "test-thumb-data".data(using: .utf8)!
        
        let json = JSON.object([
            "name": .string("test-image"),
            "path": .string("/path/to/image.jpg"),
            "imageData": .string(imageData.base64EncodedString()),
            "thumbData": .string(thumbData.base64EncodedString())
        ])
        
        let image = Message.Image(from: json)
        
        #expect(image.name == "test-image")
        #expect(image.path == "/path/to/image.jpg")
        #expect(image.imageData == imageData)
        #expect(image.thumbData == thumbData)
    }
    
    @Test("Image init(from: JSON) - Valid JSON with required fields only")
    func testImageInitFromJSONWithRequiredFieldsOnly() throws {
        let json = JSON.object([
            "name": .string("test-image")
        ])
        
        let image = Message.Image(from: json)
        
        #expect(image.name == "test-image")
        #expect(image.path == nil)
        #expect(image.imageData == nil)
        #expect(image.thumbData == nil)
    }
    
    @Test("Image init(from: JSON) - Missing name generates UUID")
    func testImageInitFromJSONWithMissingName() throws {
        let json = JSON.object([
            "path": .string("/path/to/image.jpg")
        ])
        
        let image = Message.Image(from: json)
        
        #expect(!image.name.isEmpty)
        #expect(UUID(uuidString: image.name) != nil) // Should be a valid UUID
        #expect(image.path == "/path/to/image.jpg")
    }
    
    @Test("Image init(from: JSON) - Invalid JSON type")
    func testImageInitFromJSONWithInvalidType() throws {
        let json = JSON.string("not an object")
        
        let image = Message.Image(from: json)
        
        #expect(!image.name.isEmpty)
        #expect(UUID(uuidString: image.name) != nil)
        #expect(image.path == nil)
        #expect(image.imageData == nil)
        #expect(image.thumbData == nil)
    }
    
    @Test("Image toEasyJSON - With all data")
    func testImageToEasyJSONWithAllData() throws {
        let imageData = "test-image-data".data(using: .utf8)!
        let thumbData = "test-thumb-data".data(using: .utf8)!
        
        let image = Message.Image(
            name: "test-image",
            path: "/path/to/image.jpg",
            imageData: imageData,
            thumbData: thumbData
        )
        
        let json = image.toEasyJSON(includeImageData: true, includeThumbData: true)
        
        guard case .object(let dict) = json else {
            #expect(Bool(false), "JSON should be an object")
            return
        }
        
        expectJSONString(dict["name"], equals: "test-image")
        expectJSONString(dict["path"], equals: "/path/to/image.jpg")
        expectJSONString(dict["imageData"], equals: imageData.base64EncodedString())
        expectJSONString(dict["thumbData"], equals: thumbData.base64EncodedString())
    }
    
    @Test("Image toEasyJSON - Exclude image data")
    func testImageToEasyJSONExcludeImageData() throws {
        let imageData = "test-image-data".data(using: .utf8)!
        let thumbData = "test-thumb-data".data(using: .utf8)!
        
        let image = Message.Image(
            name: "test-image",
            path: "/path/to/image.jpg",
            imageData: imageData,
            thumbData: thumbData
        )
        
        let json = image.toEasyJSON(includeImageData: false, includeThumbData: true)
        
        guard case .object(let dict) = json else {
            #expect(Bool(false), "JSON should be an object")
            return
        }
        
        expectJSONString(dict["name"], equals: "test-image")
        expectJSONString(dict["path"], equals: "/path/to/image.jpg")
        expectJSONIsNil(dict["imageData"])
        expectJSONString(dict["thumbData"], equals: thumbData.base64EncodedString())
    }
    
    @Test("Image toEasyJSON - Exclude thumb data")
    func testImageToEasyJSONExcludeThumbData() throws {
        let imageData = "test-image-data".data(using: .utf8)!
        let thumbData = "test-thumb-data".data(using: .utf8)!
        
        let image = Message.Image(
            name: "test-image",
            path: "/path/to/image.jpg",
            imageData: imageData,
            thumbData: thumbData
        )
        
        let json = image.toEasyJSON(includeImageData: true, includeThumbData: false)
        
        guard case .object(let dict) = json else {
            #expect(Bool(false), "JSON should be an object")
            return
        }
        
        expectJSONString(dict["name"], equals: "test-image")
        expectJSONString(dict["path"], equals: "/path/to/image.jpg")
        expectJSONString(dict["imageData"], equals: imageData.base64EncodedString())
        expectJSONIsNil(dict["thumbData"])
    }
    
    @Test("Image round-trip - EasyJSON")
    func testImageRoundTripEasyJSON() throws {
        let imageData = "test-image-data".data(using: .utf8)!
        let thumbData = "test-thumb-data".data(using: .utf8)!
        
        let original = Message.Image(
            name: "test-image",
            path: "/path/to/image.jpg",
            imageData: imageData,
            thumbData: thumbData
        )
        
        let json = original.toEasyJSON(includeImageData: true, includeThumbData: true)
        let reconstructed = Message.Image(from: json)
        
        #expect(reconstructed.name == original.name)
        #expect(reconstructed.path == original.path)
        #expect(reconstructed.imageData == original.imageData)
        #expect(reconstructed.thumbData == original.thumbData)
    }
    
    // MARK: - Message EasyJSON Tests
    
    @Test("Message toEasyJSON - Complete message")
    func testMessageToEasyJSONComplete() throws {
        let id = UUID()
        let timestamp = Date()
        let formatter = ISO8601DateFormatter()
        
        let image = Message.Image(name: "test-image", path: "/path/to/image.jpg")
        let message = Message(
            id: id,
            role: .user,
            content: "Hello, world!",
            timestamp: timestamp,
            images: [image],
            toolCalls: ["tool1", "tool2"],
            responseFormat: "json"
        )
        
        let json = message.toEasyJSON()
        
        guard case .object(let dict) = json else {
            #expect(Bool(false), "JSON should be an object")
            return
        }
        
        expectJSONString(dict["id"], equals: id.uuidString)
        expectJSONString(dict["role"], equals: "user")
        expectJSONString(dict["content"], equals: "Hello, world!")
        expectJSONString(dict["timestamp"], equals: formatter.string(from: timestamp))
        expectJSONString(dict["responseFormat"], equals: "json")
        
        // Verify toolCalls array
        guard case .array(let toolCallsArray) = dict["toolCalls"] else {
            #expect(Bool(false), "toolCalls should be an array")
            return
        }
        #expect(toolCallsArray.count == 2)
        expectJSONString(toolCallsArray[0], equals: "tool1")
        expectJSONString(toolCallsArray[1], equals: "tool2")
        
        // Verify images array
        guard case .array(let imagesArray) = dict["images"] else {
            #expect(Bool(false), "images should be an array")
            return
        }
        #expect(imagesArray.count == 1)
    }
    
    @Test("Message toEasyJSON - Minimal message")
    func testMessageToEasyJSONMinimal() throws {
        let id = UUID()
        let message = Message(
            id: id,
            role: .assistant,
            content: "Response"
        )
        
        let json = message.toEasyJSON()
        
        guard case .object(let dict) = json else {
            #expect(Bool(false), "JSON should be an object")
            return
        }
        
        expectJSONString(dict["id"], equals: id.uuidString)
        expectJSONString(dict["role"], equals: "assistant")
        expectJSONString(dict["content"], equals: "Response")
        
        // Verify empty arrays
        guard case .array(let toolCallsArray) = dict["toolCalls"] else {
            #expect(Bool(false), "toolCalls should be an array")
            return
        }
        #expect(toolCallsArray.isEmpty)
        
        guard case .array(let imagesArray) = dict["images"] else {
            #expect(Bool(false), "images should be an array")
            return
        }
        #expect(imagesArray.isEmpty)
    }
    
    @Test("Message fromEasyJSON - Complete message")
    func testMessageFromEasyJSONComplete() throws {
        let id = UUID()
        let timestamp = Date()
        let formatter = ISO8601DateFormatter()
        
        let json = JSON.object([
            "id": .string(id.uuidString),
            "role": .string("user"),
            "content": .string("Hello, world!"),
            "timestamp": .string(formatter.string(from: timestamp)),
            "toolCalls": .array([.string("tool1"), .string("tool2")]),
            "images": .array([
                .object([
                    "name": .string("test-image"),
                    "path": .string("/path/to/image.jpg")
                ])
            ]),
            "responseFormat": .string("json")
        ])
        
        guard let message = Message.fromEasyJSON(json) else {
            #expect(Bool(false), "Should successfully parse message")
            return
        }
        
        #expect(message.id == id)
        #expect(message.role == .user)
        #expect(message.content == "Hello, world!")
        #expect(message.toolCalls.count == 2)
        #expect(message.toolCalls[0] == "tool1")
        #expect(message.toolCalls[1] == "tool2")
        #expect(message.images.count == 1)
        #expect(message.images[0].name == "test-image")
        #expect(message.responseFormat == "json")
    }
    
    @Test("Message fromEasyJSON - Minimal message")
    func testMessageFromEasyJSONMinimal() throws {
        let id = UUID()
        let timestamp = Date()
        let formatter = ISO8601DateFormatter()
        
        let json = JSON.object([
            "id": .string(id.uuidString),
            "role": .string("assistant"),
            "content": .string("Response"),
            "timestamp": .string(formatter.string(from: timestamp)),
            "toolCalls": .array([]),
            "images": .array([]),
            "responseFormat": .string("")
        ])
        
        guard let message = Message.fromEasyJSON(json) else {
            #expect(Bool(false), "Should successfully parse message")
            return
        }
        
        #expect(message.id == id)
        #expect(message.role == .assistant)
        #expect(message.content == "Response")
        #expect(message.toolCalls.isEmpty)
        #expect(message.images.isEmpty)
        #expect(message.responseFormat == nil) // Empty string should become nil
    }
    
    @Test("Message fromEasyJSON - Invalid JSON type")
    func testMessageFromEasyJSONInvalidType() throws {
        let json = JSON.string("not an object")
        
        let message = Message.fromEasyJSON(json)
        
        #expect(message == nil)
    }
    
    @Test("Message fromEasyJSON - Missing required fields")
    func testMessageFromEasyJSONMissingFields() throws {
        let json = JSON.object([
            "id": .string(UUID().uuidString),
            "role": .string("user")
            // Missing content and timestamp
        ])
        
        let message = Message.fromEasyJSON(json)
        
        #expect(message == nil)
    }
    
    @Test("Message fromEasyJSON - Invalid UUID")
    func testMessageFromEasyJSONInvalidUUID() throws {
        let timestamp = Date()
        let formatter = ISO8601DateFormatter()
        
        let json = JSON.object([
            "id": .string("not-a-uuid"),
            "role": .string("user"),
            "content": .string("Hello"),
            "timestamp": .string(formatter.string(from: timestamp))
        ])
        
        let message = Message.fromEasyJSON(json)
        
        #expect(message == nil)
    }
    
    @Test("Message fromEasyJSON - Invalid role")
    func testMessageFromEasyJSONInvalidRole() throws {
        let timestamp = Date()
        let formatter = ISO8601DateFormatter()
        
        let json = JSON.object([
            "id": .string(UUID().uuidString),
            "role": .string("invalid_role"),
            "content": .string("Hello"),
            "timestamp": .string(formatter.string(from: timestamp))
        ])
        
        let message = Message.fromEasyJSON(json)
        
        #expect(message == nil)
    }
    
    @Test("Message fromEasyJSON - Invalid timestamp")
    func testMessageFromEasyJSONInvalidTimestamp() throws {
        let json = JSON.object([
            "id": .string(UUID().uuidString),
            "role": .string("user"),
            "content": .string("Hello"),
            "timestamp": .string("not-a-timestamp")
        ])
        
        let message = Message.fromEasyJSON(json)
        
        #expect(message == nil)
    }
    
    @Test("Message round-trip - EasyJSON")
    func testMessageRoundTripEasyJSON() throws {
        let id = UUID()
        let imageData = "test-image".data(using: .utf8)!
        let image = Message.Image(
            name: "test-image",
            path: "/path/to/image.jpg",
            imageData: imageData
        )
        
        let original = Message(
            id: id,
            role: .user,
            content: "Hello, world!",
            timestamp: Date(),
            images: [image],
            toolCalls: ["tool1", "tool2"],
            responseFormat: "json"
        )
        
        let json = original.toEasyJSON(includeImageData: true)
        guard let reconstructed = Message.fromEasyJSON(json) else {
            #expect(Bool(false), "Should successfully reconstruct message")
            return
        }
        
        #expect(reconstructed.id == original.id)
        #expect(reconstructed.role == original.role)
        #expect(reconstructed.content == original.content)
        #expect(reconstructed.toolCalls == original.toolCalls)
        #expect(reconstructed.images.count == original.images.count)
        #expect(reconstructed.images[0].name == original.images[0].name)
        #expect(reconstructed.images[0].path == original.images[0].path)
        #expect(reconstructed.responseFormat == original.responseFormat)
        
        // Verify timestamps are very close (allow for sub-second differences from encoding/decoding)
        let timeDiff = abs(reconstructed.timestamp.timeIntervalSince(original.timestamp))
        #expect(timeDiff < 1.0)
    }
    
    @Test("Message round-trip - EasyJSON without optional fields")
    func testMessageRoundTripEasyJSONNoOptionalFields() throws {
        let original = Message(
            id: UUID(),
            role: .assistant,
            content: "Simple response"
        )
        
        let json = original.toEasyJSON()
        guard let reconstructed = Message.fromEasyJSON(json) else {
            #expect(Bool(false), "Should successfully reconstruct message")
            return
        }
        
        #expect(reconstructed.id == original.id)
        #expect(reconstructed.role == original.role)
        #expect(reconstructed.content == original.content)
        #expect(reconstructed.toolCalls.isEmpty)
        #expect(reconstructed.images.isEmpty)
        #expect(reconstructed.responseFormat == nil)
    }
    
    @Test("Message - All roles serialize correctly")
    func testMessageAllRoles() throws {
        let roles: [MessageRole] = [.system, .user, .assistant, .tool]
        
        for role in roles {
            let message = Message(
                id: UUID(),
                role: role,
                content: "Test content"
            )
            
            let json = message.toEasyJSON()
            guard let reconstructed = Message.fromEasyJSON(json) else {
                #expect(Bool(false), "Should reconstruct message with role \(role.rawValue)")
                continue
            }
            
            #expect(reconstructed.role == role)
        }
    }
    
    // MARK: - Compatibility Tests
    
    @Test("Legacy toJSON and new toEasyJSON produce equivalent data")
    func testLegacyAndNewJSONEquivalent() throws {
        let message = Message(
            id: UUID(),
            role: .user,
            content: "Test message",
            images: [],
            toolCalls: ["tool1", "tool2"],
            responseFormat: "json"
        )
        
        let legacyJSON = message.toJSON()
        let newJSON = message.toEasyJSON()
        
        // Verify key fields match
        #expect(legacyJSON["id"] as? String == message.id.uuidString)
        #expect(legacyJSON["role"] as? String == message.role.rawValue)
        #expect(legacyJSON["content"] as? String == message.content)
        
        guard case .object(let dict) = newJSON else {
            #expect(Bool(false), "New JSON should be an object")
            return
        }
        
        expectJSONString(dict["id"], equals: message.id.uuidString)
        expectJSONString(dict["role"], equals: message.role.rawValue)
        expectJSONString(dict["content"], equals: message.content)
    }
}

