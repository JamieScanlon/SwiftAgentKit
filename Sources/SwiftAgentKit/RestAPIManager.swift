//
//  RestAPIManager.swift
//  SileniaAIServer
//
//  Created by Marvin Scanlon on 5/3/25.
//

import Foundation

public enum APIError: Error {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case invalidJSON
    case decodingFailed(Error)
    case serverError(statusCode: Int, message: String?)
    case unknown
}

public actor RestAPIManager {
    
    // MARK: - Properties
    public let session: URLSession
    public let baseURL: URL
    
    // MARK: - Initialization
    public init(baseURL: URL, configuration: URLSessionConfiguration = .default) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: configuration)
        
        self.decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Public Methods
    
    /// Performs a request without returning a sesponse
    public func fire(_ endpoint: String,
                               method: HTTPMethod = .get,
                               parameters: [String: Any]? = nil,
                               headers: [String: String]? = nil) async throws {
        
        let request = try createRequest(endpoint: endpoint, method: method, parameters: parameters, headers: headers)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            // Check status code
            try validateResponse(httpResponse, data: data)
            
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.requestFailed(error)
        }
    }
    
    /// Performs a request and returns the decoded object
    public func decodableRequest<T: Decodable>(_ endpoint: String,
                                               method: HTTPMethod = .get,
                                               parameters: [String: Any]? = nil,
                                               headers: [String: String]? = nil,
                                               body: Data? = nil) async throws -> T {
        
        let request = try createRequest(endpoint: endpoint, method: method, parameters: parameters, headers: headers, body: body)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            // Check status code
            try validateResponse(httpResponse, data: data)
            
            // Decode response
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingFailed(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.requestFailed(error)
        }
    }
    
    /// Performs a request and returns the decoded object
    public func jsonRequest(_ endpoint: String,
                               method: HTTPMethod = .get,
                               parameters: [String: Any]? = nil,
                     headers: [String: String]? = nil) async throws -> [String: Sendable] {
        
        let request = try createRequest(endpoint: endpoint, method: method, parameters: parameters, headers: headers)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            // Check status code
            try validateResponse(httpResponse, data: data)
            
            // Decode response
            do {
                guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Sendable] else {
                    throw APIError.invalidJSON
                }
                return json
            } catch {
                throw APIError.decodingFailed(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.requestFailed(error)
        }
    }
    
    /// Performs a request and returns an AsyncStream of partial decoded objects
    public func streamRequest(_ endpoint: String,
                                     method: HTTPMethod = .get,
                                     parameters: [String: Any]? = nil,
                                     headers: [String: String]? = nil) -> AsyncStream<StreamingDataBuffer> {
        
        return AsyncStream { continuation in
            let task = Task {
                do {
                    // Wait for the task to complete
                    try await withCheckedThrowingContinuation { (wait: CheckedContinuation<Void, Error>) -> Void in
                        
                        // Create a delegate to handle the streaming data
                        let delegate = StreamDelegate(continuation: continuation) {
                            // Make sure to wait until the dataTask is complete
                            wait.resume()
                        }
                        
                        // Create a session with the delegate
                        let streamSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                        
                        do {
                            let request = try createRequest(endpoint: endpoint, method: method, parameters: parameters, headers: headers)
                            // Start the task
                            let task = streamSession.dataTask(with: request)
                            task.resume()
                        } catch {
                            wait.resume(throwing: error)
                        }
                        
                        // Set cancellation handler
                        continuation.onTermination = { _ in
                            wait.resume()
                        }
                    }
                    
                } catch {
                    print("Stream request error: \(error)")
                    continuation.finish()
                }
            }
            
            // If the task is cancelled, finish the stream
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    /// Performs a Server-Sent Events (SSE) request and returns an AsyncStream of parsed JSON objects
    /// This method automatically handles SSE parsing and returns complete JSON objects from the data events
    public func sseRequest(_ endpoint: String,
                          method: HTTPMethod = .post,
                          parameters: [String: Sendable]? = nil,
                          headers: [String: String]? = nil) -> AsyncStream<[String: Sendable]> {
        
        return AsyncStream { continuation in
            Task {
                // Create a custom SSE request
                let url = baseURL.appendingPathComponent(endpoint)
                var request = URLRequest(url: url)
                request.httpMethod = method.rawValue
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                
                // Add custom headers
                headers?.forEach { key, value in
                    request.setValue(value, forHTTPHeaderField: key)
                }
                
                // Add parameters to body for POST requests
                if let parameters = parameters, method == .post {
                    do {
                        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
                    } catch {
                        print("SSE Error: Failed to serialize parameters: \(error)")
                        continuation.finish()
                        return
                    }
                }
                
                let session = URLSession.shared
                let task = session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        print("SSE Error: \(error)")
                        continuation.finish()
                        return
                    }
                    
                    guard let data = data,
                          let responseString = String(data: data, encoding: .utf8) else {
                        continuation.finish()
                        return
                    }
                    
                    // Parse SSE events
                    let lines = responseString.components(separatedBy: "\n")
                    for line in lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6)) // Remove "data: " prefix
                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Sendable] {
                                continuation.yield(json)
                            }
                        }
                    }
                    continuation.finish()
                }
                task.resume()
                
                // Set cancellation handler
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }
    }
    
    /// Performs a file upload request and returns the decoded response
    public func uploadRequest<T: Decodable>(_ endpoint: String,
                                    data: Data,
                                    headers: [String: String]? = nil) async throws -> T {
        
        // Create URL
        let url = baseURL.appendingPathComponent(endpoint)
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.httpBody = data
        
        // Add headers
        headers?.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        do {
            let (responseData, response) = try await session.data(for: request)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            // Check status code
            try validateResponse(httpResponse, data: responseData)
            
            // Decode response
            do {
                return try decoder.decode(T.self, from: responseData)
            } catch {
                throw APIError.decodingFailed(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.requestFailed(error)
        }
    }
    
    // MARK: - Private
    
    private let decoder: JSONDecoder = JSONDecoder()
    
    private func createRequest(endpoint: String,
                               method: HTTPMethod,
                               parameters: [String: Any]?,
                               headers: [String: String]?,
                               body: Data? = nil) throws -> URLRequest {
        
        // Create URL
        let url = baseURL.appendingPathComponent(endpoint)
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        
        // Add headers
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        headers?.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        // Add parameters
        if let parameters = parameters {
            switch method {
            case .get, .delete:
                // Add query parameters to URL
                if var components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
                    components.queryItems = parameters.map { key, value in
                        URLQueryItem(name: key, value: "\(value)")
                    }
                    request.url = components.url
                }
            case .post, .put, .patch:
                // Add parameters to body
                do {
                    if let data = body {
                        request.httpBody = data
                    } else {
                        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
                    }
                } catch {
                    throw APIError.requestFailed(error)
                }
            }
        }
        
        return request
    }
    
    private func validateResponse(_ response: HTTPURLResponse, data: Data) throws {
        let statusCode = response.statusCode
        
        guard (200...299).contains(statusCode) else {
            // Try to parse error message from response
            var errorMessage: String?
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorData["message"] as? String {
                errorMessage = message
            }
            
            throw APIError.serverError(statusCode: statusCode, message: errorMessage)
        }
    }
}

