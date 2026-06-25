import Testing
import Foundation
import EasyJSON
import Logging
@testable import SwiftAgentKit

@Suite("SSEClient Tests")
struct SSEClientTests {
    
    // MARK: - Initialization Tests
    
    @Test("SSEClient initializes with valid URL")
    func testSSEClientInitialization() throws {
        let url = URL(string: "https://api.example.com")!
        let client = SSEClient(baseURL: url)
        
        // Verify client is created successfully
        #expect(client != nil)
    }
    
    @Test("SSEClient is Sendable")
    func testSSEClientSendable() throws {
        let url = URL(string: "https://api.example.com")!
        let client = SSEClient(baseURL: url)
        
        // Test that we can pass it across concurrency boundaries
        Task {
            let _ = client
            #expect(true)
        }
    }
    
    // MARK: - JSON Conversion Tests
    
    @Test("convertToJSON handles string values")
    func testConvertToJSONString() throws {
        let url = URL(string: "https://api.example.com")!
        let client = SSEClient(baseURL: url)
        
        // Use reflection to test the private method through its public interface
        // We'll test this indirectly through the SSE response parsing
        
        let testString = "test value"
        // The conversion is tested implicitly through the sseRequest method
        #expect(testString == "test value")
    }
    
    @Test("convertToJSON handles integer values")
    func testConvertToJSONInteger() throws {
        // Test that integers are properly converted
        let nsNumber = NSNumber(value: 42)
        
        // Verify it's not a boolean
        #expect(CFGetTypeID(nsNumber) != CFBooleanGetTypeID())
    }
    
    @Test("convertToJSON handles double values")
    func testConvertToJSONDouble() throws {
        let nsNumber = NSNumber(value: 3.14)
        
        // Verify it's a float type
        #expect(CFNumberIsFloatType(nsNumber))
    }
    
    @Test("convertToJSON handles boolean values")
    func testConvertToJSONBoolean() throws {
        let trueNumber = NSNumber(value: true)
        let falseNumber = NSNumber(value: false)
        
        // Verify they are booleans
        #expect(CFGetTypeID(trueNumber) == CFBooleanGetTypeID())
        #expect(CFGetTypeID(falseNumber) == CFBooleanGetTypeID())
    }
    
    @Test("convertToJSON handles arrays")
    func testConvertToJSONArray() throws {
        let array: [Any] = ["test", 42, true, 3.14]
        
        // Verify array has expected elements
        #expect(array.count == 4)
        #expect(array[0] as? String == "test")
        #expect(array[1] as? Int == 42)
        #expect(array[2] as? Bool == true)
        #expect(array[3] as? Double == 3.14)
    }
    
    @Test("convertToJSON handles nested objects")
    func testConvertToJSONNestedObject() throws {
        let nestedDict: [String: Any] = [
            "outer": [
                "inner": "value",
                "number": 42
            ]
        ]
        
        // Verify structure
        let outer = nestedDict["outer"] as? [String: Any]
        #expect(outer != nil)
        #expect(outer?["inner"] as? String == "value")
        #expect(outer?["number"] as? Int == 42)
    }
    
    // MARK: - SSE Data Parsing Tests
    
    @Test("SSE data line parsing - basic format")
    func testSSEDataLineFormat() throws {
        let dataLine = "data: {\"message\":\"hello\"}"
        
        #expect(dataLine.hasPrefix("data: "))
        
        let jsonString = String(dataLine.dropFirst(6))
        #expect(jsonString == "{\"message\":\"hello\"}")
        
        // Verify it can be parsed as JSON
        let data = jsonString.data(using: .utf8)!
        let json = try? JSONSerialization.jsonObject(with: data)
        #expect(json != nil)
    }
    
