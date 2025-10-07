//
//  A2AServerEndpointTests.swift
//  SwiftAgentKit
//
//  Tests to verify A2A server endpoints properly handle JSON-RPC 2.0 format
//  as specified in A2A Protocol v0.2.5
//

import Testing
import Foundation
@testable import SwiftAgentKitA2A

@Suite("A2A Server Endpoint JSON-RPC Compliance Tests")
struct A2AServerEndpointTests {
    
    // MARK: - Helper Functions
    
    /// Helper to create a JSON-RPC request
    func createJSONRPCRequest<T: Encodable>(id: Int, method: String, params: T) throws -> Data {
        let request = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method
        ] as [String : Any]
        
        var requestDict = request
        let paramsData = try JSONEncoder().encode(params)
        if let paramsObject = try JSONSerialization.jsonObject(with: paramsData) as? [String: Any] {
            requestDict["params"] = paramsObject
        }
        
        return try JSONSerialization.data(withJSONObject: requestDict)
    }
    
    // MARK: - message/send Tests
    
    @Test("message/send should accept JSON-RPC 2.0 envelope")
    func testMessageSendAcceptsJSONRPCEnvelope() async throws {
        // Given - A proper JSON-RPC request for message/send
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Hello, agent!")],
            messageId: UUID().uuidString
        )
        
        let requestBody = [
            "jsonrpc": "2.0",
            "id": 42,
            "method": "message/send",
            "params": [
                "message": [
                    "role": "user",
                    "parts": [
                        ["kind": "text", "text": "Hello, agent!"]
                    ],
                    "messageId": message.messageId,
                    "kind": "message"
                ]
            ]
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // When - Parsing the data
        let decoder = JSONDecoder()
        let rpcRequest = try decoder.decode(JSONRPCRequest<MessageSendParams>.self, from: jsonData)
        
        // Then - Verify structure
        #expect(rpcRequest.jsonrpc == "2.0")
        #expect(rpcRequest.id == 42)
        #expect(rpcRequest.params.message.role == "user")
        #expect(rpcRequest.params.message.messageId == message.messageId)
    }
    
    @Test("message/send should reject request without JSON-RPC envelope")
    func testMessageSendRejectsNonJSONRPCRequest() async throws {
        // Given - A request with just params (not wrapped in JSON-RPC)
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Hello")],
            messageId: UUID().uuidString
        )
        let params = MessageSendParams(message: message)
        
        let encoder = JSONEncoder()
        let paramsData = try encoder.encode(params)
        
        // When/Then - Should fail to decode as JSON-RPC request
        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(JSONRPCRequest<MessageSendParams>.self, from: paramsData)
        }
    }
    
    @Test("message/send response should be wrapped in JSON-RPC envelope")
    func testMessageSendResponseFormat() throws {
        // Given - A task response
        let task = A2ATask(
            id: UUID().uuidString,
            contextId: UUID().uuidString,
            status: TaskStatus(
                state: .completed,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        )
        
        // When - Encoding task first, then wrapping in JSON-RPC format
        let requestId = 42
        let encoder = JSONEncoder()
        let taskData = try encoder.encode(task)
        let taskJson = try JSONSerialization.jsonObject(with: taskData) as! [String: Any]
        
        let rpcResponse = [
            "jsonrpc": "2.0",
            "id": requestId,
            "result": taskJson
        ] as [String : Any]
        
        let data = try JSONSerialization.data(withJSONObject: rpcResponse)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then - Verify JSON-RPC structure
        #expect(json?["jsonrpc"] as? String == "2.0")
        #expect(json?["id"] as? Int == requestId)
        #expect(json?["result"] != nil)
        
        let result = json?["result"] as? [String: Any]
        #expect(result?["id"] != nil)
        #expect(result?["contextId"] != nil)
        #expect(result?["status"] != nil)
    }
    
    // MARK: - tasks/get Tests
    
    @Test("tasks/get should accept JSON-RPC 2.0 envelope")
    func testTasksGetAcceptsJSONRPCEnvelope() throws {
        // Given - A JSON-RPC request for tasks/get
        let requestBody = [
            "jsonrpc": "2.0",
            "id": 10,
            "method": "tasks/get",
            "params": [
                "id": "task-123",
                "historyLength": 5
            ]
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // When
        let decoder = JSONDecoder()
        let rpcRequest = try decoder.decode(JSONRPCRequest<TaskQueryParams>.self, from: jsonData)
        
        // Then
        #expect(rpcRequest.jsonrpc == "2.0")
        #expect(rpcRequest.id == 10)
        #expect(rpcRequest.params.taskId == "task-123")
        #expect(rpcRequest.params.historyLength == 5)
    }
    
    @Test("tasks/get should handle missing optional historyLength")
    func testTasksGetWithoutHistoryLength() throws {
        // Given
        let requestBody = [
            "jsonrpc": "2.0",
            "id": 11,
            "method": "tasks/get",
            "params": [
                "id": "task-456"
            ]
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // When
        let decoder = JSONDecoder()
        let rpcRequest = try decoder.decode(JSONRPCRequest<TaskQueryParams>.self, from: jsonData)
        
        // Then
        #expect(rpcRequest.params.taskId == "task-456")
        #expect(rpcRequest.params.historyLength == nil)
    }
    
    // MARK: - tasks/cancel Tests
    
    @Test("tasks/cancel should accept JSON-RPC 2.0 envelope")
    func testTasksCancelAcceptsJSONRPCEnvelope() throws {
        // Given
        let requestBody = [
            "jsonrpc": "2.0",
            "id": 20,
            "method": "tasks/cancel",
            "params": [
                "id": "task-789"
            ]
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // When
        let decoder = JSONDecoder()
        let rpcRequest = try decoder.decode(JSONRPCRequest<TaskIdParams>.self, from: jsonData)
        
        // Then
        #expect(rpcRequest.jsonrpc == "2.0")
        #expect(rpcRequest.id == 20)
        #expect(rpcRequest.params.taskId == "task-789")
    }
    
    // MARK: - tasks/pushNotificationConfig Tests
    
    @Test("tasks/pushNotificationConfig/set should accept JSON-RPC envelope")
    func testPushConfigSetAcceptsJSONRPCEnvelope() throws {
        // Given
        let requestBody = [
            "jsonrpc": "2.0",
            "id": 30,
            "method": "tasks/pushNotificationConfig/set",
            "params": [
                "taskId": "task-abc",
                "pushNotificationConfig": [
                    "url": "https://example.com/webhook",
                    "token": "secret-token"
                ]
            ]
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // When
        let decoder = JSONDecoder()
        let rpcRequest = try decoder.decode(JSONRPCRequest<TaskPushNotificationConfig>.self, from: jsonData)
        
        // Then
        #expect(rpcRequest.jsonrpc == "2.0")
        #expect(rpcRequest.id == 30)
        #expect(rpcRequest.params.taskId == "task-abc")
        #expect(rpcRequest.params.pushNotificationConfig.url == "https://example.com/webhook")
    }
    
    @Test("tasks/pushNotificationConfig/get should accept JSON-RPC envelope")
    func testPushConfigGetAcceptsJSONRPCEnvelope() throws {
        // Given
        let requestBody = [
            "jsonrpc": "2.0",
            "id": 31,
            "method": "tasks/pushNotificationConfig/get",
            "params": [
                "id": "task-def"
            ]
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // When
        let decoder = JSONDecoder()
        let rpcRequest = try decoder.decode(JSONRPCRequest<TaskIdParams>.self, from: jsonData)
        
        // Then
        #expect(rpcRequest.jsonrpc == "2.0")
        #expect(rpcRequest.id == 31)
        #expect(rpcRequest.params.taskId == "task-def")
    }
    
    // MARK: - tasks/resubscribe Tests
    
    @Test("tasks/resubscribe should accept JSON-RPC envelope")
    func testTasksResubscribeAcceptsJSONRPCEnvelope() throws {
        // Given
        let requestBody = [
            "jsonrpc": "2.0",
            "id": 40,
            "method": "tasks/resubscribe",
            "params": [
                "id": "task-ghi"
            ]
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // When
        let decoder = JSONDecoder()
        let rpcRequest = try decoder.decode(JSONRPCRequest<TaskIdParams>.self, from: jsonData)
        
        // Then
        #expect(rpcRequest.jsonrpc == "2.0")
        #expect(rpcRequest.id == 40)
        #expect(rpcRequest.params.taskId == "task-ghi")
    }
    
    // MARK: - Error Response Tests
    
    @Test("Error responses should include request ID")
    func testErrorResponseIncludesRequestID() throws {
        // Given
        let requestId = 99
        let errorCode = -32602
        let errorMessage = "Invalid params"
        
        // When - Creating error response structure
        let errorResponse = JSONRPCErrorResponse(
            jsonrpc: "2.0",
            id: requestId,
            error: JSONRPCError(code: errorCode, message: errorMessage)
        )
        
        // Then
        #expect(errorResponse.jsonrpc == "2.0")
        #expect(errorResponse.id == requestId)
        #expect(errorResponse.error.code == errorCode)
        #expect(errorResponse.error.message == errorMessage)
    }
    
    @Test("Error response should serialize correctly")
    func testErrorResponseSerialization() throws {
        // Given
        let errorResponse = JSONRPCErrorResponse(
            jsonrpc: "2.0",
            id: 100,
            error: JSONRPCError(code: -32600, message: "Invalid Request")
        )
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(errorResponse)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Then
        #expect(json?["jsonrpc"] as? String == "2.0")
        #expect(json?["id"] as? Int == 100)
        
        let error = json?["error"] as? [String: Any]
        #expect(error?["code"] as? Int == -32600)
        #expect(error?["message"] as? String == "Invalid Request")
    }
    
    // MARK: - Request ID Preservation Tests
    
    @Test("Request ID should be preserved from request to response")
    func testRequestIDPreservation() throws {
        // Test various ID types
        let testIDs = [1, 42, 999, 12345]
        
        for testID in testIDs {
            // Given
            let requestBody = [
                "jsonrpc": "2.0",
                "id": testID,
                "method": "tasks/get",
                "params": ["id": "task-test"]
            ] as [String : Any]
            
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            let decoder = JSONDecoder()
            let rpcRequest = try decoder.decode(JSONRPCRequest<TaskQueryParams>.self, from: jsonData)
            
            // When - Creating response with same ID
            let responseBody = [
                "jsonrpc": "2.0",
                "id": rpcRequest.id,
                "result": ["status": "ok"]
            ] as [String : Any]
            
            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let responseJson = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
            
            // Then
            #expect(responseJson?["id"] as? Int == testID, "ID \(testID) should be preserved")
        }
    }
    
    // MARK: - Multiple Parts Message Tests
    
    @Test("message/send should handle multiple message parts")
    func testMessageSendWithMultipleParts() throws {
        // Given - Message with text and file parts
        let requestBody = [
            "jsonrpc": "2.0",
            "id": 50,
            "method": "message/send",
            "params": [
                "message": [
                    "role": "user",
                    "parts": [
                        ["kind": "text", "text": "Analyze this image"],
                        ["kind": "file", "file": "https://example.com/image.png"]
                    ],
                    "messageId": UUID().uuidString,
                    "kind": "message"
                ]
            ]
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // When
        let decoder = JSONDecoder()
        let rpcRequest = try decoder.decode(JSONRPCRequest<MessageSendParams>.self, from: jsonData)
        
        // Then
        #expect(rpcRequest.params.message.parts.count == 2)
        
        if case .text(let text) = rpcRequest.params.message.parts[0] {
            #expect(text == "Analyze this image")
        } else {
            #expect(Bool(false), "First part should be text")
        }
        
        if case .file(_, let url) = rpcRequest.params.message.parts[1] {
            #expect(url?.absoluteString == "https://example.com/image.png")
        } else {
            #expect(Bool(false), "Second part should be file")
        }
    }
    
    // MARK: - Metadata Tests
    
    @Test("message/send should accept optional metadata")
    func testMessageSendWithMetadata() throws {
        // Given
        let requestBody = [
            "jsonrpc": "2.0",
            "id": 60,
            "method": "message/send",
            "params": [
                "message": [
                    "role": "user",
                    "parts": [["kind": "text", "text": "Hello"]],
                    "messageId": UUID().uuidString,
                    "kind": "message"
                ],
                "metadata": [
                    "customKey": "customValue",
                    "priority": 1
                ]
            ]
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // When
        let decoder = JSONDecoder()
        let rpcRequest = try decoder.decode(JSONRPCRequest<MessageSendParams>.self, from: jsonData)
        
        // Then
        #expect(rpcRequest.params.metadata != nil)
    }
    
    // MARK: - Configuration Tests
    
    @Test("message/send should accept optional configuration")
    func testMessageSendWithConfiguration() throws {
        // Given
        let requestBody = [
            "jsonrpc": "2.0",
            "id": 70,
            "method": "message/send",
            "params": [
                "message": [
                    "role": "user",
                    "parts": [["kind": "text", "text": "Hello"]],
                    "messageId": UUID().uuidString,
                    "kind": "message"
                ],
                "configuration": [
                    "acceptedOutputModes": ["text/plain", "application/json"],
                    "historyLength": 10,
                    "blocking": true
                ]
            ]
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // When
        let decoder = JSONDecoder()
        let rpcRequest = try decoder.decode(JSONRPCRequest<MessageSendParams>.self, from: jsonData)
        
        // Then
        #expect(rpcRequest.params.configuration != nil)
        #expect(rpcRequest.params.configuration?.acceptedOutputModes.count == 2)
        #expect(rpcRequest.params.configuration?.historyLength == 10)
        #expect(rpcRequest.params.configuration?.blocking == true)
    }
    
    // MARK: - Invalid Request Tests
    
    @Test("Should detect wrong jsonrpc version")
    func testDetectsWrongJSONRPCVersion() throws {
        // Given - A valid message structure with wrong jsonrpc version
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Test")],
            messageId: UUID().uuidString
        )
        let params = MessageSendParams(message: message)
        
        let encoder = JSONEncoder()
        let paramsData = try encoder.encode(params)
        let paramsJson = try JSONSerialization.jsonObject(with: paramsData) as! [String: Any]
        
        let requestBody = [
            "jsonrpc": "1.0",
            "id": 80,
            "method": "message/send",
            "params": paramsJson
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // When
        let decoder = JSONDecoder()
        let rpcRequest = try decoder.decode(JSONRPCRequest<MessageSendParams>.self, from: jsonData)
        
        // Then - Should decode but version is wrong
        #expect(rpcRequest.jsonrpc == "1.0") // Not "2.0" - this should be validated by server
    }
    
    @Test("Should handle missing jsonrpc field")
    func testHandlesMissingJSONRPCField() throws {
        // Given - Request without jsonrpc field
        let requestBody = [
            "id": 90,
            "method": "message/send",
            "params": ["message": ["role": "user"]]
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // When/Then - Should fail to decode
        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(JSONRPCRequest<MessageSendParams>.self, from: jsonData)
        }
    }
    
    @Test("Should handle missing id field")
    func testHandlesMissingIDField() throws {
        // Given - Request without id field
        let requestBody = [
            "jsonrpc": "2.0",
            "method": "message/send",
            "params": ["message": ["role": "user"]]
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // When/Then - Should fail to decode
        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(JSONRPCRequest<MessageSendParams>.self, from: jsonData)
        }
    }
}

