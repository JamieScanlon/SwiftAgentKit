//
//  OAuthAuthProvider.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/20/25.
//

import Foundation
import Logging

/// OAuth token information
public struct OAuthTokens: Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let tokenType: String
    public let expiresIn: TimeInterval?
    public let scope: String?
    
    /// When the access token expires (calculated from expiresIn)
    public let expiresAt: Date?
    
    public init(
        accessToken: String,
        refreshToken: String? = nil,
        tokenType: String = "Bearer",
        expiresIn: TimeInterval? = nil,
        scope: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.scope = scope
        
        // Calculate expiration time if provided
        if let expiresIn = expiresIn {
            self.expiresAt = Date().addingTimeInterval(expiresIn)
        } else {
            self.expiresAt = nil
        }
    }
}

/// OAuth configuration for token refresh
public struct OAuthConfig: Sendable {
    public let tokenEndpoint: URL
    public let clientId: String
    public let clientSecret: String?
    public let scope: String?
    /// Resource URI for RFC 8707 Resource Indicators (required for MCP clients)
    public let resourceURI: String?
    
    public init(
        tokenEndpoint: URL,
        clientId: String,
        clientSecret: String? = nil,
        scope: String? = nil,
        resourceURI: String? = nil
    ) throws {
        self.tokenEndpoint = tokenEndpoint
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.scope = scope
        
        // Validate and canonicalize resource URI if provided
        if let resourceURI = resourceURI {
            self.resourceURI = try ResourceIndicatorUtilities.canonicalizeResourceURI(resourceURI)
        } else {
            self.resourceURI = nil
        }
    }
}

