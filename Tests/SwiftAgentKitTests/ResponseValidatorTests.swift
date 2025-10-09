import Testing
import Foundation
import EasyJSON
@testable import SwiftAgentKit

@Suite("ResponseValidator Tests")
struct ResponseValidatorTests {
    
    // MARK: - decodeEasyJSON Tests
    
    @Test("decodeEasyJSON - Valid JSON object")
    func testDecodeEasyJSONValidObject() throws {
        let validator = ResponseValidator()
        
        let jsonDict: [String: Any] = [
            "name": "John Doe",
            "age": 30,
            "isActive": true,
            "balance": 1234.56
        ]
        let data = try JSONSerialization.data(withJSONObject: jsonDict)
        
        let result = try validator.decodeEasyJSON(from: data)
        
        guard case .object(let dict) = result else {
            #expect(Bool(false), "Result should be a JSON object")
            return
        }
        
        guard case .string(let name) = dict["name"] else {
            #expect(Bool(false), "name should be a string")
            return
        }
        #expect(name == "John Doe")
        
        guard case .integer(let age) = dict["age"] else {
            #expect(Bool(false), "age should be an integer")
            return
        }
        #expect(age == 30)
        
        guard case .boolean(let isActive) = dict["isActive"] else {
            #expect(Bool(false), "isActive should be a boolean")
            return
        }
        #expect(isActive == true)
        
        guard case .double(let balance) = dict["balance"] else {
            #expect(Bool(false), "balance should be a double")
            return
        }
        #expect(balance == 1234.56)
    }
    
