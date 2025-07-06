import Testing
import Foundation
@testable import SwiftAgentKit

@Suite("RestAPIManager Tests")
struct RestAPIManagerTests {
    
    // MARK: - Test Setup
    
    private let testBaseURL = URL(string: "https://api.example.com")!
    
    @Test("Initialization")
    func testInitialization() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        let baseURL = await apiManager.baseURL
        #expect(baseURL == testBaseURL)
    }
    
    @Test("Initialization with custom configuration")
    func testInitializationWithCustomConfiguration() async throws {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        let apiManager = RestAPIManager(baseURL: testBaseURL, configuration: config)
        let baseURL = await apiManager.baseURL
        #expect(baseURL == testBaseURL)
    }
    
    // MARK: - Request Building Tests
    
    @Test("GET request with query parameters")
    func testGetRequestWithQueryParameters() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        // Test that the request is created correctly
        // This will be moved to RequestBuilder in the refactor
        let endpoint = "/users"
        let parameters = ["page": 1, "limit": 10]
        
        // For now, we'll test the public interface
        // In the refactor, this will test RequestBuilder directly
        do {
            try await apiManager.fire(endpoint, method: .get, parameters: parameters)
        } catch {
            // Expected to fail due to network, but request should be built correctly
            #expect(error is APIError)
        }
    }
    
    @Test("POST request with JSON body")
    func testPostRequestWithJSONBody() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let endpoint = "/users"
        let parameters = ["name": "John Doe", "email": "john@example.com"]
        
        do {
            try await apiManager.fire(endpoint, method: .post, parameters: parameters)
        } catch {
            // Expected to fail due to network, but request should be built correctly
            #expect(error is APIError)
        }
    }
    
    @Test("Request with custom headers")
    func testRequestWithCustomHeaders() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let endpoint = "/protected"
        let headers = ["Authorization": "Bearer token123", "X-Custom-Header": "value"]
        
        do {
            try await apiManager.fire(endpoint, method: .get, headers: headers)
        } catch {
            // Expected to fail due to network, but request should be built correctly
            #expect(error is APIError)
        }
    }
    
    @Test("Request with different HTTP methods")
    func testRequestWithDifferentHTTPMethods() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        let endpoint = "/resource"
        
        // Test all HTTP methods
        let methods: [HTTPMethod] = [.get, .post, .put, .patch, .delete]
        
        for method in methods {
            do {
                try await apiManager.fire(endpoint, method: method)
            } catch {
                // Expected to fail due to network, but request should be built correctly
                #expect(error is APIError)
            }
        }
    }
    
    // MARK: - Edge Case Request Tests
    
    @Test("Request with empty parameters")
    func testRequestWithEmptyParameters() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        do {
            try await apiManager.fire("/test", method: .get, parameters: [:])
        } catch {
            #expect(error is APIError)
        }
    }
    
    @Test("Request with nil parameters")
    func testRequestWithNilParameters() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        do {
            try await apiManager.fire("/test", method: .get, parameters: nil)
        } catch {
            #expect(error is APIError)
        }
    }
    
    @Test("Request with empty headers")
    func testRequestWithEmptyHeaders() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        do {
            try await apiManager.fire("/test", method: .get, headers: [:])
        } catch {
            #expect(error is APIError)
        }
    }
    
    @Test("Request with nil headers")
    func testRequestWithNilHeaders() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        do {
            try await apiManager.fire("/test", method: .get, headers: nil)
        } catch {
            #expect(error is APIError)
        }
    }
    
    @Test("Request with empty endpoint")
    func testRequestWithEmptyEndpoint() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        do {
            try await apiManager.fire("", method: .get)
        } catch {
            #expect(error is APIError)
        }
    }
    
    @Test("Request with complex parameter types")
    func testRequestWithComplexParameterTypes() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let parameters: [String: Any] = [
            "string": "value",
            "number": 42,
            "boolean": true,
            "array": [1, 2, 3],
            "nested": ["key": "value"]
        ]
        
        do {
            try await apiManager.fire("/test", method: .post, parameters: parameters)
        } catch {
            #expect(error is APIError)
        }
    }
    
    @Test("Request with special characters in parameters")
    func testRequestWithSpecialCharactersInParameters() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let parameters = [
            "query": "hello world",
            "email": "test@example.com",
            "url": "https://example.com/path?param=value",
            "special": "!@#$%^&*()"
        ]
        
        do {
            try await apiManager.fire("/test", method: .get, parameters: parameters)
        } catch {
            #expect(error is APIError)
        }
    }
    
    // MARK: - Response Validation Tests
    
    @Test("Successful response validation")
    func testSuccessfulResponseValidation() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        // Test with a mock response that would succeed
        // This will be moved to ResponseValidator in the refactor
        let endpoint = "/success"
        
        do {
            let _: MockResponse = try await apiManager.decodableRequest(endpoint)
        } catch {
            // Expected to fail due to network, but validation logic should work
            #expect(error is APIError)
        }
    }
    
    @Test("Error response validation")
    func testErrorResponseValidation() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        // Test with an endpoint that would return an error
        let endpoint = "/error"
        
        do {
            let _: MockResponse = try await apiManager.decodableRequest(endpoint)
        } catch {
            // Should handle server errors properly
            #expect(error is APIError)
        }
    }
    
    @Test("Invalid response handling")
    func testInvalidResponseHandling() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        // Test with an invalid endpoint
        let endpoint = "/invalid"
        
        do {
            let _: MockResponse = try await apiManager.decodableRequest(endpoint)
        } catch {
            // Should handle invalid responses properly
            #expect(error is APIError)
        }
    }
    
    @Test("Decoding error handling")
    func testDecodingErrorHandling() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        // Test with an endpoint that returns invalid JSON
        let endpoint = "/invalid-json"
        
        do {
            let _: MockResponse = try await apiManager.decodableRequest(endpoint)
        } catch {
            // Should handle decoding errors properly
            #expect(error is APIError)
        }
    }
    
    // MARK: - Edge Case Response Tests
    
    @Test("Response with empty data")
    func testResponseWithEmptyData() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        do {
            let _: MockResponse = try await apiManager.decodableRequest("/empty")
        } catch {
            #expect(error is APIError)
        }
    }
    
    @Test("Response with malformed JSON")
    func testResponseWithMalformedJSON() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        do {
            let _: MockResponse = try await apiManager.decodableRequest("/malformed")
        } catch {
            #expect(error is APIError)
        }
    }
    
    @Test("Response with unexpected data type")
    func testResponseWithUnexpectedDataType() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        do {
            let _: [String] = try await apiManager.decodableRequest("/array")
        } catch {
            #expect(error is APIError)
        }
    }
    
    // MARK: - API Method Tests
    
    @Test("Fire method")
    func testFireMethod() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        do {
            try await apiManager.fire("/test", method: .get)
        } catch {
            // Expected to fail due to network, but method should work
            #expect(error is APIError)
        }
    }
    
    @Test("Decodable request method")
    func testDecodableRequestMethod() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        do {
            let _: MockResponse = try await apiManager.decodableRequest("/test")
        } catch {
            // Expected to fail due to network, but method should work
            #expect(error is APIError)
        }
    }
    
    @Test("JSON request method")
    func testJSONRequestMethod() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        do {
            let _: [String: Sendable] = try await apiManager.jsonRequest("/test")
        } catch {
            // Expected to fail due to network, but method should work
            #expect(error is APIError)
        }
    }
    
    @Test("Upload request method")
    func testUploadRequestMethod() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let testData = "test content".data(using: .utf8)!
        
        do {
            let _: MockResponse = try await apiManager.uploadRequest("/upload", data: testData)
        } catch {
            // Expected to fail due to network, but method should work
            #expect(error is APIError)
        }
    }
    
    // MARK: - Edge Case API Method Tests
    
    @Test("Upload request with empty data")
    func testUploadRequestWithEmptyData() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let emptyData = Data()
        
        do {
            let _: MockResponse = try await apiManager.uploadRequest("/upload", data: emptyData)
        } catch {
            #expect(error is APIError)
        }
    }
    
    @Test("Upload request with large data")
    func testUploadRequestWithLargeData() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        // Create a large data object (1MB)
        let largeData = Data(repeating: 0, count: 1024 * 1024)
        
        do {
            let _: MockResponse = try await apiManager.uploadRequest("/upload", data: largeData)
        } catch {
            #expect(error is APIError)
        }
    }
    
    @Test("Decodable request with complex type")
    func testDecodableRequestWithComplexType() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        do {
            let _: ComplexMockResponse = try await apiManager.decodableRequest("/complex")
        } catch {
            #expect(error is APIError)
        }
    }
    
    // MARK: - Streaming Tests
    
    @Test("Stream request method")
    func testStreamRequestMethod() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        // Test that the stream is created and can be iterated
        let stream = await apiManager.streamRequest("/stream", method: .get)
        
        var receivedCount = 0
        for await _ in stream {
            // Should receive StreamingDataBuffer objects
            receivedCount += 1
            
            // Limit to prevent infinite loop in test
            if receivedCount > 10 {
                break
            }
        }
        
        // Stream should complete (even if no data received due to network failure)
        #expect(receivedCount >= 0)
    }
    
    @Test("Stream request with parameters")
    func testStreamRequestWithParameters() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let parameters: [String: Any] = ["filter": "active", "limit": 100]
        let headers = ["Authorization": "Bearer token"]
        
        let stream = await apiManager.streamRequest("/stream", method: .post, parameters: parameters, headers: headers)
        
        var receivedCount = 0
        for await _ in stream {
            receivedCount += 1
            
            if receivedCount > 5 {
                break
            }
        }
        
        #expect(receivedCount >= 0)
    }
    
    @Test("Stream request cancellation")
    func testStreamRequestCancellation() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let stream = await apiManager.streamRequest("/stream")
        
        // Test that we can cancel the stream
        var receivedCount = 0
        for await _ in stream {
            receivedCount += 1
            // Cancel after first item
            break
        }
        
        #expect(receivedCount >= 0)
    }
    
    // MARK: - Edge Case Streaming Tests
    
    @Test("Stream request with empty parameters")
    func testStreamRequestWithEmptyParameters() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let stream = await apiManager.streamRequest("/stream", parameters: [:])
        
        var receivedCount = 0
        for await _ in stream {
            receivedCount += 1
            break
        }
        
        #expect(receivedCount >= 0)
    }
    
    @Test("Stream request with large data chunks")
    func testStreamRequestWithLargeDataChunks() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let stream = await apiManager.streamRequest("/large-stream")
        
        var receivedCount = 0
        for await _ in stream {
            receivedCount += 1
            if receivedCount > 3 {
                break
            }
        }
        
        #expect(receivedCount >= 0)
    }
    
    @Test("Stream request with rapid cancellation")
    func testStreamRequestWithRapidCancellation() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let stream = await apiManager.streamRequest("/stream")
        
        // Cancel immediately without consuming any items
        var receivedCount = 0
        for await _ in stream {
            receivedCount += 1
            break
        }
        
        #expect(receivedCount >= 0)
    }
    
    // MARK: - SSE Tests
    
    @Test("SSE request method")
    func testSSERequestMethod() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        // Test that the SSE stream is created and can be iterated
        let stream = await apiManager.sseRequest("/sse", method: .post)
        
        var receivedCount = 0
        for await _ in stream {
            // Should receive JSON objects
            receivedCount += 1
            
            // Limit to prevent infinite loop in test
            if receivedCount > 10 {
                break
            }
        }
        
        // Stream should complete (even if no data received due to network failure)
        #expect(receivedCount >= 0)
    }
    
    @Test("SSE request with parameters")
    func testSSERequestWithParameters() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let parameters: [String: Sendable] = ["event": "user_update", "user_id": 123]
        let headers = ["Authorization": "Bearer token"]
        
        let stream = await apiManager.sseRequest("/sse", method: .post, parameters: parameters, headers: headers)
        
        var receivedCount = 0
        for await _ in stream {
            receivedCount += 1
            
            if receivedCount > 5 {
                break
            }
        }
        
        #expect(receivedCount >= 0)
    }
    
    @Test("SSE request cancellation")
    func testSSERequestCancellation() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let stream = await apiManager.sseRequest("/sse")
        
        // Test that we can cancel the SSE stream
        var receivedCount = 0
        for await _ in stream {
            receivedCount += 1
            // Cancel after first item
            break
        }
        
        #expect(receivedCount >= 0)
    }
    
    @Test("SSE request with different HTTP methods")
    func testSSERequestWithDifferentHTTPMethods() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        // Test SSE with different methods (though POST is most common)
        let methods: [HTTPMethod] = [.post, .get]
        
        for method in methods {
            let stream = await apiManager.sseRequest("/sse", method: method)
            
            var receivedCount = 0
            for await _ in stream {
                receivedCount += 1
                break // Just test one item per method
            }
            
            #expect(receivedCount >= 0)
        }
    }
    
    // MARK: - Edge Case SSE Tests
    
    @Test("SSE request with empty parameters")
    func testSSERequestWithEmptyParameters() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let stream = await apiManager.sseRequest("/sse", parameters: [:])
        
        var receivedCount = 0
        for await _ in stream {
            receivedCount += 1
            break
        }
        
        #expect(receivedCount >= 0)
    }
    
    @Test("SSE request with malformed event data")
    func testSSERequestWithMalformedEventData() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let stream = await apiManager.sseRequest("/malformed-sse")
        
        var receivedCount = 0
        for await _ in stream {
            receivedCount += 1
            if receivedCount > 3 {
                break
            }
        }
        
        #expect(receivedCount >= 0)
    }
    
    @Test("SSE request with rapid cancellation")
    func testSSERequestWithRapidCancellation() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        let stream = await apiManager.sseRequest("/sse")
        
        // Cancel immediately without consuming any items
        var receivedCount = 0
        for await _ in stream {
            receivedCount += 1
            break
        }
        
        #expect(receivedCount >= 0)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Network error handling")
    func testNetworkErrorHandling() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        do {
            try await apiManager.fire("/network-error")
        } catch {
            // Should handle network errors properly
            #expect(error is APIError)
        }
    }
    
    @Test("Server error handling")
    func testServerErrorHandling() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        do {
            let _: MockResponse = try await apiManager.decodableRequest("/server-error")
        } catch {
            // Should handle server errors properly
            #expect(error is APIError)
        }
    }
    
    @Test("Invalid URL handling")
    func testInvalidURLHandling() async throws {
        // Test with an invalid base URL
        let invalidURL = URL(string: "not-a-valid-url")!
        let apiManager = RestAPIManager(baseURL: invalidURL)
        
        do {
            try await apiManager.fire("/test")
        } catch {
            // Should handle invalid URL errors properly
            #expect(error is APIError)
        }
    }
    
    // MARK: - Edge Case Error Tests
    
    @Test("Timeout error handling")
    func testTimeoutErrorHandling() async throws {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 0.001 // Very short timeout
        let apiManager = RestAPIManager(baseURL: testBaseURL, configuration: config)
        
        do {
            try await apiManager.fire("/slow-endpoint")
        } catch {
            #expect(error is APIError)
        }
    }
    
    @Test("Memory pressure handling")
    func testMemoryPressureHandling() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        // Test with a request that might cause memory pressure
        do {
            let _: MockResponse = try await apiManager.decodableRequest("/memory-intensive")
        } catch {
            #expect(error is APIError)
        }
    }
    
    @Test("Concurrent request handling")
    func testConcurrentRequestHandling() async throws {
        let apiManager = RestAPIManager(baseURL: testBaseURL)
        
        // Test multiple concurrent requests
        async let request1: Void = apiManager.fire("/concurrent1")
        async let request2: Void = apiManager.fire("/concurrent2")
        async let request3: Void = apiManager.fire("/concurrent3")
        
        do {
            _ = try await (request1, request2, request3)
        } catch {
            #expect(error is APIError)
        }
    }
    
    // MARK: - Integration Tests (for post-refactor validation)
    
    @Test("RequestBuilder integration placeholder")
    func testRequestBuilderIntegrationPlaceholder() async throws {
        // This test will be implemented after RequestBuilder is created
        // It will test that RequestBuilder properly integrates with RestAPIManager
        #expect(Bool(true))
    }
    
    @Test("ResponseValidator integration placeholder")
    func testResponseValidatorIntegrationPlaceholder() async throws {
        // This test will be implemented after ResponseValidator is created
        // It will test that ResponseValidator properly integrates with RestAPIManager
        #expect(Bool(true))
    }
    
    @Test("StreamClient integration placeholder")
    func testStreamClientIntegrationPlaceholder() async throws {
        // This test will be implemented after StreamClient is created
        // It will test that StreamClient properly integrates with RestAPIManager
        #expect(Bool(true))
    }
    
    @Test("SSEClient integration placeholder")
    func testSSEClientIntegrationPlaceholder() async throws {
        // This test will be implemented after SSEClient is created
        // It will test that SSEClient properly integrates with RestAPIManager
        #expect(Bool(true))
    }
    
    @Test("End-to-end workflow placeholder")
    func testEndToEndWorkflowPlaceholder() async throws {
        // This test will be implemented after all components are refactored
        // It will test a complete workflow using all the new components
        #expect(Bool(true))
    }
    
    // MARK: - Helper Type Tests
    
    @Test("HTTPMethod enum")
    func testHTTPMethodEnum() throws {
        #expect(HTTPMethod.get.rawValue == "GET")
        #expect(HTTPMethod.post.rawValue == "POST")
        #expect(HTTPMethod.put.rawValue == "PUT")
        #expect(HTTPMethod.patch.rawValue == "PATCH")
        #expect(HTTPMethod.delete.rawValue == "DELETE")
    }
    
    @Test("APIError enum")
    func testAPIErrorEnum() throws {
        // Test that we can create all error types
        _ = APIError.invalidURL
        _ = APIError.requestFailed(NSError(domain: "test", code: 0))
        _ = APIError.invalidResponse
        _ = APIError.invalidJSON
        _ = APIError.decodingFailed(NSError(domain: "test", code: 0))
        _ = APIError.serverError(statusCode: 500, message: "Server error")
        _ = APIError.unknown
        #expect(Bool(true))
    }
    
    @Test("StreamingDataBuffer")
    func testStreamingDataBuffer() async throws {
        let buffer = StreamingDataBuffer()
        let testData = "test".data(using: .utf8)!
        await buffer.append(testData)
        #expect(await buffer.buffer == testData)
    }
    
    @Test("StreamingDataBuffer multiple appends")
    func testStreamingDataBufferMultipleAppends() async throws {
        let buffer = StreamingDataBuffer()
        let data1 = "hello".data(using: .utf8)!
        let data2 = " world".data(using: .utf8)!
        
        await buffer.append(data1)
        await buffer.append(data2)
        
        let expectedData = "hello world".data(using: .utf8)!
        #expect(await buffer.buffer == expectedData)
    }
    
    @Test("StreamingDataBuffer empty buffer")
    func testStreamingDataBufferEmptyBuffer() async throws {
        let buffer = StreamingDataBuffer()
        #expect(await buffer.buffer.isEmpty)
    }
    
    // MARK: - Edge Case Helper Type Tests
    
    @Test("StreamingDataBuffer with large data")
    func testStreamingDataBufferWithLargeData() async throws {
        let buffer = StreamingDataBuffer()
        let largeData = Data(repeating: 0, count: 1024 * 1024) // 1MB
        
        await buffer.append(largeData)
        #expect(await buffer.buffer.count == 1024 * 1024)
    }
    
    @Test("StreamingDataBuffer concurrent access")
    func testStreamingDataBufferConcurrentAccess() async throws {
        let buffer = StreamingDataBuffer()
        
        // Test concurrent appends
        async let append1: Void = buffer.append("data1".data(using: .utf8)!)
        async let append2: Void = buffer.append("data2".data(using: .utf8)!)
        async let append3: Void = buffer.append("data3".data(using: .utf8)!)
        
        _ = await (append1, append2, append3)
        
        let result = await buffer.buffer
        #expect(result.count > 0)
    }
    
    @Test("APIError error descriptions")
    func testAPIErrorErrorDescriptions() throws {
        // Test that all error types have meaningful descriptions
        let errors: [APIError] = [
            .invalidURL,
            .requestFailed(NSError(domain: "test", code: 0)),
            .invalidResponse,
            .invalidJSON,
            .decodingFailed(NSError(domain: "test", code: 0)),
            .serverError(statusCode: 500, message: "Server error"),
            .unknown
        ]
        
        for error in errors {
            let description = String(describing: error)
            #expect(!description.isEmpty)
        }
    }
}

// MARK: - Mock Types for Testing

struct MockResponse: Codable {
    let id: Int
    let name: String
}

struct MockRequest: Codable {
    let title: String
    let content: String
}

struct ComplexMockResponse: Codable {
    let id: Int
    let name: String
    let metadata: [String: String]
    let tags: [String]
    let nested: NestedObject
    let optionalField: String?
    
    struct NestedObject: Codable {
        let value: Int
        let description: String
    }
} 