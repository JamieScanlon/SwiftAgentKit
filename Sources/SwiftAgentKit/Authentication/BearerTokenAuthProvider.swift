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
    private let logger: Logger
    
    private var token: String
    private let tokenRefreshHandler: (() async throws -> String)?
    private var tokenExpiresAt: Date?
    
    public init(
        token: String,
        expiresAt: Date? = nil,
        refreshHandler: (() async throws -> String)? = nil,
        logger: Logger? = nil
    ) {
        self.token = token
        self.tokenExpiresAt = expiresAt
        self.tokenRefreshHandler = refreshHandler
        if let logger {
            self.logger = logger
        } else {
            self.logger = SwiftAgentKitLogging.logger(
                for: .authentication("BearerTokenAuthProvider"),
                metadata: ["refreshable": .string(refreshHandler != nil ? "true" : "false")]
            )
        }
    }
    
    public init(token: String) {
        self.init(token: token, expiresAt: nil, refreshHandler: nil, logger: nil)
    }
    
    public func authenticationHeaders() async throws -> [String: String] {
        // Check if token needs refresh
        if await needsRefresh() {
            try await refreshToken()
        }
        
        if let expiresAt = tokenExpiresAt {
            let secondsRemaining = expiresAt.timeIntervalSinceNow
            logger.debug(
                "Using bearer token",
                metadata: [
                    "expiresIn": .stringConvertible(secondsRemaining),
                    "refreshable": .string(tokenRefreshHandler != nil ? "true" : "false")
                ]
            )
        }
        
        return ["Authorization": "Bearer \(token)"]
    }
    
    public func handleAuthenticationChallenge(_ challenge: AuthenticationChallenge) async throws -> [String: String] {
        let hasRefreshHandler = tokenRefreshHandler != nil
        logger.warning(
            "Bearer authentication challenge encountered",
            metadata: [
                "status": .stringConvertible(challenge.statusCode),
                "refreshHandler": .string(hasRefreshHandler ? "present" : "missing"),
                "server": .string(challenge.serverInfo ?? "unknown")
            ]
        )
        
        guard challenge.statusCode == 401 else {
            throw AuthenticationError.authenticationFailed("Unexpected status code: \(challenge.statusCode)")
        }
        
        // Try to refresh the token if we have a refresh handler
        guard hasRefreshHandler else {
            logger.error("Bearer token challenge cannot be resolved because no refresh handler is configured")
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
        logger.debug("Bearer token authentication cleaned up")
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
        
        logger.info(
            "Refreshing bearer token",
            metadata: ["expiresAt": .stringConvertible(tokenExpiresAt ?? Date())]
        )
        
        do {
            let newToken = try await refreshHandler()
            self.token = newToken
            logger.info(
                "Successfully refreshed bearer token",
                metadata: ["refreshHandler": .string("present")]
            )
        } catch {
            logger.error(
                "Failed to refresh token",
                metadata: ["error": .string(String(describing: error))]
            )
            throw AuthenticationError.authenticationFailed("Token refresh failed: \(error.localizedDescription)")
        }
    }
}
