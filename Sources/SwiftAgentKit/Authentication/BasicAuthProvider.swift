//
//  BasicAuthProvider.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/20/25.
//

import Foundation
import Logging

/// Authentication provider for HTTP Basic authentication
public struct BasicAuthProvider: AuthenticationProvider {
    
    public let scheme: AuthenticationScheme = .basic
    private let logger = Logger(label: "BasicAuthProvider")
    
    private let username: String
    private let password: String
    
    /// Initialize Basic authentication
    /// - Parameters:
    ///   - username: Username for authentication
    ///   - password: Password for authentication
    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
    
    public func authenticationHeaders() async throws -> [String: String] {
        let credentials = "\(username):\(password)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw AuthenticationError.authenticationFailed("Failed to encode credentials")
        }
        
        let base64Credentials = credentialsData.base64EncodedString()
        return ["Authorization": "Basic \(base64Credentials)"]
    }
    
    public func handleAuthenticationChallenge(_ challenge: AuthenticationChallenge) async throws -> [String: String] {
        logger.info("Handling Basic auth challenge with status code: \(challenge.statusCode)")
        
        guard challenge.statusCode == 401 else {
            throw AuthenticationError.authenticationFailed("Unexpected status code: \(challenge.statusCode)")
        }
        
        // For Basic auth, we just return the same credentials
        // In a real scenario, you might want to prompt for new credentials
        return try await authenticationHeaders()
    }
    
    public func isAuthenticationValid() async -> Bool {
        // Basic auth doesn't typically expire, so always return true
        // In practice, you might want to make a test request to validate
        return true
    }
    
    public func cleanup() async {
        // No cleanup needed for Basic auth
        logger.info("Basic authentication cleaned up")
    }
}