    @Test("decodeEasyJSON - Nested JSON object")
    func testDecodeEasyJSONNestedObject() throws {
        let validator = ResponseValidator()
        
        let jsonDict: [String: Any] = [
            "user": [
                "name": "Jane",
                "email": "jane@example.com"
            ],
            "metadata": [
                "version": "1.0",
                "timestamp": "2024-10-09"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: jsonDict)
        
        let result = try validator.decodeEasyJSON(from: data)
        
        guard case .object(let dict) = result else {
            #expect(Bool(false), "Result should be a JSON object")
            return
        }
        
        guard case .object(let userDict) = dict["user"] else {
            #expect(Bool(false), "user should be an object")
            return
        }
        
        guard case .string(let name) = userDict["name"] else {
            #expect(Bool(false), "name should be a string")
            return
        }
        #expect(name == "Jane")
        
        guard case .object(let metadataDict) = dict["metadata"] else {
            #expect(Bool(false), "metadata should be an object")
            return
        }
        
        guard case .string(let version) = metadataDict["version"] else {
            #expect(Bool(false), "version should be a string")
            return
        }
        #expect(version == "1.0")
    }
    
    @Test("decodeEasyJSON - Array values")
    func testDecodeEasyJSONArrayValues() throws {
        let validator = ResponseValidator()
        
        let jsonDict: [String: Any] = [
            "tags": ["swift", "ios", "testing"],
            "scores": [95, 87, 92],
            "flags": [true, false, true]
        ]
        let data = try JSONSerialization.data(withJSONObject: jsonDict)
        
        let result = try validator.decodeEasyJSON(from: data)
        
        guard case .object(let dict) = result else {
            #expect(Bool(false), "Result should be a JSON object")
            return
        }
        
        guard case .array(let tags) = dict["tags"] else {
            #expect(Bool(false), "tags should be an array")
            return
        }
        #expect(tags.count == 3)
        
        guard case .string(let firstTag) = tags[0] else {
            #expect(Bool(false), "first tag should be a string")
            return
        }
        #expect(firstTag == "swift")
        
        guard case .array(let scores) = dict["scores"] else {
            #expect(Bool(false), "scores should be an array")
            return
        }
        #expect(scores.count == 3)
        
        guard case .integer(let firstScore) = scores[0] else {
            #expect(Bool(false), "first score should be an integer")
            return
        }
        #expect(firstScore == 95)
        
        guard case .array(let flags) = dict["flags"] else {
            #expect(Bool(false), "flags should be an array")
            return
        }
        #expect(flags.count == 3)
        
        guard case .boolean(let firstFlag) = flags[0] else {
            #expect(Bool(false), "first flag should be a boolean")
            return
        }
        #expect(firstFlag == true)
    }
    
    @Test("decodeEasyJSON - Empty object")
    func testDecodeEasyJSONEmptyObject() throws {
        let validator = ResponseValidator()
        
        let jsonDict: [String: Any] = [:]
        let data = try JSONSerialization.data(withJSONObject: jsonDict)
        
        let result = try validator.decodeEasyJSON(from: data)
        
        guard case .object(let dict) = result else {
            #expect(Bool(false), "Result should be a JSON object")
            return
        }
        
        #expect(dict.isEmpty)
    }
    
    @Test("decodeEasyJSON - Mixed types")
    func testDecodeEasyJSONMixedTypes() throws {
        let validator = ResponseValidator()
        
        let jsonDict: [String: Any] = [
            "string": "text",
            "int": 42,
            "double": 3.14,
            "bool": false,
            "array": [1, 2, 3],
            "object": ["key": "value"],
            "null": NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: jsonDict)
        
        let result = try validator.decodeEasyJSON(from: data)
        
        guard case .object(let dict) = result else {
            #expect(Bool(false), "Result should be a JSON object")
            return
        }
        
        // Verify each type
        #expect(dict.count >= 6) // NSNull might not be included
        
        guard case .string(_) = dict["string"] else {
            #expect(Bool(false), "string should be a string type")
            return
        }
        
        guard case .integer(_) = dict["int"] else {
            #expect(Bool(false), "int should be an integer type")
            return
        }
        
        guard case .double(_) = dict["double"] else {
            #expect(Bool(false), "double should be a double type")
            return
        }
        
        guard case .boolean(_) = dict["bool"] else {
            #expect(Bool(false), "bool should be a boolean type")
            return
        }
        
        guard case .array(_) = dict["array"] else {
            #expect(Bool(false), "array should be an array type")
            return
        }
        
        guard case .object(_) = dict["object"] else {
            #expect(Bool(false), "object should be an object type")
            return
        }
    }
    
    @Test("decodeEasyJSON - Invalid data throws error")
    func testDecodeEasyJSONInvalidData() throws {
        let validator = ResponseValidator()
        
        let invalidData = "not valid json".data(using: .utf8)!
        
        do {
            _ = try validator.decodeEasyJSON(from: invalidData)
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            // Expected to throw
            #expect(error is APIError)
        }
    }
    
    @Test("decodeEasyJSON - Non-object JSON throws error")
    func testDecodeEasyJSONNonObject() throws {
        let validator = ResponseValidator()
        
        // JSON that's an array at the root level
        let jsonArray = [1, 2, 3]
        let data = try JSONSerialization.data(withJSONObject: jsonArray)
        
        do {
            _ = try validator.decodeEasyJSON(from: data)
            #expect(Bool(false), "Should have thrown invalidJSON error")
        } catch APIError.invalidJSON {
            // Expected error
            #expect(true)
        } catch {
            #expect(Bool(false), "Should have thrown APIError.invalidJSON, got \(error)")
        }
    }
    
    @Test("decodeEasyJSON - Empty data throws error")
    func testDecodeEasyJSONEmptyData() throws {
        let validator = ResponseValidator()
        
        let emptyData = Data()
        
        do {
            _ = try validator.decodeEasyJSON(from: emptyData)
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            // Expected to throw
            #expect(error is APIError)
        }
    }
    
    // MARK: - Comparison with legacy decodeJSON
    
    @Test("decodeEasyJSON and decodeJSON produce equivalent results")
    func testDecodeEasyJSONVsLegacy() throws {
        let validator = ResponseValidator()
        
        let jsonDict: [String: Any] = [
            "id": "123",
            "name": "Test User",
            "count": 42,
            "active": true
        ]
        let data = try JSONSerialization.data(withJSONObject: jsonDict)
        
        // Decode with both methods
        let legacyResult = try validator.decodeJSON(from: data)
        let newResult = try validator.decodeEasyJSON(from: data)
        
        // Verify legacy result
        #expect(legacyResult["id"] as? String == "123")
        #expect(legacyResult["name"] as? String == "Test User")
        #expect(legacyResult["count"] as? Int == 42)
        #expect(legacyResult["active"] as? Bool == true)
        
        // Verify new result
        guard case .object(let dict) = newResult else {
            #expect(Bool(false), "Result should be a JSON object")
            return
        }
        
        guard case .string(let id) = dict["id"] else {
            #expect(Bool(false), "id should be a string")
            return
        }
        #expect(id == "123")
        
        guard case .string(let name) = dict["name"] else {
            #expect(Bool(false), "name should be a string")
            return
        }
        #expect(name == "Test User")
        
        guard case .integer(let count) = dict["count"] else {
            #expect(Bool(false), "count should be an integer")
            return
        }
        #expect(count == 42)
        
        guard case .boolean(let active) = dict["active"] else {
            #expect(Bool(false), "active should be a boolean")
            return
        }
        #expect(active == true)
    }
    
    @Test("decodeEasyJSON - Real-world API response structure")
    func testDecodeEasyJSONRealWorldResponse() throws {
        let validator = ResponseValidator()
        
        let jsonDict: [String: Any] = [
            "status": "success",
            "data": [
                "user": [
                    "id": 12345,
                    "username": "testuser",
                    "email": "test@example.com",
                    "verified": true
                ],
                "permissions": ["read", "write"],
                "lastLogin": "2024-10-09T12:00:00Z"
            ],
            "meta": [
                "requestId": "req-abc-123",
                "timestamp": 1696857600,
                "version": 2.1
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: jsonDict)
        
        let result = try validator.decodeEasyJSON(from: data)
        
        guard case .object(let dict) = result else {
            #expect(Bool(false), "Result should be a JSON object")
            return
        }
        
        // Verify status
        guard case .string(let status) = dict["status"] else {
            #expect(Bool(false), "status should be a string")
            return
        }
        #expect(status == "success")
        
        // Verify nested data structure
        guard case .object(let dataDict) = dict["data"] else {
            #expect(Bool(false), "data should be an object")
            return
        }
        
        guard case .object(let userDict) = dataDict["user"] else {
            #expect(Bool(false), "user should be an object")
            return
        }
        
        guard case .integer(let userId) = userDict["id"] else {
            #expect(Bool(false), "user id should be an integer")
            return
        }
        #expect(userId == 12345)
        
        guard case .boolean(let verified) = userDict["verified"] else {
            #expect(Bool(false), "verified should be a boolean")
            return
        }
        #expect(verified == true)
        
        // Verify array
        guard case .array(let permissions) = dataDict["permissions"] else {
            #expect(Bool(false), "permissions should be an array")
            return
        }
        #expect(permissions.count == 2)
        
        // Verify meta
        guard case .object(let metaDict) = dict["meta"] else {
            #expect(Bool(false), "meta should be an object")
            return
        }
        
        guard case .double(let version) = metaDict["version"] else {
            #expect(Bool(false), "version should be a double")
            return
        }
        #expect(version == 2.1)
    }
}