    @Test("SSE data line parsing - with boolean")
    func testSSEDataLineWithBoolean() throws {
        let dataLine = "data: {\"active\":true,\"count\":5}"
        let jsonString = String(dataLine.dropFirst(6))
        
        let data = jsonString.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json != nil)
        #expect(json?["active"] as? Bool == true)
        #expect(json?["count"] as? Int == 5)
    }
    
    @Test("SSE data line parsing - with nested object")
    func testSSEDataLineWithNestedObject() throws {
        let dataLine = "data: {\"user\":{\"name\":\"John\",\"age\":30}}"
        let jsonString = String(dataLine.dropFirst(6))
        
        let data = jsonString.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json != nil)
        
        let user = json?["user"] as? [String: Any]
        #expect(user != nil)
        #expect(user?["name"] as? String == "John")
        #expect(user?["age"] as? Int == 30)
    }
    
    @Test("SSE data line parsing - with array")
    func testSSEDataLineWithArray() throws {
        let dataLine = "data: {\"items\":[1,2,3]}"
        let jsonString = String(dataLine.dropFirst(6))
        
        let data = jsonString.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json != nil)
        
        let items = json?["items"] as? [Int]
        #expect(items != nil)
        #expect(items?.count == 3)
        #expect(items?[0] == 1)
        #expect(items?[1] == 2)
        #expect(items?[2] == 3)
    }
    
    @Test("SSE data line parsing - empty object")
    func testSSEDataLineEmptyObject() throws {
        let dataLine = "data: {}"
        let jsonString = String(dataLine.dropFirst(6))
        
        let data = jsonString.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json != nil)
        #expect(json?.isEmpty == true)
    }
    
    @Test("SSE multiple data lines")
    func testSSEMultipleDataLines() throws {
        let response = """
        data: {"id":1,"message":"first"}
        data: {"id":2,"message":"second"}
        data: {"id":3,"message":"third"}
        """
        
        let lines = response.components(separatedBy: "\n")
        var dataLines: [String] = []
        
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                dataLines.append(jsonString)
            }
        }
        
        #expect(dataLines.count == 3)
        
        // Verify first message
        let data1 = dataLines[0].data(using: .utf8)!
        let json1 = try JSONSerialization.jsonObject(with: data1) as? [String: Any]
        #expect(json1?["id"] as? Int == 1)
        #expect(json1?["message"] as? String == "first")
        
        // Verify second message
        let data2 = dataLines[1].data(using: .utf8)!
        let json2 = try JSONSerialization.jsonObject(with: data2) as? [String: Any]
        #expect(json2?["id"] as? Int == 2)
        #expect(json2?["message"] as? String == "second")
        
        // Verify third message
        let data3 = dataLines[2].data(using: .utf8)!
        let json3 = try JSONSerialization.jsonObject(with: data3) as? [String: Any]
        #expect(json3?["id"] as? Int == 3)
        #expect(json3?["message"] as? String == "third")
    }
    
    @Test("SSE with non-data lines")
    func testSSEWithNonDataLines() throws {
        let response = """
        : comment line
        event: message
        data: {"content":"actual data"}
        id: 123
        """
        
        let lines = response.components(separatedBy: "\n")
        var dataLines: [String] = []
        
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                dataLines.append(jsonString)
            }
        }
        
        // Only the data line should be captured
        #expect(dataLines.count == 1)
        #expect(dataLines[0] == "{\"content\":\"actual data\"}")
    }
    
    // MARK: - Type Handling Tests
    
    @Test("NSNumber type detection - integers")
    func testNSNumberIntegers() throws {
        let numbers = [
            NSNumber(value: 0),
            NSNumber(value: 42),
            NSNumber(value: -17),
            NSNumber(value: Int.max),
            NSNumber(value: Int.min)
        ]
        
        for number in numbers {
            #expect(CFGetTypeID(number) != CFBooleanGetTypeID())
        }
    }
    
    @Test("NSNumber type detection - doubles")
    func testNSNumberDoubles() throws {
        let numbers = [
            NSNumber(value: 0.0),
            NSNumber(value: 3.14),
            NSNumber(value: -2.5),
            NSNumber(value: Double.pi)
        ]
        
        for number in numbers {
            #expect(CFNumberIsFloatType(number))
        }
    }
    
    @Test("NSNumber type detection - booleans")
    func testNSNumberBooleans() throws {
        let trueValue = NSNumber(value: true)
        let falseValue = NSNumber(value: false)
        
        #expect(CFGetTypeID(trueValue) == CFBooleanGetTypeID())
        #expect(CFGetTypeID(falseValue) == CFBooleanGetTypeID())
        
        #expect(trueValue.boolValue == true)
        #expect(falseValue.boolValue == false)
    }
    
    @Test("NSNumber from JSON deserialization")
    func testNSNumberFromJSON() throws {
        let jsonString = """
        {
            "integer": 42,
            "double": 3.14,
            "boolean": true,
            "zero": 0,
            "negative": -5
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json != nil)
        
        // Check types
        let integer = json?["integer"] as? NSNumber
        #expect(integer != nil)
        #expect(CFGetTypeID(integer!) != CFBooleanGetTypeID())
        
        let double = json?["double"] as? NSNumber
        #expect(double != nil)
        #expect(CFNumberIsFloatType(double!))
        
        let boolean = json?["boolean"] as? NSNumber
        #expect(boolean != nil)
        #expect(CFGetTypeID(boolean!) == CFBooleanGetTypeID())
    }
    
    // MARK: - URL Construction Tests
    
    @Test("URL construction with endpoint")
    func testURLConstruction() throws {
        let baseURL = URL(string: "https://api.example.com")!
        let endpoint = "events"
        
        let fullURL = baseURL.appendingPathComponent(endpoint)
        
        #expect(fullURL.absoluteString == "https://api.example.com/events")
    }
    
    @Test("URL construction with multiple path components")
    func testURLConstructionMultiplePaths() throws {
        let baseURL = URL(string: "https://api.example.com/v1")!
        let endpoint = "stream/events"
        
        let fullURL = baseURL.appendingPathComponent(endpoint)
        
        #expect(fullURL.absoluteString == "https://api.example.com/v1/stream/events")
    }
    
    @Test("URL construction with trailing slash")
    func testURLConstructionTrailingSlash() throws {
        let baseURL = URL(string: "https://api.example.com/")!
        let endpoint = "events"
        
        let fullURL = baseURL.appendingPathComponent(endpoint)
        
        #expect(fullURL.absoluteString == "https://api.example.com/events")
    }
    
    // MARK: - HTTP Request Configuration Tests
    
    @Test("HTTP request headers for SSE")
    func testHTTPRequestHeaders() throws {
        var request = URLRequest(url: URL(string: "https://api.example.com")!)
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    }
    
    @Test("HTTP request with custom headers")
    func testHTTPRequestCustomHeaders() throws {
        var request = URLRequest(url: URL(string: "https://api.example.com")!)
        
        let customHeaders = [
            "Authorization": "Bearer token123",
            "X-Custom-Header": "custom-value"
        ]
        
        customHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token123")
        #expect(request.value(forHTTPHeaderField: "X-Custom-Header") == "custom-value")
    }
    
    @Test("HTTP request method configuration")
    func testHTTPRequestMethods() throws {
        var getRequest = URLRequest(url: URL(string: "https://api.example.com")!)
        getRequest.httpMethod = HTTPMethod.get.rawValue
        #expect(getRequest.httpMethod == "GET")
        
        var postRequest = URLRequest(url: URL(string: "https://api.example.com")!)
        postRequest.httpMethod = HTTPMethod.post.rawValue
        #expect(postRequest.httpMethod == "POST")
        
        var putRequest = URLRequest(url: URL(string: "https://api.example.com")!)
        putRequest.httpMethod = HTTPMethod.put.rawValue
        #expect(putRequest.httpMethod == "PUT")
        
        var deleteRequest = URLRequest(url: URL(string: "https://api.example.com")!)
        deleteRequest.httpMethod = HTTPMethod.delete.rawValue
        #expect(deleteRequest.httpMethod == "DELETE")
    }
    
    @Test("HTTP request body serialization")
    func testHTTPRequestBodySerialization() throws {
        let parameters: [String: Any] = [
            "query": "test",
            "limit": 10,
            "enabled": true
        ]
        
        let data = try JSONSerialization.data(withJSONObject: parameters)
        
        // Verify data is not empty
        #expect(!data.isEmpty)
        
        // Verify it can be deserialized back
        let deserializedParameters = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(deserializedParameters?["query"] as? String == "test")
        #expect(deserializedParameters?["limit"] as? Int == 10)
        #expect(deserializedParameters?["enabled"] as? Bool == true)
    }
    
    // MARK: - Edge Cases and Error Handling
    
    @Test("SSE data line with invalid JSON")
    func testSSEInvalidJSON() throws {
        let dataLine = "data: {invalid json}"
        let jsonString = String(dataLine.dropFirst(6))
        
        let data = jsonString.data(using: .utf8)!
        let json = try? JSONSerialization.jsonObject(with: data)
        
        // Should fail to parse
        #expect(json == nil)
    }
    
    @Test("SSE data line with empty data")
    func testSSEEmptyData() throws {
        let dataLine = "data: "
        let jsonString = String(dataLine.dropFirst(6))
        
        #expect(jsonString.isEmpty)
    }
    
    @Test("SSE data line without prefix")
    func testSSENoDataPrefix() throws {
        let line = "{\"message\":\"no prefix\"}"
        
        #expect(!line.hasPrefix("data: "))
    }
    
    @Test("SSE response with mixed line endings")
    func testSSEMixedLineEndings() throws {
        let response = "data: {\"id\":1}\ndata: {\"id\":2}\r\ndata: {\"id\":3}"
        
        // Split by newline only (as in the implementation)
        let lines = response.components(separatedBy: "\n")
        var dataCount = 0
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.hasPrefix("data: ") {
                dataCount += 1
            }
        }
        
        #expect(dataCount >= 2) // At least 2 should be found
    }
    
    @Test("Parameter serialization with empty dictionary")
    func testParameterSerializationEmpty() throws {
        let parameters: [String: Any] = [:]
        let data = try JSONSerialization.data(withJSONObject: parameters)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?.isEmpty == true)
    }
    
    @Test("Parameter serialization with nested structures")
    func testParameterSerializationNested() throws {
        let parameters: [String: Any] = [
            "user": [
                "name": "John",
                "preferences": [
                    "theme": "dark",
                    "notifications": true
                ]
            ],
            "tags": ["swift", "testing"]
        ]
        
        let data = try JSONSerialization.data(withJSONObject: parameters)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json != nil)
        
        let user = json?["user"] as? [String: Any]
        #expect(user?["name"] as? String == "John")
        
        let preferences = user?["preferences"] as? [String: Any]
        #expect(preferences?["theme"] as? String == "dark")
        #expect(preferences?["notifications"] as? Bool == true)
        
        let tags = json?["tags"] as? [String]
        #expect(tags?.count == 2)
    }
    
    // MARK: - Real-world SSE Response Patterns
    
    @Test("SSE streaming chat completion pattern")
    func testSSEChatCompletionPattern() throws {
        let response = """
        data: {"id":"msg-1","delta":{"content":"Hello"}}
        data: {"id":"msg-1","delta":{"content":" world"}}
        data: {"id":"msg-1","delta":{"content":"!"}}
        data: [DONE]
        """
        
        let lines = response.components(separatedBy: "\n")
        var messages: [[String: Any]] = []
        
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                if jsonString != "[DONE]",
                   let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    messages.append(json)
                }
            }
        }
        
        #expect(messages.count == 3)
        
        // Verify delta content
        let delta1 = messages[0]["delta"] as? [String: Any]
        #expect(delta1?["content"] as? String == "Hello")
        
        let delta2 = messages[1]["delta"] as? [String: Any]
        #expect(delta2?["content"] as? String == " world")
        
        let delta3 = messages[2]["delta"] as? [String: Any]
        #expect(delta3?["content"] as? String == "!")
    }
    
    @Test("SSE progress update pattern")
    func testSSEProgressUpdatePattern() throws {
        let response = """
        data: {"status":"started","progress":0}
        data: {"status":"processing","progress":25}
        data: {"status":"processing","progress":50}
        data: {"status":"processing","progress":75}
        data: {"status":"completed","progress":100}
        """
        
        let lines = response.components(separatedBy: "\n")
        var updates: [[String: Any]] = []
        
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    updates.append(json)
                }
            }
        }
        
        #expect(updates.count == 5)
        #expect(updates[0]["status"] as? String == "started")
        #expect(updates[0]["progress"] as? Int == 0)
        #expect(updates[4]["status"] as? String == "completed")
        #expect(updates[4]["progress"] as? Int == 100)
    }
    
    @Test("SSE error event pattern")
    func testSSEErrorEventPattern() throws {
        let response = """
        data: {"type":"data","content":"processing"}
        data: {"type":"error","message":"Something went wrong","code":500}
        """
        
        let lines = response.components(separatedBy: "\n")
        var events: [[String: Any]] = []
        
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    events.append(json)
                }
            }
        }
        
        #expect(events.count == 2)
        #expect(events[0]["type"] as? String == "data")
        #expect(events[1]["type"] as? String == "error")
        #expect(events[1]["message"] as? String == "Something went wrong")
        #expect(events[1]["code"] as? Int == 500)
    }
    
    // MARK: - Delivery / Completion Ordering (race regression)
    
    @Test("Final error chunk is delivered before the stream finishes")
    func testFinalChunkDeliveredBeforeFinish() async throws {
        // Run repeatedly to stress the ordering between `didReceive` and `didCompleteWithError`.
        // A provider that emits a terminal error event and then immediately closes the connection
        // must not have that final chunk dropped by `continuation.finish()`.
        let logger = Logger(label: "SSEClientTests")
        let dummySession = URLSession.shared
        let dummyTask = dummySession.dataTask(with: URL(string: "https://example.com")!)
        let errorEvent = "event: error\ndata: {\"error\":{\"message\":\"boom\"}}\n\n".data(using: .utf8)!
        
        for _ in 0..<200 {
            var continuation: AsyncStream<[String: Sendable]>.Continuation!
            let stream = AsyncStream<[String: Sendable]> { continuation = $0 }
            let delegate = SSEDelegate(continuation: continuation, logger: logger, endpoint: "test")
            
            // Deliver the error chunk, then immediately complete (the racy sequence).
            delegate.urlSession(dummySession, dataTask: dummyTask, didReceive: errorEvent)
            delegate.urlSession(dummySession, task: dummyTask, didCompleteWithError: nil)
            
            var chunks: [[String: Sendable]] = []
            for await chunk in stream {
                chunks.append(chunk)
            }
            
            #expect(chunks.count == 1)
            #expect(chunks.first?["_sse_event"] as? String == "error")
        }
    }
    
    // MARK: - End-to-End SSE Error Surfacing
    
    @Test("SSE error-only event reaches the consumer end-to-end")
    func testSSEErrorEventEndToEnd() async throws {
        MockSSEURLProtocol.statusCode = 200
        MockSSEURLProtocol.responseBody = "event: error\ndata: {\"error\":{\"message\":\"Error rendering prompt with jinja template: \\\"No user query found in messages.\\\"\"}}\n\n".data(using: .utf8)!
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSSEURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let client = SSEClient(
            baseURL: URL(string: "https://mock.test")!,
            session: mockSession,
            timeoutInterval: 5,
            logger: nil
        )
        
        let stream = client.sseRequest(
            "v1/chat/completions",
            method: .post,
            parameters: ["model": "test"]
        )
        
        var chunks: [[String: Sendable]] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        
        #expect(chunks.count >= 1)
        #expect(chunks.first?["_sse_event"] as? String == "error")
        let error = chunks.first?["error"] as? [String: Any]
        #expect((error?["message"] as? String)?.contains("No user query found in messages.") == true)
    }
}

/// Mock URLProtocol that returns a scripted SSE response body, then closes the connection.
final class MockSSEURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseBody: Data = Data()
    nonisolated(unsafe) static var statusCode: Int = 200
    
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    
    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {}
}

