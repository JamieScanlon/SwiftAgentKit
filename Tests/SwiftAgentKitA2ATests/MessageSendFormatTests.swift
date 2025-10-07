//
//  MessageSendFormatTests.swift
//  SwiftAgentKit
//
//  Tests to verify A2A message/send format compliance with A2A Protocol v0.2.5
//  Specification: https://a2a-protocol.org/v0.2.5/specification/#7-protocol-rpc-methods
//

import Testing
import Foundation
import EasyJSON
@testable import SwiftAgentKitA2A

@Suite("A2A message/send Format Compliance Tests")
struct MessageSendFormatTests {
    
    // MARK: - JSON-RPC 2.0 Request Format Tests
    
    @Test("JSON-RPC request has correct structure")
    func testJSONRPCRequestStructure() throws {
        // Given - Create a message/send request as per spec
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Hello, agent!")],
            messageId: UUID().uuidString
        )
        let params = MessageSendParams(message: message)
        let rpcRequest = JSONRPCRequest(jsonrpc: "2.0", id: 1, params: params)
        
        // When - Encode to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(rpcRequest)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then - Verify JSON-RPC 2.0 structure
        #expect(json != nil)
        #expect(json?["jsonrpc"] as? String == "2.0", "Must have jsonrpc: '2.0'")
        #expect(json?["id"] != nil, "Must have an id field")
        #expect(json?["params"] != nil, "Must have a params field")
    }
    
    @Test("MessageSendParams has required message field")
    func testMessageSendParamsStructure() throws {
        // Given
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Test message")],
            messageId: UUID().uuidString
        )
        let params = MessageSendParams(message: message)
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(params)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then
        #expect(json != nil)
        #expect(json?["message"] != nil, "MessageSendParams must have a 'message' field")
    }
    
    // MARK: - Message Object Format Tests
    
    @Test("Message has all required fields")
    func testMessageRequiredFields() throws {
        // Given
        let messageId = UUID().uuidString
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Test")],
            messageId: messageId
        )
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then - Verify all required fields per spec
        #expect(json != nil)
        #expect(json?["role"] as? String == "user", "Message must have 'role' field")
        #expect(json?["parts"] != nil, "Message must have 'parts' field")
        #expect(json?["messageId"] as? String == messageId, "Message must have 'messageId' field")
    }
    
    @Test("Message role accepts standard values")
    func testMessageRoleValues() throws {
        let roles = ["user", "assistant", "system"]
        
        for role in roles {
            let message = A2AMessage(
                role: role,
                parts: [.text(text: "Test")],
                messageId: UUID().uuidString
            )
            
            let encoder = JSONEncoder()
            let data = try encoder.encode(message)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            #expect(json?["role"] as? String == role, "Role '\(role)' should be preserved")
        }
    }
    
    // MARK: - Part Types Format Tests (per spec section 6.5)
    
    @Test("TextPart format matches spec")
    func testTextPartFormat() throws {
        // Given - Create a TextPart as per spec
        let textPart = A2AMessagePart.text(text: "Your message content here")
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(textPart)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then - Verify format matches spec: { "kind": "text", "text": "..." }
        #expect(json != nil)
        #expect(json?["kind"] as? String == "text", "TextPart must have kind='text'")
        #expect(json?["text"] as? String == "Your message content here", "TextPart must have 'text' field")
    }
    
    @Test("FilePart with bytes format matches spec")
    func testFilePartWithBytesFormat() throws {
        // Given - Create a FilePart with bytes as per spec
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header
        let filePart = A2AMessagePart.file(data: imageData, url: nil)
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(filePart)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then - Verify format: { "kind": "file", "file": "base64..." }
        #expect(json != nil)
        #expect(json?["kind"] as? String == "file", "FilePart must have kind='file'")
        #expect(json?["file"] != nil, "FilePart must have 'file' field")
        
        // Verify it's base64 encoded
        let fileValue = json?["file"] as? String
        #expect(fileValue != nil)
        let decodedData = Data(base64Encoded: fileValue!)
        #expect(decodedData != nil, "File data should be base64 encoded")
    }
    
    @Test("FilePart with URI format matches spec")
    func testFilePartWithURIFormat() throws {
        // Given - Create a FilePart with URI as per spec
        let fileURL = URL(string: "https://example.com/file.png")!
        let filePart = A2AMessagePart.file(data: nil, url: fileURL)
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(filePart)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then - Verify format: { "kind": "file", "file": "uri" }
        #expect(json != nil)
        #expect(json?["kind"] as? String == "file", "FilePart must have kind='file'")
        #expect(json?["file"] as? String == "https://example.com/file.png", "FilePart must have 'file' URI")
    }
    
    @Test("DataPart format matches spec")
    func testDataPartFormat() throws {
        // Given - Create a DataPart as per spec
        let structuredData = Data([0x01, 0x02, 0x03, 0x04])
        let dataPart = A2AMessagePart.data(data: structuredData)
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(dataPart)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then - Verify format: { "kind": "data", "data": {...} }
        #expect(json != nil)
        #expect(json?["kind"] as? String == "data", "DataPart must have kind='data'")
        #expect(json?["data"] != nil, "DataPart must have 'data' field")
    }
    
    // MARK: - Complete message/send Request Format Tests
    
    @Test("Complete message/send request matches spec example")
    func testCompleteMessageSendRequest() throws {
        // Given - Create a complete request as shown in spec
        let messageId = "6dbc13b5-bd57-4c2b-b503-24e381b6c8d6"
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Analyze this image and highlight any faces.")],
            messageId: messageId
        )
        let params = MessageSendParams(message: message)
        let rpcRequest = JSONRPCRequest(jsonrpc: "2.0", id: 7, params: params)
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(rpcRequest)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then - Verify complete structure
        #expect(json != nil)
        #expect(json?["jsonrpc"] as? String == "2.0")
        #expect(json?["id"] as? Int == 7)
        
        // Verify params structure
        guard let rpcParams = json?["params"] as? [String: Any] else {
            #expect(Bool(false), "Params should exist")
            return
        }
        
        guard let messageJson = rpcParams["message"] as? [String: Any] else {
            #expect(Bool(false), "Message should exist")
            return
        }
        
        #expect(messageJson["role"] as? String == "user")
        #expect(messageJson["messageId"] as? String == messageId)
        
        if let parts = messageJson["parts"] as? [[String: Any]] {
            #expect(parts.count == 1)
            if let firstPart = parts.first {
                #expect(firstPart["kind"] as? String == "text")
            }
        } else {
            #expect(Bool(false), "Parts should be an array")
        }
    }
    
    @Test("Message with multiple parts format")
    func testMessageWithMultipleParts() throws {
        // Given - Create a message with multiple parts (text + file)
        let message = A2AMessage(
            role: "user",
            parts: [
                .text(text: "Analyze this image"),
                .file(data: nil, url: URL(string: "https://example.com/image.png")!)
            ],
            messageId: UUID().uuidString
        )
        let params = MessageSendParams(message: message)
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(params)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then
        let messageJson = json?["message"] as? [String: Any]
        let parts = messageJson?["parts"] as? [[String: Any]]
        
        #expect(parts != nil)
        #expect(parts?.count == 2, "Should have 2 parts")
        #expect(parts?.first?["kind"] as? String == "text")
        #expect(parts?.last?["kind"] as? String == "file")
    }
    
    @Test("MessageSendParams with optional configuration")
    func testMessageSendParamsWithConfiguration() throws {
        // Given
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Test")],
            messageId: UUID().uuidString
        )
        let configuration = MessageSendConfiguration(
            acceptedOutputModes: ["text/plain", "application/json"],
            historyLength: 10,
            blocking: true
        )
        let params = MessageSendParams(message: message, configuration: configuration)
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(params)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then
        #expect(json != nil)
        #expect(json?["message"] != nil)
        #expect(json?["configuration"] != nil, "Configuration should be encoded")
        
        let configJson = json?["configuration"] as? [String: Any]
        #expect(configJson?["acceptedOutputModes"] != nil)
        #expect(configJson?["historyLength"] as? Int == 10)
        #expect(configJson?["blocking"] as? Bool == true)
    }
    
    @Test("MessageSendParams with metadata")
    func testMessageSendParamsWithMetadata() throws {
        // Given
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Test")],
            messageId: UUID().uuidString
        )
        let metadata = try EasyJSON.JSON(["customKey": "customValue", "priority": 1])
        let params = MessageSendParams(message: message, metadata: metadata)
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(params)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then
        #expect(json?["metadata"] != nil, "Metadata should be encoded")
    }
    
    // MARK: - Round-trip Tests (Encoding and Decoding)
    
    @Test("MessageSendParams round-trip encoding/decoding")
    func testMessageSendParamsRoundTrip() throws {
        // Given
        let originalMessage = A2AMessage(
            role: "user",
            parts: [
                .text(text: "Hello"),
                .file(data: nil, url: URL(string: "https://example.com/file.txt")!)
            ],
            messageId: UUID().uuidString
        )
        let originalParams = MessageSendParams(message: originalMessage)
        
        // When - Encode then decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(originalParams)
        let decodedParams = try decoder.decode(MessageSendParams.self, from: data)
        
        // Then
        #expect(decodedParams.message.role == originalMessage.role)
        #expect(decodedParams.message.messageId == originalMessage.messageId)
        #expect(decodedParams.message.parts.count == originalMessage.parts.count)
    }
    
    @Test("JSON-RPC request round-trip")
    func testJSONRPCRequestRoundTrip() throws {
        // Given
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Test message")],
            messageId: UUID().uuidString
        )
        let params = MessageSendParams(message: message)
        let originalRequest = JSONRPCRequest(jsonrpc: "2.0", id: 42, params: params)
        
        // When
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(originalRequest)
        let decodedRequest = try decoder.decode(JSONRPCRequest<MessageSendParams>.self, from: data)
        
        // Then
        #expect(decodedRequest.jsonrpc == "2.0")
        #expect(decodedRequest.id == 42)
        #expect(decodedRequest.params.message.role == "user")
    }
    
    // MARK: - Response Format Tests
    
    @Test("Task response has correct structure per spec")
    func testTaskResponseStructure() throws {
        // Given - Create a task response as returned by message/send
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(
                state: .completed,
                timestamp: ISO8601DateFormatter().string(from: Date())
            ),
            artifacts: [
                Artifact(
                    artifactId: UUID().uuidString,
                    parts: [.text(text: "Response text")]
                )
            ]
        )
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(task)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then - Verify task structure per spec section 6.1
        #expect(json != nil)
        #expect(json?["id"] != nil, "Task must have 'id' field")
        #expect(json?["contextId"] != nil, "Task must have 'contextId' field")
        #expect(json?["status"] != nil, "Task must have 'status' field")
        #expect(json?["kind"] as? String == "task", "Task must have kind='task'")
        
        // Verify TaskStatus structure
        let status = json?["status"] as? [String: Any]
        #expect(status != nil)
        #expect(status?["state"] != nil, "TaskStatus must have 'state' field")
        #expect(status?["timestamp"] != nil, "TaskStatus should have 'timestamp' field")
    }
    
    @Test("TaskStatus states match spec enum")
    func testTaskStateEnumValues() throws {
        // Test all TaskState values defined in spec section 6.3
        let states: [(TaskState, String)] = [
            (.submitted, "submitted"),
            (.working, "working"),
            (.inputRequired, "input-required"),
            (.completed, "completed"),
            (.canceled, "canceled"),
            (.failed, "failed"),
            (.rejected, "rejected"),
            (.authRequired, "auth-required"),
            (.unknown, "unknown")
        ]
        
        for (state, expectedString) in states {
            let taskStatus = TaskStatus(state: state, timestamp: ISO8601DateFormatter().string(from: Date()))
            let encoder = JSONEncoder()
            let data = try encoder.encode(taskStatus)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            #expect(json?["state"] as? String == expectedString, "State '\(state)' should encode as '\(expectedString)'")
        }
    }
    
    @Test("Artifact format matches spec")
    func testArtifactFormat() throws {
        // Given - Create an artifact as per spec section 6.7
        let artifact = Artifact(
            artifactId: UUID().uuidString,
            parts: [
                .text(text: "Artifact content")
            ],
            name: "result.txt",
            description: "Result artifact"
        )
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(artifact)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then
        #expect(json != nil)
        #expect(json?["artifactId"] != nil, "Artifact must have 'artifactId' field")
        #expect(json?["parts"] != nil, "Artifact must have 'parts' field")
        #expect(json?["name"] as? String == "result.txt")
        #expect(json?["description"] as? String == "Result artifact")
    }
    
    // MARK: - Edge Cases and Validation
    
    @Test("Empty parts array is allowed")
    func testEmptyPartsArray() throws {
        // Given - Message with empty parts (edge case)
        let message = A2AMessage(
            role: "user",
            parts: [],
            messageId: UUID().uuidString
        )
        
        // When/Then - Should encode without error
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        let parts = json?["parts"] as? [[String: Any]]
        #expect(parts != nil)
        #expect(parts?.count == 0, "Empty parts array should be preserved")
    }
    
    @Test("MessageId is preserved exactly")
    func testMessageIdPreservation() throws {
        // Given - UUID format message ID as commonly used
        let uuid = UUID().uuidString
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Test")],
            messageId: uuid
        )
        
        // When
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(A2AMessage.self, from: data)
        
        // Then
        #expect(decoded.messageId == uuid, "MessageId must be preserved exactly")
    }
    
    @Test("Optional message fields are encoded when present")
    func testOptionalMessageFields() throws {
        // Given - Message with optional fields
        let metadata = try EasyJSON.JSON(["key": "value"])
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Test")],
            messageId: UUID().uuidString,
            metadata: metadata,
            extensions: ["https://example.com/extension"],
            referenceTaskIds: ["task-123"],
            taskId: "task-456",
            contextId: "context-789"
        )
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then - Optional fields should be present
        #expect(json?["metadata"] != nil)
        #expect(json?["extensions"] != nil)
        #expect(json?["referenceTaskIds"] != nil)
        
        let taskId = json?["taskId"] as? String
        #expect(taskId == "task-456")
        
        let contextId = json?["contextId"] as? String
        #expect(contextId == "context-789")
    }
}

