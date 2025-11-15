//
//  RestAPIManager.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 5/3/25.
//

import Foundation
import Logging
import EasyJSON

public actor RestAPIManager {
    
    // MARK: - Properties
    public let session: URLSession
    public let baseURL: URL
    private let requestBuilder: RequestBuilder
    private let responseValidator: ResponseValidator
    private let streamClient: StreamClient
    private let sseClient: SSEClient
    private let logger: Logger
    
    // MARK: - Initialization
    /// Initialize RestAPIManager with configurable timeouts
    /// - Parameters:
    ///   - baseURL: The base URL for API requests
    ///   - configuration: URLSessionConfiguration for regular requests (default: .default)
    ///   - sseTimeoutInterval: Timeout interval in seconds for SSE connections (default: 600 seconds / 10 minutes)
    ///   - logger: Optional logger instance
    public init(baseURL: URL, configuration: URLSessionConfiguration = .default, sseTimeoutInterval: TimeInterval = 600.0, logger: Logger? = nil) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: configuration)
        let metadata: Logger.Metadata = ["baseURL": .string(baseURL.absoluteString)]
        if let logger {
            self.logger = logger
        } else {
            self.logger = SwiftAgentKitLogging.logger(
                for: .networking("RestAPIManager"),
                metadata: metadata
            )
        }
        let requestLogger = SwiftAgentKitLogging.logger(
            for: .networking("RequestBuilder"),
            metadata: metadata
        )
        let validatorLogger = SwiftAgentKitLogging.logger(
            for: .networking("ResponseValidator"),
            metadata: metadata
        )
        self.requestBuilder = RequestBuilder(baseURL: baseURL, logger: requestLogger)
        self.responseValidator = ResponseValidator(logger: validatorLogger)
        self.streamClient = StreamClient(
            requestBuilder: requestBuilder,
            logger: SwiftAgentKitLogging.logger(
                for: .networking("StreamClient"),
                metadata: metadata
            )
        )
        
        self.sseClient = SSEClient(
            baseURL: baseURL,
            session: nil,
            timeoutInterval: sseTimeoutInterval,
            logger: SwiftAgentKitLogging.logger(
                for: .networking("SSEClient"),
                metadata: metadata
            )
        )
    }
    
    // MARK: - Public Methods
    
    /// Performs a request without returning a response
    public func fire(_ endpoint: String,
                               method: HTTPMethod = .get,
                               parameters: [String: Any]? = nil,
                               headers: [String: String]? = nil) async throws {
        
        let request = try requestBuilder.createRequest(endpoint: endpoint, method: method, parameters: parameters, headers: headers)
        logRequestStart(
            endpoint: endpoint,
            method: method,
            headers: headers,
            parametersCount: parameters?.count,
            bodyBytes: request.httpBody?.count
        )
        logRequestDetails(parameters: parameters, headers: headers)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                logRequestFailure(endpoint: endpoint, method: method, error: APIError.invalidResponse)
                throw APIError.invalidResponse
            }
            try responseValidator.validateResponse(httpResponse, data: data)
            logRequestSuccess(
                endpoint: endpoint,
                method: method,
                statusCode: httpResponse.statusCode,
                responseBytes: data.count
            )
        } catch let error as APIError {
            logRequestFailure(endpoint: endpoint, method: method, error: error)
            throw error
        } catch {
            logRequestFailure(endpoint: endpoint, method: method, error: error)
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
        logRequestStart(
            endpoint: endpoint,
            method: method,
            headers: headers,
            parametersCount: parameters?.count,
            bodyBytes: request.httpBody?.count
        )
        logRequestDetails(parameters: parameters, headers: headers, body: body)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                logRequestFailure(endpoint: endpoint, method: method, error: APIError.invalidResponse)
                throw APIError.invalidResponse
            }
            try responseValidator.validateResponse(httpResponse, data: data)
            logRequestSuccess(
                endpoint: endpoint,
                method: method,
                statusCode: httpResponse.statusCode,
                responseBytes: data.count
            )
            return try responseValidator.decode(T.self, from: data)
        } catch let error as APIError {
            logRequestFailure(endpoint: endpoint, method: method, error: error)
            throw error
        } catch {
            logRequestFailure(endpoint: endpoint, method: method, error: error)
            throw APIError.requestFailed(error)
        }
    }
    
    /// Performs a request and returns the decoded object
    public func jsonRequest(_ endpoint: String,
                               method: HTTPMethod = .get,
                               parameters: [String: Any]? = nil,
                     headers: [String: String]? = nil) async throws -> [String: Sendable] {
        
        let request = try requestBuilder.createRequest(endpoint: endpoint, method: method, parameters: parameters, headers: headers)
        logRequestStart(
            endpoint: endpoint,
            method: method,
            headers: headers,
            parametersCount: parameters?.count,
            bodyBytes: request.httpBody?.count
        )
        logRequestDetails(parameters: parameters, headers: headers)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                logRequestFailure(endpoint: endpoint, method: method, error: APIError.invalidResponse)
                throw APIError.invalidResponse
            }
            try responseValidator.validateResponse(httpResponse, data: data)
            logRequestSuccess(
                endpoint: endpoint,
                method: method,
                statusCode: httpResponse.statusCode,
                responseBytes: data.count
            )
            return try responseValidator.decodeJSON(from: data)
        } catch let error as APIError {
            logRequestFailure(endpoint: endpoint, method: method, error: error)
            throw error
        } catch {
            logRequestFailure(endpoint: endpoint, method: method, error: error)
            throw APIError.requestFailed(error)
        }
    }
    
    /// Performs a request and returns the response as EasyJSON.JSON
    public func jsonRequest(_ endpoint: String,
                                method: HTTPMethod = .get,
                                parameters: [String: Any]? = nil,
                                headers: [String: String]? = nil) async throws -> JSON {
        
        let request = try requestBuilder.createRequest(endpoint: endpoint, method: method, parameters: parameters, headers: headers)
        logRequestStart(
            endpoint: endpoint,
            method: method,
            headers: headers,
            parametersCount: parameters?.count,
            bodyBytes: request.httpBody?.count
        )
        logRequestDetails(parameters: parameters, headers: headers)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                logRequestFailure(endpoint: endpoint, method: method, error: APIError.invalidResponse)
                throw APIError.invalidResponse
            }
            try responseValidator.validateResponse(httpResponse, data: data)
            logRequestSuccess(
                endpoint: endpoint,
                method: method,
                statusCode: httpResponse.statusCode,
                responseBytes: data.count
            )
            return try responseValidator.decodeEasyJSON(from: data)
        } catch let error as APIError {
            logRequestFailure(endpoint: endpoint, method: method, error: error)
            throw error
        } catch {
            logRequestFailure(endpoint: endpoint, method: method, error: error)
            throw APIError.requestFailed(error)
        }
    }
    
    /// Performs a request and returns an AsyncStream of partial decoded objects
    public func streamRequest(_ endpoint: String,
                                     method: HTTPMethod = .get,
                                     parameters: [String: Any]? = nil,
                                     headers: [String: String]? = nil) -> AsyncStream<StreamingDataBuffer> {
        logger.info(
            "Starting streaming request",
            metadata: [
                "endpoint": .string(endpoint),
                "method": .string(method.rawValue),
                "parameterCount": .stringConvertible(parameters?.count ?? 0),
                "headerCount": .stringConvertible(headers?.count ?? 0)
            ]
        )
        return streamClient.streamRequest(endpoint, method: method, parameters: parameters, headers: headers)
    }
    
    /// Performs a Server-Sent Events (SSE) request and returns an AsyncStream of parsed JSON objects
    /// This method automatically handles SSE parsing and returns complete JSON objects from the data events
    public func sseRequest(_ endpoint: String,
                          method: HTTPMethod = .post,
                          parameters: [String: Sendable]? = nil,
                          headers: [String: String]? = nil) -> AsyncStream<[String: Sendable]> {
        logger.info(
            "Starting SSE request",
            metadata: [
                "endpoint": .string(endpoint),
                "method": .string(method.rawValue),
                "parameterCount": .stringConvertible(parameters?.count ?? 0),
                "headerCount": .stringConvertible(headers?.count ?? 0)
            ]
        )
        return sseClient.sseRequest(endpoint, method: method, parameters: parameters, headers: headers)
    }
    
   
    
    /// Performs a Server-Sent Events (SSE) request and returns an AsyncStream of EasyJSON.JSON objects
    /// This method automatically handles SSE parsing and returns complete JSON objects from the data events
    public func sseRequest(_ endpoint: String,
                               method: HTTPMethod = .post,
                               parameters: JSON? = nil,
                               headers: [String: String]? = nil) -> AsyncStream<JSON> {
        logger.info(
            "Starting SSE request",
            metadata: [
                "endpoint": .string(endpoint),
                "method": .string(method.rawValue),
                "hasParameters": .string(parameters == nil ? "false" : "true"),
                "headerCount": .stringConvertible(headers?.count ?? 0)
            ]
        )
        return sseClient.sseRequest(endpoint, method: method, parameters: parameters, headers: headers)
    }
    
    /// Performs a file upload request and returns the decoded response
    public func uploadRequest<T: Decodable>(_ endpoint: String,
                                    data: Data,
                                    headers: [String: String]? = nil) async throws -> T {
        
        let request = try requestBuilder.createRequest(endpoint: endpoint, method: .post, parameters: nil, headers: headers, body: data)
        logRequestStart(
            endpoint: endpoint,
            method: .post,
            headers: headers,
            parametersCount: nil,
            bodyBytes: request.httpBody?.count
        )
        logRequestDetails(parameters: nil, headers: headers, body: data)
        
        do {
            let (responseData, response) = try await session.data(for: request)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                logRequestFailure(endpoint: endpoint, method: .post, error: APIError.invalidResponse)
                throw APIError.invalidResponse
            }
            try responseValidator.validateResponse(httpResponse, data: responseData)
            logRequestSuccess(
                endpoint: endpoint,
                method: .post,
                statusCode: httpResponse.statusCode,
                responseBytes: responseData.count
            )
            return try responseValidator.decode(T.self, from: responseData)
        } catch let error as APIError {
            logRequestFailure(endpoint: endpoint, method: .post, error: error)
            throw error
        } catch {
            logRequestFailure(endpoint: endpoint, method: .post, error: error)
            throw APIError.requestFailed(error)
        }
    }
    
    // MARK: - Private
    
    // Remove the old validateResponse and decoder logic, now handled by ResponseValidator
    
    private func logRequestStart(
        endpoint: String,
        method: HTTPMethod,
        headers: [String: String]?,
        parametersCount: Int?,
        bodyBytes: Int?
    ) {
        var metadata: Logger.Metadata = [
            "endpoint": .string(endpoint),
            "method": .string(method.rawValue),
            "headerCount": .stringConvertible(headers?.count ?? 0)
        ]
        if let parametersCount {
            metadata["parameterCount"] = .stringConvertible(parametersCount)
        }
        if let bodyBytes {
            metadata["bodyBytes"] = .stringConvertible(bodyBytes)
        }
        logger.info("Executing HTTP request", metadata: metadata)
    }
    
    private func logRequestDetails(
        parameters: [String: Any]?,
        headers: [String: String]?,
        body: Data? = nil
    ) {
        if let parameters, !parameters.isEmpty {
            logger.debug(
                "Request parameters prepared",
                metadata: ["parameterKeys": .string(parameters.keys.sorted().joined(separator: ","))]
            )
        }
        if let headers, !headers.isEmpty {
            logger.debug(
                "Request headers prepared",
                metadata: ["headerKeys": .string(headers.keys.sorted().joined(separator: ","))]
            )
        }
        if let body {
            logger.debug(
                "Request body prepared",
                metadata: ["bodyBytes": .stringConvertible(body.count)]
            )
        }
    }
    
    private func logRequestSuccess(
        endpoint: String,
        method: HTTPMethod,
        statusCode: Int,
        responseBytes: Int
    ) {
        logger.info(
            "HTTP request succeeded",
            metadata: [
                "endpoint": .string(endpoint),
                "method": .string(method.rawValue),
                "status": .stringConvertible(statusCode),
                "responseBytes": .stringConvertible(responseBytes)
            ]
        )
    }
    
    private func logRequestFailure(
        endpoint: String,
        method: HTTPMethod,
        error: Error
    ) {
        var metadata: Logger.Metadata = [
            "endpoint": .string(endpoint),
            "method": .string(method.rawValue),
            "error": .string(String(describing: error))
        ]
        if let apiError = error as? APIError {
            switch apiError {
            case .serverError(let status, _):
                metadata["status"] = .stringConvertible(status)
                logger.warning("HTTP request failed with server error", metadata: metadata)
                return
            case .invalidResponse:
                logger.warning("HTTP request returned invalid response", metadata: metadata)
                return
            default:
                logger.error("HTTP request failed", metadata: metadata)
                return
            }
        }
        logger.error("HTTP request failed", metadata: metadata)
    }
}



