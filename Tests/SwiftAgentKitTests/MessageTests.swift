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
        let toolCall1 = ToolCall(name: "tool1", arguments: .object(["arg1": .string("value1")]), id: "tc1")
        let toolCall2 = ToolCall(name: "tool2", arguments: .object(["arg2": .string("value2")]), id: "tc2")
        let message = Message(
            id: id,
            role: .user,
            content: "Hello, world!",
            timestamp: timestamp,
            images: [image],
            toolCalls: [toolCall1, toolCall2],
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
        
        // Verify first tool call
        guard case .object(let tc1Dict) = toolCallsArray[0] else {
            #expect(Bool(false), "First tool call should be an object")
            return
        }
        expectJSONString(tc1Dict["name"], equals: "tool1")
        expectJSONString(tc1Dict["id"], equals: "tc1")
        
        // Verify second tool call
        guard case .object(let tc2Dict) = toolCallsArray[1] else {
            #expect(Bool(false), "Second tool call should be an object")
            return
        }
        expectJSONString(tc2Dict["name"], equals: "tool2")
        expectJSONString(tc2Dict["id"], equals: "tc2")
        
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
            "toolCalls": .array([
                .object([
                    "name": .string("tool1"),
                    "arguments": .object(["arg1": .string("value1")]),
                    "instructions": .string(""),
                    "id": .string("tc1")
                ]),
                .object([
                    "name": .string("tool2"),
                    "arguments": .object(["arg2": .string("value2")]),
                    "instructions": .string(""),
                    "id": .string("tc2")
                ])
            ]),
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
        #expect(message.toolCalls[0].name == "tool1")
        #expect(message.toolCalls[0].id == "tc1")
        #expect(message.toolCalls[1].name == "tool2")
        #expect(message.toolCalls[1].id == "tc2")
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
        
        let toolCall1 = ToolCall(name: "tool1", arguments: .object(["arg1": .string("value1")]), id: "tc1")
        let toolCall2 = ToolCall(name: "tool2", arguments: .object(["arg2": .string("value2")]), id: "tc2")
        
        let original = Message(
            id: id,
            role: .user,
            content: "Hello, world!",
            timestamp: Date(),
            images: [image],
            toolCalls: [toolCall1, toolCall2],
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
        #expect(reconstructed.toolCalls.count == original.toolCalls.count)
        #expect(reconstructed.toolCalls[0].name == original.toolCalls[0].name)
        #expect(reconstructed.toolCalls[0].id == original.toolCalls[0].id)
        #expect(reconstructed.toolCalls[1].name == original.toolCalls[1].name)
        #expect(reconstructed.toolCalls[1].id == original.toolCalls[1].id)
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
        let toolCall1 = ToolCall(name: "tool1", arguments: .object(["arg1": .string("value1")]), id: "tc1")
        let toolCall2 = ToolCall(name: "tool2", arguments: .object(["arg2": .string("value2")]), id: "tc2")
        
        let message = Message(
            id: UUID(),
            role: .user,
            content: "Test message",
            images: [],
            toolCalls: [toolCall1, toolCall2],
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
    
    // MARK: - Legacy JSON Tests (toJSON/fromJSON)
    
    @Test("Message toJSON - Complete message with tool calls")
    func testMessageToJSONComplete() throws {
        let id = UUID()
        let timestamp = Date()
        let formatter = ISO8601DateFormatter()
        
        let toolCall1 = ToolCall(name: "search", arguments: .object(["query": .string("test")]), instructions: "Search for test", id: "tc1")
        let toolCall2 = ToolCall(name: "calculate", arguments: .object(["operation": .string("sum"), "values": .array([.integer(1), .integer(2)])]), id: "tc2")
        
        let image = Message.Image(name: "test-image", path: "/path/to/image.jpg")
        
        let message = Message(
            id: id,
            role: .assistant,
            content: "Here are the results",
            timestamp: timestamp,
            images: [image],
            toolCalls: [toolCall1, toolCall2],
            toolCallId: "parent-tool-call-id",
            responseFormat: "json"
        )
        
        let json = message.toJSON()
        
        // Verify basic fields
        #expect(json["id"] as? String == id.uuidString)
        #expect(json["role"] as? String == "assistant")
        #expect(json["content"] as? String == "Here are the results")
        #expect(json["timestamp"] as? String == formatter.string(from: timestamp))
        #expect(json["toolCallId"] as? String == "parent-tool-call-id")
        #expect(json["responseFormat"] as? String == "json")
        
        // Verify tool calls
        guard let toolCallsArray = json["toolCalls"] as? [[String: Any]] else {
            #expect(Bool(false), "toolCalls should be an array of dictionaries")
            return
        }
        #expect(toolCallsArray.count == 2)
        
        // Verify first tool call
        let tc1 = toolCallsArray[0]
        #expect(tc1["name"] as? String == "search")
        #expect(tc1["instructions"] as? String == "Search for test")
        #expect(tc1["id"] as? String == "tc1")
        
        // Verify second tool call
        let tc2 = toolCallsArray[1]
        #expect(tc2["name"] as? String == "calculate")
        #expect(tc2["id"] as? String == "tc2")
        
        // Verify images
        guard let imagesArray = json["images"] as? [[String: Any]] else {
            #expect(Bool(false), "images should be an array of dictionaries")
            return
        }
        #expect(imagesArray.count == 1)
        #expect(imagesArray[0]["name"] as? String == "test-image")
    }
    
    @Test("Message fromJSON - Complete message with tool calls")
    func testMessageFromJSONComplete() throws {
        let id = UUID()
        let timestamp = Date()
        let formatter = ISO8601DateFormatter()
        
        let json: [String: Any] = [
            "id": id.uuidString,
            "role": "user",
            "content": "Execute these tools",
            "timestamp": formatter.string(from: timestamp),
            "toolCalls": [
                [
                    "name": "search",
                    "arguments": ["query": "test"],
                    "instructions": "Search for test",
                    "id": "tc1"
                ],
                [
                    "name": "calculate",
                    "arguments": ["operation": "sum", "values": [1, 2]],
                    "instructions": "Calculate sum",
                    "id": "tc2"
                ]
            ],
            "toolCallId": "parent-id",
            "images": [
                [
                    "name": "test-image",
                    "path": "/path/to/image.jpg"
                ]
            ],
            "responseFormat": "json"
        ]
        
        guard let message = Message.fromJSON(json) else {
            #expect(Bool(false), "Should successfully parse message from JSON")
            return
        }
        
        #expect(message.id == id)
        #expect(message.role == .user)
        #expect(message.content == "Execute these tools")
        #expect(message.toolCallId == "parent-id")
        #expect(message.responseFormat == "json")
        
        // Verify tool calls
        #expect(message.toolCalls.count == 2)
        #expect(message.toolCalls[0].name == "search")
        #expect(message.toolCalls[0].id == "tc1")
        #expect(message.toolCalls[0].instructions == "Search for test")
        #expect(message.toolCalls[1].name == "calculate")
        #expect(message.toolCalls[1].id == "tc2")
        
        // Verify images
        #expect(message.images.count == 1)
        #expect(message.images[0].name == "test-image")
        #expect(message.images[0].path == "/path/to/image.jpg")
        
        // Verify timestamp is close
        let timeDiff = abs(message.timestamp.timeIntervalSince(timestamp))
        #expect(timeDiff < 1.0)
    }
    
    @Test("Message fromJSON - Minimal message")
    func testMessageFromJSONMinimal() throws {
        let id = UUID()
        let timestamp = Date()
        let formatter = ISO8601DateFormatter()
        
        let json: [String: Any] = [
            "id": id.uuidString,
            "role": "system",
            "content": "System message",
            "timestamp": formatter.string(from: timestamp)
        ]
        
        guard let message = Message.fromJSON(json) else {
            #expect(Bool(false), "Should successfully parse minimal message")
            return
        }
        
        #expect(message.id == id)
        #expect(message.role == .system)
        #expect(message.content == "System message")
        #expect(message.toolCalls.isEmpty)
        #expect(message.images.isEmpty)
        #expect(message.toolCallId == nil)
        #expect(message.responseFormat == nil)
    }
    
    @Test("Message fromJSON - Invalid JSON returns nil")
    func testMessageFromJSONInvalid() throws {
        // Missing required fields
        let invalidJSON1: [String: Any] = [
            "id": UUID().uuidString,
            "role": "user"
            // Missing content and timestamp
        ]
        #expect(Message.fromJSON(invalidJSON1) == nil)
        
        // Invalid UUID
        let invalidJSON2: [String: Any] = [
            "id": "not-a-uuid",
            "role": "user",
            "content": "Test",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        #expect(Message.fromJSON(invalidJSON2) == nil)
        
        // Invalid role
        let invalidJSON3: [String: Any] = [
            "id": UUID().uuidString,
            "role": "invalid_role",
            "content": "Test",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        #expect(Message.fromJSON(invalidJSON3) == nil)
        
        // Invalid timestamp
        let invalidJSON4: [String: Any] = [
            "id": UUID().uuidString,
            "role": "user",
            "content": "Test",
            "timestamp": "not-a-timestamp"
        ]
        #expect(Message.fromJSON(invalidJSON4) == nil)
    }
    
    @Test("Message round-trip - Legacy JSON")
    func testMessageRoundTripLegacyJSON() throws {
        let toolCall1 = ToolCall(name: "search", arguments: .object(["query": .string("test")]), instructions: "Search", id: "tc1")
        let toolCall2 = ToolCall(name: "calculate", arguments: .object(["op": .string("sum")]), id: "tc2")
        let image = Message.Image(name: "test-image", path: "/path/to/image.jpg")
        
        let original = Message(
            id: UUID(),
            role: .assistant,
            content: "Test message",
            timestamp: Date(),
            images: [image],
            toolCalls: [toolCall1, toolCall2],
            toolCallId: "parent-id",
            responseFormat: "json"
        )
        
        let json = original.toJSON()
        guard let reconstructed = Message.fromJSON(json) else {
            #expect(Bool(false), "Should successfully reconstruct message")
            return
        }
        
        #expect(reconstructed.id == original.id)
        #expect(reconstructed.role == original.role)
        #expect(reconstructed.content == original.content)
        #expect(reconstructed.toolCallId == original.toolCallId)
        #expect(reconstructed.responseFormat == original.responseFormat)
        
        // Verify tool calls
        #expect(reconstructed.toolCalls.count == original.toolCalls.count)
        #expect(reconstructed.toolCalls[0].name == original.toolCalls[0].name)
        #expect(reconstructed.toolCalls[0].id == original.toolCalls[0].id)
        #expect(reconstructed.toolCalls[1].name == original.toolCalls[1].name)
        
        // Verify images
        #expect(reconstructed.images.count == original.images.count)
        #expect(reconstructed.images[0].name == original.images[0].name)
        
        // Verify timestamp
        let timeDiff = abs(reconstructed.timestamp.timeIntervalSince(original.timestamp))
        #expect(timeDiff < 1.0)
    }
    
    // MARK: - ToolCall Serialization Tests
    
    @Test("Message - Tool calls with complex arguments")
    func testMessageWithComplexToolCallArguments() throws {
        let complexArgs = JSON.object([
            "string_arg": .string("test"),
            "int_arg": .integer(42),
            "double_arg": .double(3.14),
            "bool_arg": .boolean(true),
            "array_arg": .array([.string("a"), .string("b")]),
            "nested_object": .object([
                "key1": .string("value1"),
                "key2": .integer(100)
            ])
        ])
        
        let toolCall = ToolCall(name: "complex_tool", arguments: complexArgs, instructions: "Complex operation", id: "tc1")
        let message = Message(
            id: UUID(),
            role: .assistant,
            content: "Executing complex tool",
            toolCalls: [toolCall]
        )
        
        // Test EasyJSON serialization
        let easyJSON = message.toEasyJSON()
        guard let reconstructedFromEasyJSON = Message.fromEasyJSON(easyJSON) else {
            #expect(Bool(false), "Should reconstruct from EasyJSON")
            return
        }
        
        #expect(reconstructedFromEasyJSON.toolCalls.count == 1)
        let reconstructedToolCall = reconstructedFromEasyJSON.toolCalls[0]
        #expect(reconstructedToolCall.name == "complex_tool")
        #expect(reconstructedToolCall.id == "tc1")
        #expect(reconstructedToolCall.instructions == "Complex operation")
        
        // Verify complex arguments are preserved
        guard case .object(let argsDict) = reconstructedToolCall.arguments else {
            #expect(Bool(false), "Arguments should be an object")
            return
        }
        
        guard case .string(let stringVal) = argsDict["string_arg"] else {
            #expect(Bool(false), "string_arg should be a string")
            return
        }
        #expect(stringVal == "test")
        
        guard case .integer(let intVal) = argsDict["int_arg"] else {
            #expect(Bool(false), "int_arg should be an integer")
            return
        }
        #expect(intVal == 42)
        
        guard case .double(let doubleVal) = argsDict["double_arg"] else {
            #expect(Bool(false), "double_arg should be a double")
            return
        }
        #expect(abs(doubleVal - 3.14) < 0.001)
        
        guard case .boolean(let boolVal) = argsDict["bool_arg"] else {
            #expect(Bool(false), "bool_arg should be a boolean")
            return
        }
        #expect(boolVal == true)
        
        // Test legacy JSON serialization
        let legacyJSON = message.toJSON()
        guard let reconstructedFromLegacy = Message.fromJSON(legacyJSON) else {
            #expect(Bool(false), "Should reconstruct from legacy JSON")
            return
        }
        
        #expect(reconstructedFromLegacy.toolCalls.count == 1)
        #expect(reconstructedFromLegacy.toolCalls[0].name == "complex_tool")
    }
    
    @Test("Message - Tool calls with empty arguments")
    func testMessageWithEmptyToolCallArguments() throws {
        let toolCall = ToolCall(name: "simple_tool", arguments: .object([:]), id: "tc1")
        let message = Message(
            id: UUID(),
            role: .assistant,
            content: "Simple tool",
            toolCalls: [toolCall]
        )
        
        // Test EasyJSON round-trip
        let easyJSON = message.toEasyJSON()
        guard let reconstructed = Message.fromEasyJSON(easyJSON) else {
            #expect(Bool(false), "Should reconstruct from EasyJSON")
            return
        }
        
        #expect(reconstructed.toolCalls.count == 1)
        #expect(reconstructed.toolCalls[0].name == "simple_tool")
        guard case .object(let args) = reconstructed.toolCalls[0].arguments else {
            #expect(Bool(false), "Arguments should be an object")
            return
        }
        #expect(args.isEmpty)
    }
    
    @Test("Message - Multiple tool calls in sequence")
    func testMessageWithMultipleToolCalls() throws {
        let toolCalls = (1...5).map { i in
            ToolCall(name: "tool\(i)", arguments: .object(["index": .integer(i)]), id: "tc\(i)")
        }
        
        let message = Message(
            id: UUID(),
            role: .assistant,
            content: "Multiple tools",
            toolCalls: toolCalls
        )
        
        // Test EasyJSON round-trip
        let easyJSON = message.toEasyJSON()
        guard let reconstructed = Message.fromEasyJSON(easyJSON) else {
            #expect(Bool(false), "Should reconstruct from EasyJSON")
            return
        }
        
        #expect(reconstructed.toolCalls.count == 5)
        for i in 0..<5 {
            #expect(reconstructed.toolCalls[i].name == "tool\(i+1)")
            #expect(reconstructed.toolCalls[i].id == "tc\(i+1)")
        }
        
        // Test legacy JSON round-trip
        let legacyJSON = message.toJSON()
        guard let reconstructedLegacy = Message.fromJSON(legacyJSON) else {
            #expect(Bool(false), "Should reconstruct from legacy JSON")
            return
        }
        
        #expect(reconstructedLegacy.toolCalls.count == 5)
        for i in 0..<5 {
            #expect(reconstructedLegacy.toolCalls[i].name == "tool\(i+1)")
        }
    }
    
    // MARK: - Image Serialization Tests
    
    @Test("Message - Images with base64 data serialization")
    func testMessageImagesWithBase64DataSerialization() throws {
        let imageData = "test-image-data".data(using: .utf8)!
        let thumbData = "test-thumb-data".data(using: .utf8)!
        
        let image = Message.Image(
            name: "test-image",
            path: "/path/to/image.jpg",
            imageData: imageData,
            thumbData: thumbData
        )
        
        let message = Message(
            id: UUID(),
            role: .user,
            content: "Here's an image",
            images: [image]
        )
        
        // Test with image data included
        let jsonWithData = message.toEasyJSON(includeImageData: true, includeThumbData: true)
        guard let reconstructedWithData = Message.fromEasyJSON(jsonWithData) else {
            #expect(Bool(false), "Should reconstruct with image data")
            return
        }
        
        #expect(reconstructedWithData.images.count == 1)
        #expect(reconstructedWithData.images[0].name == "test-image")
        #expect(reconstructedWithData.images[0].imageData == imageData)
        #expect(reconstructedWithData.images[0].thumbData == thumbData)
        
        // Test without image data
        let jsonWithoutData = message.toEasyJSON(includeImageData: false, includeThumbData: false)
        guard let reconstructedWithoutData = Message.fromEasyJSON(jsonWithoutData) else {
            #expect(Bool(false), "Should reconstruct without image data")
            return
        }
        
        #expect(reconstructedWithoutData.images.count == 1)
        #expect(reconstructedWithoutData.images[0].name == "test-image")
        #expect(reconstructedWithoutData.images[0].path == "/path/to/image.jpg")
        #expect(reconstructedWithoutData.images[0].imageData == nil)
        #expect(reconstructedWithoutData.images[0].thumbData == nil)
    }
    
    @Test("Message - Multiple images")
    func testMessageWithMultipleImages() throws {
        let images = (1...3).map { i in
            Message.Image(
                name: "image\(i)",
                path: "/path/to/image\(i).jpg",
                imageData: "data\(i)".data(using: .utf8)
            )
        }
        
        let message = Message(
            id: UUID(),
            role: .user,
            content: "Multiple images",
            images: images
        )
        
        let json = message.toEasyJSON(includeImageData: true)
        guard let reconstructed = Message.fromEasyJSON(json) else {
            #expect(Bool(false), "Should reconstruct message with multiple images")
            return
        }
        
        #expect(reconstructed.images.count == 3)
        for i in 0..<3 {
            #expect(reconstructed.images[i].name == "image\(i+1)")
            #expect(reconstructed.images[i].path == "/path/to/image\(i+1).jpg")
        }
    }
    
    // MARK: - Edge Cases and Error Handling
    
    @Test("Message - Empty content is allowed")
    func testMessageWithEmptyContent() throws {
        let message = Message(
            id: UUID(),
            role: .assistant,
            content: ""
        )
        
        let easyJSON = message.toEasyJSON()
        guard let reconstructed = Message.fromEasyJSON(easyJSON) else {
            #expect(Bool(false), "Should reconstruct message with empty content")
            return
        }
        
        #expect(reconstructed.content == "")
    }
    
    @Test("Message - Tool role with toolCallId")
    func testMessageWithToolRole() throws {
        let message = Message(
            id: UUID(),
            role: .tool,
            content: "Tool execution result",
            toolCallId: "parent-tool-call-id"
        )
        
        // EasyJSON round-trip
        let easyJSON = message.toEasyJSON()
        guard let reconstructed = Message.fromEasyJSON(easyJSON) else {
            #expect(Bool(false), "Should reconstruct tool message")
            return
        }
        
        #expect(reconstructed.role == .tool)
        #expect(reconstructed.toolCallId == "parent-tool-call-id")
        
        // Legacy JSON round-trip
        let legacyJSON = message.toJSON()
        guard let reconstructedLegacy = Message.fromJSON(legacyJSON) else {
            #expect(Bool(false), "Should reconstruct tool message from legacy JSON")
            return
        }
        
        #expect(reconstructedLegacy.role == .tool)
        #expect(reconstructedLegacy.toolCallId == "parent-tool-call-id")
    }
    
    @Test("Message - isUser property")
    func testMessageIsUserProperty() throws {
        let userMessage = Message(id: UUID(), role: .user, content: "User message")
        #expect(userMessage.isUser == true)
        
        let assistantMessage = Message(id: UUID(), role: .assistant, content: "Assistant message")
        #expect(assistantMessage.isUser == false)
        
        let systemMessage = Message(id: UUID(), role: .system, content: "System message")
        #expect(systemMessage.isUser == false)
        
        let toolMessage = Message(id: UUID(), role: .tool, content: "Tool message")
        #expect(toolMessage.isUser == false)
    }
    
    @Test("Message - Codable conformance")
    func testMessageCodableConformance() throws {
        let toolCall = ToolCall(name: "test_tool", arguments: .object(["key": .string("value")]), id: "tc1")
        let image = Message.Image(name: "test", path: "/test.jpg")
        
        let original = Message(
            id: UUID(),
            role: .assistant,
            content: "Test",
            timestamp: Date(),
            images: [image],
            toolCalls: [toolCall],
            toolCallId: "parent-id",
            responseFormat: "json"
        )
        
        // Encode
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(original) else {
            #expect(Bool(false), "Should encode message")
            return
        }
        
        // Decode
        let decoder = JSONDecoder()
        guard let decoded = try? decoder.decode(Message.self, from: data) else {
            #expect(Bool(false), "Should decode message")
            return
        }
        
        #expect(decoded.id == original.id)
        #expect(decoded.role == original.role)
        #expect(decoded.content == original.content)
        #expect(decoded.toolCallId == original.toolCallId)
        #expect(decoded.responseFormat == original.responseFormat)
        #expect(decoded.toolCalls.count == original.toolCalls.count)
        #expect(decoded.images.count == original.images.count)
    }
}

