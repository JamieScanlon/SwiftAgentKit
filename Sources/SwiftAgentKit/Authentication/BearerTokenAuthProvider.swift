//
//  BearerTokenAuthProvider.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/20/25.
//

import Foundation
import Logging

/// Authentication provider for Bearer token authentication
public actor BearerTokenAuthProvider: AuthenticationProvider {
    
    public let scheme: AuthenticationScheme = .bearer
    private let logger = Logger(label: "BearerTokenAuthProvider")
    
    private var token: String
    private let tokenRefreshHandler: (() async throws -> String)?
    private var tokenExpiresAt: Date?
    
    /// Initialize with a static token
    /// - Parameter token: The bearer token to use
    public init(token: String) {
        self.token = token
        self.tokenRefreshHandler = nil
        self.tokenExpiresAt = nil
    }
    
    /// Initialize with a token and refresh capability
    /// - Parameters:
    ///   - token: Initial bearer token
    ///   - expiresAt: When the token expires (optional)
    ///   - refreshHandler: Closure to refresh the token when needed
    public init(
        token: String,
        expiresAt: Date? = nil,
        refreshHandler: (() async throws -> String)?
    ) {
        self.token = token
        self.tokenExpiresAt = expiresAt
        self.tokenRefreshHandler = refreshHandler
    }
    
    public func authenticationHeaders() async throws -> [String: String] {
        // Check if token needs refresh
        if await needsRefresh() {
            try await refreshToken()
        }
        
        return ["Authorization": "Bearer \(token)"]
    }
    
    public func handleAuthenticationChallenge(_ challenge: AuthenticationChallenge) async throws -> [String: String] {
        logger.info("Handling authentication challenge with status code: \(challenge.statusCode)")
        
        guard challenge.statusCode == 401 else {
            throw AuthenticationError.authenticationFailed("Unexpected status code: \(challenge.statusCode)")
        }
        
        // Try to refresh the token if we have a refresh handler
        guard tokenRefreshHandler != nil else {
            throw AuthenticationError.invalidCredentials
        }
        
        try await refreshToken()
        return ["Authorization": "Bearer \(token)"]
    }
    
    public func isAuthenticationValid() async -> Bool {
        return !(await needsRefresh())
    }
    
    public func cleanup() async {
        // For bearer tokens, we typically don't need to do cleanup
        // unless we're managing token storage or sessions
        logger.info("Bearer token authentication cleaned up")
    }
    
    // MARK: - Private Methods
    
    private func needsRefresh() async -> Bool {
        guard let expiresAt = tokenExpiresAt else {
            return false // No expiration set, assume token is valid
        }
        
        // Refresh if token expires within the next 5 minutes
        let refreshThreshold = Date().addingTimeInterval(300) // 5 minutes
        return expiresAt <= refreshThreshold
    }
    
    private func refreshToken() async throws {
        guard let refreshHandler = tokenRefreshHandler else {
            throw AuthenticationError.authenticationFailed("No token refresh handler available")
        }
        
        logger.info("Refreshing bearer token")
        
        do {
            let newToken = try await refreshHandler()
            self.token = newToken
            logger.info("Successfully refreshed bearer token")
        } catch {
            logger.error("Failed to refresh token: \(error)")
            throw AuthenticationError.authenticationFailed("Token refresh failed: \(error.localizedDescription)")
        }
    }
}
