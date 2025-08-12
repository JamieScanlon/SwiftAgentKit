import Testing
import Foundation
@testable import SwiftAgentKit

@Suite("RequestBuilder Tests")
struct RequestBuilderTests {
    private let baseURL = URL(string: "https://api.example.com")!

    // MARK: - Helpers
    private func queryItems(from url: URL?) -> [URLQueryItem] {
        guard let url = url, let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return []
        }
        return components.queryItems ?? []
    }

    // MARK: - Core scenarios
    @Test("POST with body and no parameters uses httpBody")
    func testPostWithBodyNoParameters() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let bodyData = "hello".data(using: .utf8)!

        let request = try builder.createRequest(endpoint: "upload", method: .post, parameters: nil, headers: nil, body: bodyData)

        #expect(request.httpMethod == HTTPMethod.post.rawValue)
        #expect(request.httpBody == bodyData)
        #expect(queryItems(from: request.url).isEmpty)
    }

    @Test("GET with query parameters encodes into URL and no body")
    func testGetWithQueryParameters() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let params: [String: Any] = ["page": 1, "limit": 10]

        let request = try builder.createRequest(endpoint: "users", method: .get, parameters: params)

        #expect(request.httpMethod == HTTPMethod.get.rawValue)
        #expect(request.httpBody == nil)

        let items = queryItems(from: request.url)
        // Expect two items, order not guaranteed
        #expect(items.count == 2)
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(dict["page"] == "1")
        #expect(dict["limit"] == "10")
    }

    @Test("DELETE with query parameters encodes into URL and no body")
    func testDeleteWithQueryParameters() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let params: [String: Any] = ["force": true]

        let request = try builder.createRequest(endpoint: "resource/123", method: .delete, parameters: params)

        #expect(request.httpMethod == HTTPMethod.delete.rawValue)
        #expect(request.httpBody == nil)

        let items = queryItems(from: request.url)
        #expect(items.count == 1)
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(dict["force"] == "true")
    }

    @Test("POST with parameters and no body serializes JSON into httpBody")
    func testPostWithParametersNoBody() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let params: [String: Any] = ["name": "John", "email": "john@example.com"]

        let request = try builder.createRequest(endpoint: "users", method: .post, parameters: params)

        #expect(request.httpMethod == HTTPMethod.post.rawValue)
        #expect(request.httpBody != nil)

        if let body = request.httpBody {
            let json = try JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
            #expect(json?["name"] as? String == "John")
            #expect(json?["email"] as? String == "john@example.com")
        }

        // Default headers should be present
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("Explicit body takes precedence over parameters for POST/PUT/PATCH")
    func testExplicitBodyPrecedence() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let bodyData = "override".data(using: .utf8)!
        let params: [String: Any] = ["should": "not_be_used"]

        let postReq = try builder.createRequest(endpoint: "test", method: .post, parameters: params, body: bodyData)
        let putReq = try builder.createRequest(endpoint: "test", method: .put, parameters: params, body: bodyData)
        let patchReq = try builder.createRequest(endpoint: "test", method: .patch, parameters: params, body: bodyData)

        #expect(postReq.httpBody == bodyData)
        #expect(putReq.httpBody == bodyData)
        #expect(patchReq.httpBody == bodyData)
    }

    @Test("No body when both parameters and body are nil for POST")
    func testNoBodyWhenMissingForPost() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let request = try builder.createRequest(endpoint: "empty", method: .post)
        #expect(request.httpBody == nil)
    }

    @Test("GET without parameters leaves URL unchanged and no body")
    func testGetWithoutParameters() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let request = try builder.createRequest(endpoint: "ping", method: .get)
        #expect(request.httpBody == nil)
        #expect(queryItems(from: request.url).isEmpty)
    }

    @Test("Method correctness across all supported methods")
    func testMethodCorrectness() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let methods: [HTTPMethod] = [.get, .post, .put, .patch, .delete]
        for method in methods {
            let request = try builder.createRequest(endpoint: "resource", method: method)
            #expect(request.httpMethod == method.rawValue)
        }
    }

    @Test("Custom headers are merged with defaults")
    func testHeaderMerging() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let headers = ["Authorization": "Bearer token123", "X-Custom": "value"]
        let request = try builder.createRequest(endpoint: "secure", method: .get, headers: headers)

        // Defaults
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        // Custom
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token123")
        #expect(request.value(forHTTPHeaderField: "X-Custom") == "value")
    }

    // MARK: - Additional edge cases

    @Test("GET ignores provided body data")
    func testGetIgnoresBody() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let bodyData = "should be ignored".data(using: .utf8)!

        let request = try builder.createRequest(endpoint: "ignore", method: .get, body: bodyData)
        #expect(request.httpBody == nil)
    }

    @Test("PUT/PATCH with parameters only serializes JSON body")
    func testPutPatchWithParametersOnly() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let params: [String: Any] = ["a": 1, "b": true, "c": "str"]

        let putReq = try builder.createRequest(endpoint: "upd", method: .put, parameters: params)
        let patchReq = try builder.createRequest(endpoint: "upd", method: .patch, parameters: params)

        #expect(putReq.httpBody != nil)
        #expect(patchReq.httpBody != nil)
    }

    @Test("Invalid JSON parameters throw APIError.requestFailed")
    func testInvalidJSONParameters() {
        let builder = RequestBuilder(baseURL: baseURL)
        let badParams: [String: Any] = ["data": Data()] // Data is not JSON-serializable

        #expect(throws: APIError.self) {
            _ = try builder.createRequest(endpoint: "bad", method: .post, parameters: badParams)
        }
    }

    @Test("Endpoint path composition handles leading slash and no slash")
    func testEndpointPathComposition() throws {
        let builder = RequestBuilder(baseURL: baseURL)

        let req1 = try builder.createRequest(endpoint: "/users", method: .get)
        let req2 = try builder.createRequest(endpoint: "users", method: .get)

        #expect(req1.url?.path == "/users")
        #expect(req2.url?.path == "/users")
    }

    @Test("Query encoding handles special characters in keys and values")
    func testQueryEncodingSpecialCharacters() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let params: [String: Any] = [
            "q query": "hello world",
            "email": "a+b@test+example.com",
            "symbols": "!@#$%^&*()_+[]{}|;:'\",.<>/?`~"
        ]
        let request = try builder.createRequest(endpoint: "search", method: .get, parameters: params)
        let items = queryItems(from: request.url)
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(dict["q query"] == "hello world")
        #expect(dict["email"] == "a+b@test+example.com")
        #expect(dict["symbols"] == "!@#$%^&*()_+[]{}|;:'\",.<>/?`~")
    }

    @Test("Arrays in query parameters become stringified")
    func testArrayQueryParameterStringified() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let params: [String: Any] = ["ids": [1, 2, 3]]
        let request = try builder.createRequest(endpoint: "list", method: .get, parameters: params)
        let items = queryItems(from: request.url)
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(dict["ids"] == "[1, 2, 3]")
    }

    @Test("Overriding Content-Type appends value rather than replacing")
    func testContentTypeAppendBehavior() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let headers = ["Content-Type": "application/octet-stream"]
        let body = Data([0x01, 0x02])
        let request = try builder.createRequest(endpoint: "upload", method: .post, headers: headers, body: body)
        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        // Expect both the default and custom value to be present (comma-separated)
        #expect(contentType.contains("application/json"))
        #expect(contentType.contains("application/octet-stream"))
    }

    @Test("GET with empty parameters should not add query items")
    func testGetWithEmptyParameters() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let request = try builder.createRequest(endpoint: "empty", method: .get, parameters: [:])
        #expect(queryItems(from: request.url).isEmpty)
    }

    @Test("POST with empty parameters produces empty JSON object body")
    func testPostWithEmptyParametersProducesEmptyJSONObject() throws {
        let builder = RequestBuilder(baseURL: baseURL)
        let request = try builder.createRequest(endpoint: "empty", method: .post, parameters: [:])
        #expect(request.httpBody != nil)
        if let body = request.httpBody, let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
            #expect(json.isEmpty)
        }
    }
}


