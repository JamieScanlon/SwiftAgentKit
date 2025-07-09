//
//  RestAPIManager.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 5/3/25.
//

import Foundation
import Logging

public actor RestAPIManager {
    
    // MARK: - Properties
    public let session: URLSession
    public let baseURL: URL
    private let requestBuilder: RequestBuilder
    private let responseValidator: ResponseValidator
    private let streamClient: StreamClient
    private let sseClient: SSEClient
    
    // MARK: - Initialization
    public init(baseURL: URL, configuration: URLSessionConfiguration = .default) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: configuration)
        self.requestBuilder = RequestBuilder(baseURL: baseURL)
        self.responseValidator = ResponseValidator()
        self.streamClient = StreamClient(requestBuilder: requestBuilder)
        self.sseClient = SSEClient(baseURL: baseURL)
    }
    
    // MARK: - Public Methods
    
    /// Performs a request without returning a response
    public func fire(_ endpoint: String,
                               method: HTTPMethod = .get,
                               parameters: [String: Any]? = nil,
                               headers: [String: String]? = nil) async throws {
        
        let request = try requestBuilder.createRequest(endpoint: endpoint, method: method, parameters: parameters, headers: headers)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            try responseValidator.validateResponse(httpResponse, data: data)
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
        
        let request = try requestBuilder.createRequest(endpoint: endpoint, method: method, parameters: parameters, headers: headers, body: body)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            try responseValidator.validateResponse(httpResponse, data: data)
            return try responseValidator.decode(T.self, from: data)
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
        
        let request = try requestBuilder.createRequest(endpoint: endpoint, method: method, parameters: parameters, headers: headers)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            try responseValidator.validateResponse(httpResponse, data: data)
            return try responseValidator.decodeJSON(from: data)
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
        return streamClient.streamRequest(endpoint, method: method, parameters: parameters, headers: headers)
    }
    
    /// Performs a Server-Sent Events (SSE) request and returns an AsyncStream of parsed JSON objects
    /// This method automatically handles SSE parsing and returns complete JSON objects from the data events
    public func sseRequest(_ endpoint: String,
                          method: HTTPMethod = .post,
                          parameters: [String: Sendable]? = nil,
                          headers: [String: String]? = nil) -> AsyncStream<[String: Sendable]> {
        return sseClient.sseRequest(endpoint, method: method, parameters: parameters, headers: headers)
    }
    
    /// Performs a file upload request and returns the decoded response
    public func uploadRequest<T: Decodable>(_ endpoint: String,
                                    data: Data,
                                    headers: [String: String]? = nil) async throws -> T {
        
        let request = try requestBuilder.createRequest(endpoint: endpoint, method: .post, parameters: nil, headers: headers, body: data)
        
        do {
            let (responseData, response) = try await session.data(for: request)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            try responseValidator.validateResponse(httpResponse, data: responseData)
            return try responseValidator.decode(T.self, from: responseData)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.requestFailed(error)
        }
    }
    
    // MARK: - Private
    
    // Remove the old validateResponse and decoder logic, now handled by ResponseValidator
}



