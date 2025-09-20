//
//  RemoteTransport.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/20/25.
//

import Foundation
import Logging
import MCP
import SwiftAgentKit

/// Transport implementation for connecting to remote MCP servers over HTTP/HTTPS
public actor RemoteTransport: Transport {
    
    public enum RemoteTransportError: LocalizedError {
        case invalidURL(String)
        case authenticationFailed(String)
        case connectionFailed(String)
        case networkError(Swift.Error)
        case invalidResponse(String)
        case serverError(Int, String)
        case notConnected
        
        public var errorDescription: String? {
            switch self {
            case .invalidURL(let url):
                return "Invalid URL: \(url)"
            case .authenticationFailed(let message):
                return "Authentication failed: \(message)"
            case .connectionFailed(let message):
                return "Connection failed: \(message)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse(let message):
                return "Invalid response from server: \(message)"
            case .serverError(let code, let message):
                return "Server error \(code): \(message)"
            case .notConnected:
                return "Transport is not connected"
            }
        }
    }
    
    public nonisolated let logger: Logger
    
    private let serverURL: URL
    private let authProvider: (any AuthenticationProvider)?
    private let urlSession: URLSession
    private let connectionTimeout: TimeInterval
    private let requestTimeout: TimeInterval
    private let maxRetries: Int
    
    private var isConnected = false
    private var messageStream: AsyncThrowingStream<Data, Swift.Error>?
    private var messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation?
    private var backgroundTask: Task<Void, Never>?
    
    /// Initialize remote transport
    /// - Parameters:
    ///   - serverURL: URL of the remote MCP server
    ///   - authProvider: Authentication provider (optional)
    ///   - connectionTimeout: Connection timeout in seconds (default: 30)
    ///   - requestTimeout: Individual request timeout in seconds (default: 60)
    ///   - maxRetries: Maximum number of retry attempts (default: 3)
    ///   - urlSession: Custom URLSession (optional)
    public init(
        serverURL: URL,
        authProvider: (any AuthenticationProvider)? = nil,
        connectionTimeout: TimeInterval = 30.0,
        requestTimeout: TimeInterval = 60.0,
        maxRetries: Int = 3,
        urlSession: URLSession? = nil
    ) {
        self.serverURL = serverURL
        self.authProvider = authProvider
        self.connectionTimeout = connectionTimeout
        self.requestTimeout = requestTimeout
        self.maxRetries = maxRetries
        self.logger = Logger(label: "RemoteTransport")
        
        // Configure URLSession with timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = connectionTimeout
        config.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "SwiftAgentKit-MCP/1.0"
        ]
        self.urlSession = urlSession ?? URLSession(configuration: config)
    }
    
    /// Establishes connection with the remote server
    public func connect() async throws {
        guard !isConnected else { 
            logger.debug("Already connected to remote MCP server")
            return 
        }
        
        logger.info("Connecting to remote MCP server at \(serverURL)")
        
        // Test connection with a health check or initial handshake
        try await testConnection()
        
        // Set up message stream for bidirectional communication
        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        let stream = AsyncThrowingStream<Data, Swift.Error> { continuation = $0 }
        self.messageStream = stream
        self.messageContinuation = continuation
        
        // Start background task for handling server-initiated messages (if applicable)
        self.backgroundTask = Task {
            await handleBackgroundCommunication()
        }
        
        isConnected = true
        logger.info("Successfully connected to remote MCP server")
    }
    
    /// Disconnects from the remote server
    public func disconnect() async {
        guard isConnected else { 
            logger.debug("Already disconnected from remote MCP server")
            return 
        }
        
        logger.info("Disconnecting from remote MCP server")
        
        isConnected = false
        messageContinuation?.finish()
        backgroundTask?.cancel()
        backgroundTask = nil
        
        // Clean up authentication if needed
        await authProvider?.cleanup()
        
        logger.info("Disconnected from remote MCP server")
    }
    
    /// Sends data to the remote server
    public func send(_ data: Data) async throws {
        guard isConnected else {
            throw RemoteTransportError.notConnected
        }
        
        logger.debug("Sending \(data.count) bytes to remote MCP server")
        
        // Create HTTP request
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.httpBody = data
        
        // Add authentication headers if available
        if let authProvider = authProvider {
            do {
                let authHeaders = try await authProvider.authenticationHeaders()
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }
                logger.debug("Added authentication headers")
            } catch {
                logger.error("Failed to get authentication headers: \(error)")
                throw RemoteTransportError.authenticationFailed(error.localizedDescription)
            }
        }
        
        // Send request with retry logic for authentication
        let response = try await sendRequestWithAuthRetry(request)
        
        // Handle response - for MCP, we expect JSON-RPC responses
        if let responseData = response.data, !responseData.isEmpty {
            logger.debug("Received \(responseData.count) bytes response")
            
            // Validate that it's a proper JSON-RPC response
            if isValidJSONRPCMessage(responseData) {
                messageContinuation?.yield(responseData)
            } else {
                logger.warning("Received non-JSON-RPC response from server")
                // Still yield it in case it's a valid response in a different format
                messageContinuation?.yield(responseData)
            }
        }
    }
    
    /// Receives data from the remote server
    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        guard let messageStream = messageStream else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: RemoteTransportError.notConnected)
            }
        }
        return messageStream
    }
    
    // MARK: - Private Methods
    
    private func testConnection() async throws {
        logger.debug("Testing connection to remote MCP server")
        
        // Create a lightweight test request - could be OPTIONS or a simple JSON-RPC ping
        var request = URLRequest(url: serverURL)
        request.httpMethod = "OPTIONS"
        
        // Add authentication headers if available
        if let authProvider = authProvider {
            let authHeaders = try await authProvider.authenticationHeaders()
            for (key, value) in authHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        do {
            let (_, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RemoteTransportError.invalidResponse("Non-HTTP response received")
            }
            
            // Accept various success codes for OPTIONS (2xx range) or even 405 (Method Not Allowed)
            // since some MCP servers might not support OPTIONS
            guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 405 else {
                throw RemoteTransportError.serverError(httpResponse.statusCode, "Connection test failed")
            }
            
            logger.debug("Connection test successful (status: \(httpResponse.statusCode))")
        } catch {
            logger.error("Connection test failed: \(error)")
            if let transportError = error as? RemoteTransportError {
                throw transportError
            } else {
                throw RemoteTransportError.networkError(error)
            }
        }
    }
    
    private func sendRequestWithAuthRetry(_ request: URLRequest) async throws -> (data: Data?, response: URLResponse) {
        var currentRequest = request
        var retryCount = 0
        
        while retryCount <= maxRetries {
            do {
                let (data, response) = try await urlSession.data(for: currentRequest)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw RemoteTransportError.invalidResponse("Non-HTTP response received")
                }
                
                // Check for authentication challenges
                if httpResponse.statusCode == 401 && retryCount < maxRetries {
                    logger.info("Received authentication challenge (401), attempting to refresh credentials (attempt \(retryCount + 1)/\(maxRetries))")
                    
                    if let authProvider = authProvider {
                        let challenge = AuthenticationChallenge(
                            statusCode: httpResponse.statusCode,
                            headers: httpResponse.allHeaderFields as? [String: String] ?? [:],
                            body: data,
                            serverInfo: serverURL.absoluteString
                        )
                        
                        do {
                            let newAuthHeaders = try await authProvider.handleAuthenticationChallenge(challenge)
                            
                            // Update request with new auth headers
                            for (key, value) in newAuthHeaders {
                                currentRequest.setValue(value, forHTTPHeaderField: key)
                            }
                            
                            retryCount += 1
                            logger.debug("Updated authentication headers, retrying request")
                            continue // Retry with new credentials
                        } catch {
                            logger.error("Failed to handle authentication challenge: \(error)")
                            
                            // For OAuth Discovery providers, check if this is a discovery-related error
                            if error.localizedDescription.contains("OAuth authorization flow requires manual intervention") {
                                logger.error("OAuth discovery requires manual intervention - this is expected for first-time authentication")
                                throw RemoteTransportError.authenticationFailed("OAuth discovery requires manual user intervention to complete authorization flow")
                            }
                            
                            throw RemoteTransportError.authenticationFailed("Authentication refresh failed: \(error.localizedDescription)")
                        }
                    } else {
                        // No authentication provider available - this might be a discovery opportunity
                        logger.warning("No authentication provider available for 401 challenge - this might indicate the need for OAuth discovery")
                        
                        // Check if the response contains WWW-Authenticate header with OAuth challenge
                        if let wwwAuthenticate = httpResponse.allHeaderFields["WWW-Authenticate"] as? String,
                           wwwAuthenticate.lowercased().contains("bearer") || wwwAuthenticate.lowercased().contains("oauth") {
                            logger.info("Detected OAuth challenge in WWW-Authenticate header: \(wwwAuthenticate)")
                            throw RemoteTransportError.authenticationFailed("OAuth authentication required but no OAuth provider configured. Consider using OAuthDiscoveryAuthProvider.")
                        }
                        
                        throw RemoteTransportError.authenticationFailed("No authentication provider available for 401 challenge")
                    }
                }
                
                // Check for other client error status codes (4xx)
                if (400...499).contains(httpResponse.statusCode) && httpResponse.statusCode != 401 {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown client error"
                    throw RemoteTransportError.serverError(httpResponse.statusCode, errorMessage)
                }
                
                // Check for server error status codes (5xx) - these might be retryable
                if (500...599).contains(httpResponse.statusCode) {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
                    
                    if retryCount < maxRetries {
                        logger.warning("Server error \(httpResponse.statusCode), retrying (\(retryCount + 1)/\(maxRetries)): \(errorMessage)")
                        retryCount += 1
                        
                        // Exponential backoff for server errors
                        let backoffDelay = pow(2.0, Double(retryCount)) * 0.5 // 0.5s, 1s, 2s, 4s...
                        try await Task.sleep(for: .seconds(backoffDelay))
                        continue
                    } else {
                        throw RemoteTransportError.serverError(httpResponse.statusCode, errorMessage)
                    }
                }
                
                // Success case (2xx) or 3xx redirects (URLSession handles these automatically)
                if !(200...399).contains(httpResponse.statusCode) {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unexpected status code"
                    throw RemoteTransportError.serverError(httpResponse.statusCode, errorMessage)
                }
                
                return (data, response)
                
            } catch let error as RemoteTransportError {
                throw error
            } catch {
                if retryCount < maxRetries {
                    retryCount += 1
                    logger.warning("Request failed, retrying (\(retryCount)/\(maxRetries)): \(error)")
                    
                    // Brief delay before retry for network errors
                    try await Task.sleep(for: .seconds(1.0))
                    continue
                } else {
                    throw RemoteTransportError.networkError(error)
                }
            }
        }
        
        throw RemoteTransportError.connectionFailed("Max retries (\(maxRetries)) exceeded")
    }
    
    private func handleBackgroundCommunication() async {
        // For HTTP-based MCP, this might handle server-sent events or WebSocket upgrades
        // For now, we'll keep it simple as most MCP over HTTP is request-response
        logger.debug("Background communication handler started")
        
        while !Task.isCancelled && isConnected {
            // In a full implementation, this might:
            // 1. Handle server-sent events if the MCP server supports them
            // 2. Manage WebSocket connections for bidirectional communication
            // 3. Handle keep-alive pings
            
            // For now, just sleep and check for cancellation
            try? await Task.sleep(for: .seconds(30))
        }
        
        logger.debug("Background communication handler stopped")
    }
    
    private nonisolated func isValidJSONRPCMessage(_ data: Data) -> Bool {
        // First, check if it's valid JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        
        // Check for required JSON-RPC fields
        guard let jsonrpc = json["jsonrpc"] as? String,
              jsonrpc == "2.0" else {
            return false
        }
        
        // Check if it has either method (request) or result/error (response)
        let hasMethod = json["method"] != nil
        let hasResult = json["result"] != nil
        let hasError = json["error"] != nil
        
        // Must have either method (for requests) or result/error (for responses)
        return hasMethod || hasResult || hasError
    }
}