// MARK: - Helper Types

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - StreamingDataBuffer

public actor StreamingDataBuffer {
    
    public var buffer = Data()
    public func append(_ data: Data) {
        buffer.append(data)
    }
}

// MARK: - URLSessionTaskDelegate for Stream Handling

final class StreamDelegate: NSObject, URLSessionDataDelegate {
    private let continuation: AsyncStream<StreamingDataBuffer>.Continuation
    private let buffer = StreamingDataBuffer()
    private let decoder = JSONDecoder()
    let completionHandler: (@Sendable () -> Void)?
    
    init(continuation: AsyncStream<StreamingDataBuffer>.Continuation, completionHandler: (@Sendable () -> Void)? = nil) {
        self.continuation = continuation
        self.completionHandler = completionHandler
        super.init()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task {
            await buffer.append(data)
            
            // Process the buffer to find complete JSON objects
            continuation.yield(buffer)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Stream error: \(error)")
        }
        
        // Process any remaining data in the buffer
        continuation.yield(buffer)
        
        // Finish the stream
        continuation.finish()
        
        // Call completion handler
        completionHandler?()
    }
}

// MARK: - Usage Example

/* Example usage:
 
 struct User: Decodable {
 let id: Int
 let name: String
 }
 
 // Create API manager
 let apiManager = APIManager(baseURL: "https://api.example.com")
 
 // Regular request
 Task {
 do {
 let user: User = try await apiManager.request("/users/1")
 print("User: \(user)")
 } catch {
 print("Error: \(error)")
 }
 }
 
 // Streaming request
 Task {
 let userStream = apiManager.streamRequest<User>("/users/stream")
 for await user in userStream {
 print("Received user: \(user)")
 }
 print("Stream completed")
 }
 */