/// Authentication provider for OAuth 2.0 authentication
public actor OAuthAuthProvider: AuthenticationProvider {
    
    public let scheme: AuthenticationScheme = .oauth
    private let logger: Logger
    
    private var tokens: OAuthTokens
    private let config: OAuthConfig
    private let urlSession: URLSession
    
    /// Initialize with OAuth tokens and configuration
    /// - Parameters:
    ///   - tokens: Initial OAuth tokens (access token, refresh token, etc.)
    ///   - config: OAuth configuration for token refresh
    ///   - urlSession: Custom URLSession (optional)
    public init(
        tokens: OAuthTokens,
        config: OAuthConfig,
        urlSession: URLSession,
        logger: Logger?
    ) {
        self.tokens = tokens
        self.config = config
        self.urlSession = urlSession
        let metadata: Logger.Metadata = [
            "tokenEndpoint": .string(config.tokenEndpoint.absoluteString),
            "clientId": .string(config.clientId)
        ]
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .authentication("OAuthAuthProvider"),
            metadata: metadata
        )
    }
    
    public init(
        tokens: OAuthTokens,
        config: OAuthConfig,
        urlSession: URLSession = .shared
    ) {
        self.init(tokens: tokens, config: config, urlSession: urlSession, logger: nil)
    }
    
    public func authenticationHeaders() async throws -> [String: String] {
        // Check if token needs refresh
        if await needsRefresh() {
            try await refreshAccessToken()
        }
        
        if let expiresAt = tokens.expiresAt {
            logger.debug(
                "Using OAuth access token",
                metadata: SwiftAgentKitLogging.metadata(
                    ("expiresIn", .stringConvertible(expiresAt.timeIntervalSinceNow)),
                    ("hasRefreshToken", .string(tokens.refreshToken != nil ? "true" : "false"))
                )
            )
        }
        
        return ["Authorization": "\(tokens.tokenType) \(tokens.accessToken)"]
    }
    
    public func handleAuthenticationChallenge(_ challenge: AuthenticationChallenge) async throws -> [String: String] {
        let hasRefreshToken = tokens.refreshToken != nil
        logger.warning(
            "OAuth authentication challenge encountered",
            metadata: SwiftAgentKitLogging.metadata(
                ("status", .stringConvertible(challenge.statusCode)),
                ("refreshToken", .string(hasRefreshToken ? "present" : "missing")),
                ("server", .string(challenge.serverInfo ?? "unknown"))
            )
        )
        
        guard challenge.statusCode == 401 else {
            throw AuthenticationError.authenticationFailed("Unexpected status code: \(challenge.statusCode)")
        }
        
        // Try to refresh the access token
        guard tokens.refreshToken != nil else {
            logger.error("No refresh token available for OAuth token refresh")
            throw AuthenticationError.authenticationExpired
        }
        
        try await refreshAccessToken()
        return ["Authorization": "\(tokens.tokenType) \(tokens.accessToken)"]
    }
    
    public func isAuthenticationValid() async -> Bool {
        return !(await needsRefresh())
    }
    
    public func cleanup() async {
        // In a production app, you might want to revoke the tokens
        logger.debug("OAuth authentication cleaned up")
    }
    
    /// Get current access token (useful for debugging or logging)
    public func getCurrentAccessToken() async -> String {
        return tokens.accessToken
    }
    
    /// Get current tokens (useful for persisting to storage)
    public func getCurrentTokens() async -> OAuthTokens {
        return tokens
    }
    
    /// Update tokens (useful when tokens are refreshed externally)
    public func updateTokens(_ newTokens: OAuthTokens) async {
        self.tokens = newTokens
        logger.debug("OAuth tokens updated")
    }
    
    // MARK: - Private Methods
    
    private func needsRefresh() async -> Bool {
        guard let expiresAt = tokens.expiresAt else {
            return false // No expiration set, assume token is valid
        }
        
        // Refresh if token expires within the next 5 minutes
        let refreshThreshold = Date().addingTimeInterval(300) // 5 minutes
        return expiresAt <= refreshThreshold
    }
    
    private func refreshAccessToken() async throws {
        guard let refreshToken = tokens.refreshToken else {
            throw AuthenticationError.authenticationExpired
        }
        
        logger.info(
            "Refreshing OAuth access token",
            metadata: SwiftAgentKitLogging.metadata(
                ("tokenEndpoint", .string(config.tokenEndpoint.absoluteString)),
                ("clientId", .string(config.clientId))
            )
        )
        
        // Prepare refresh token request
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Build request body
        var bodyComponents = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)"
        ]
        
        if let scope = config.scope {
            bodyComponents.append("scope=\(scope)")
        }
        
        // Add resource parameter as required by RFC 8707 for MCP clients
        if let resourceURI = config.resourceURI {
            bodyComponents.append("resource=\(ResourceIndicatorUtilities.createResourceParameter(canonicalURI: resourceURI))")
            logger.debug(
                "Added resource parameter to token refresh request",
                metadata: SwiftAgentKitLogging.metadata(("resourceURI", .string(resourceURI)))
            )
        }
        
        // Add client authentication
        if let clientSecret = config.clientSecret {
            // Use client credentials in body (alternative: HTTP Basic auth)
            bodyComponents.append("client_id=\(config.clientId)")
            bodyComponents.append("client_secret=\(clientSecret)")
        } else {
            // Public client (PKCE flow)
            bodyComponents.append("client_id=\(config.clientId)")
        }
        
        let bodyString = bodyComponents.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthenticationError.networkError("Invalid response type")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error(
                    "OAuth token refresh failed",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("status", .stringConvertible(httpResponse.statusCode)),
                        ("payload", .string(errorMessage))
                    )
                )
                throw AuthenticationError.authenticationFailed("Token refresh failed: \(errorMessage)")
            }
            
            // Parse token response
            let newTokens = try parseTokenResponse(data)
            self.tokens = newTokens
            
            logger.info(
                "Successfully refreshed OAuth access token",
                metadata: SwiftAgentKitLogging.metadata(
                    ("expiresIn", .stringConvertible(newTokens.expiresAt?.timeIntervalSinceNow ?? 0)),
                    ("scope", .string(newTokens.scope ?? "unspecified"))
                )
            )
            
        } catch {
            logger.error(
                "Failed to refresh OAuth token",
                metadata: SwiftAgentKitLogging.metadata(("error", .string(String(describing: error))))
            )
            if error is AuthenticationError {
                throw error
            } else {
                throw AuthenticationError.networkError(error.localizedDescription)
            }
        }
    }
    
    private func parseTokenResponse(_ data: Data) throws -> OAuthTokens {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthenticationError.authenticationFailed("Invalid JSON response from token endpoint")
        }
        
        guard let accessToken = json["access_token"] as? String else {
            throw AuthenticationError.authenticationFailed("No access_token in response")
        }
        
        let refreshToken = json["refresh_token"] as? String ?? tokens.refreshToken // Keep existing refresh token if not provided
        let tokenType = json["token_type"] as? String ?? "Bearer"
        let expiresIn = json["expires_in"] as? TimeInterval
        let scope = json["scope"] as? String
        
        return OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresIn: expiresIn,
            scope: scope
        )
    }
}
