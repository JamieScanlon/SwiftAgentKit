//
//  APIKeyAuthProvider.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/20/25.
//

import Foundation
import Logging

/// Authentication provider for API Key authentication
public struct APIKeyAuthProvider: AuthenticationProvider {
    
    public let scheme: AuthenticationScheme = .apiKey
    private let logger = Logger(label: "APIKeyAuthProvider")
    
    private let apiKey: String
    private let headerName: String
    private let prefix: String?
    
    /// Initialize API Key authentication
    /// - Parameters:
    ///   - apiKey: The API key value
    ///   - headerName: Header name to use (default: "X-API-Key")
    ///   - prefix: Optional prefix for the key value (e.g., "ApiKey ")
    public init(apiKey: String, headerName: String = "X-API-Key", prefix: String? = nil) {
        self.apiKey = apiKey
        self.headerName = headerName
        self.prefix = prefix
    }
    
    public func authenticationHeaders() async throws -> [String: String] {
        let headerValue: String
        if let prefix = prefix {
            headerValue = "\(prefix)\(apiKey)"
        } else {
            headerValue = apiKey
        }
        
        return [headerName: headerValue]
    }
    
    public func handleAuthenticationChallenge(_ challenge: AuthenticationChallenge) async throws -> [String: String] {
        // API keys typically don't refresh, so if we get a challenge, the key is likely invalid
        logger.error("API Key authentication challenge received with status: \(challenge.statusCode)")
        throw AuthenticationError.invalidCredentials
    }
    
    public func isAuthenticationValid() async -> Bool {
        // API keys don't typically expire, so always return true
        // In practice, you might want to make a test request to validate
        return true
    }
    
    public func cleanup() async {
        // No cleanup needed for API keys
        logger.info("API Key authentication cleaned up")
    }
}
