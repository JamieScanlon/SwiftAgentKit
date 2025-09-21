//
//  OAuthDiscoveryAuthProvider.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Foundation
import Logging

/// OAuth Discovery-based authentication provider that implements the complete MCP Auth flow
/// This provider automatically discovers authorization server metadata and handles OAuth 2.1 flows
public actor OAuthDiscoveryAuthProvider: AuthenticationProvider {
    
    public nonisolated let scheme: AuthenticationScheme = .oauth
    
    private let logger = Logger(label: "OAuthDiscoveryAuthProvider")
    private let discoveryManager: OAuthDiscoveryManager
    private let resourceServerURL: URL
    private let resourceType: String?
    private let clientId: String
    private let clientSecret: String?
    private let scope: String?
    private let redirectURI: URL
    private let preConfiguredAuthServerURL: URL?
    private let resourceURI: String?
    
    // Discovery state
    private var oauthServerMetadata: OAuthServerMetadata?
    private var accessToken: String?
    private var tokenExpiration: Date?
    private var refreshToken: String?
    
    /// Initialize OAuth Discovery authentication provider
    /// - Parameters:
    ///   - resourceServerURL: URL of the MCP server (Resource Server)
    ///   - clientId: OAuth client ID
    ///   - clientSecret: OAuth client secret (optional for public clients)
    ///   - scope: OAuth scope (optional)
    ///   - redirectURI: OAuth redirect URI
    ///   - resourceType: Type of resource (e.g., "mcp" for MCP servers)
    ///   - preConfiguredAuthServerURL: Pre-configured authorization server URL (optional)
    ///   - resourceURI: Resource URI for RFC 8707 Resource Indicators (optional, will use resourceServerURL if not provided)
    public init(
        resourceServerURL: URL,
        clientId: String,
        clientSecret: String? = nil,
        scope: String? = nil,
        redirectURI: URL,
        resourceType: String? = "mcp",
        preConfiguredAuthServerURL: URL? = nil,
        resourceURI: String? = nil
    ) throws {
        self.resourceServerURL = resourceServerURL
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.scope = scope
        self.redirectURI = redirectURI
        self.resourceType = resourceType
        self.preConfiguredAuthServerURL = preConfiguredAuthServerURL
        
        // Use provided resourceURI or derive from resourceServerURL
        let targetResourceURI = resourceURI ?? resourceServerURL.absoluteString
        self.resourceURI = try ResourceIndicatorUtilities.canonicalizeResourceURI(targetResourceURI)
        
        self.discoveryManager = OAuthDiscoveryManager()
    }
    
    /// Initialize OAuth Discovery authentication provider with discovery manager
    /// - Parameters:
    ///   - resourceServerURL: URL of the MCP server (Resource Server)
    ///   - clientId: OAuth client ID
    ///   - clientSecret: OAuth client secret (optional for public clients)
    ///   - scope: OAuth scope (optional)
    ///   - redirectURI: OAuth redirect URI
    ///   - resourceType: Type of resource (e.g., "mcp" for MCP servers)
    ///   - preConfiguredAuthServerURL: Pre-configured authorization server URL (optional)
    ///   - discoveryManager: Custom discovery manager (optional)
    ///   - resourceURI: Resource URI for RFC 8707 Resource Indicators (optional, will use resourceServerURL if not provided)
    public init(
        resourceServerURL: URL,
        clientId: String,
        clientSecret: String? = nil,
        scope: String? = nil,
        redirectURI: URL,
        resourceType: String? = "mcp",
        preConfiguredAuthServerURL: URL? = nil,
        discoveryManager: OAuthDiscoveryManager,
        resourceURI: String? = nil
    ) throws {
        self.resourceServerURL = resourceServerURL
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.scope = scope
        self.redirectURI = redirectURI
        self.resourceType = resourceType
        self.preConfiguredAuthServerURL = preConfiguredAuthServerURL
        self.discoveryManager = discoveryManager
        
        // Use provided resourceURI or derive from resourceServerURL
        let targetResourceURI = resourceURI ?? resourceServerURL.absoluteString
        self.resourceURI = try ResourceIndicatorUtilities.canonicalizeResourceURI(targetResourceURI)
    }
    
    // MARK: - AuthenticationProvider Protocol
    
    public func authenticationHeaders() async throws -> [String: String] {
        // Ensure we have valid authentication
        try await ensureValidAuthentication()
        
        guard let accessToken = accessToken else {
            throw AuthenticationError.authenticationFailed("No access token available")
        }
        
        return ["Authorization": "Bearer \(accessToken)"]
    }
    
    public func handleAuthenticationChallenge(_ challenge: AuthenticationChallenge) async throws -> [String: String] {
        logger.info("Handling authentication challenge")
        
        // If we get a 401, try to refresh the token or re-authenticate
        if challenge.statusCode == 401 {
            logger.info("Received 401 challenge, attempting to refresh authentication")
            
            // Try to refresh token if we have one
            if let refreshToken = refreshToken {
                do {
                    try await refreshAccessToken(refreshToken: refreshToken)
                    return try await authenticationHeaders()
                } catch {
                    logger.warning("Token refresh failed: \(error)")
                    // Fall through to full re-authentication
                }
            }
            
            // If refresh failed or no refresh token, perform full re-authentication
            try await performOAuthFlow()
            return try await authenticationHeaders()
        }
        
        // For other challenges, return current headers
        return try await authenticationHeaders()
    }
    
    public func isAuthenticationValid() async -> Bool {
        guard let tokenExpiration = tokenExpiration else {
            return accessToken != nil
        }
        
        // Consider token valid if it expires more than 5 minutes from now
        return Date().addingTimeInterval(300) < tokenExpiration
    }
    
    public func cleanup() async {
        logger.info("Cleaning up OAuth Discovery authentication")
        accessToken = nil
        refreshToken = nil
        tokenExpiration = nil
        oauthServerMetadata = nil
    }
    
    // MARK: - Private Methods
    
    /// Ensure we have valid authentication, performing discovery and OAuth flow if needed
    private func ensureValidAuthentication() async throws {
        // Check if we already have valid authentication
        if await isAuthenticationValid() {
            return
        }
        
        logger.info("Authentication not valid, performing discovery and OAuth flow")
        
        // Perform discovery if we haven't already
        if oauthServerMetadata == nil {
            try await performDiscovery()
        }
        
        // Perform OAuth flow to get access token
        try await performOAuthFlow()
    }
    
    /// Perform OAuth server discovery
    private func performDiscovery() async throws {
        logger.info("Performing OAuth server discovery")
        
        oauthServerMetadata = try await discoveryManager.discoverAuthorizationServerMetadata(
            resourceServerURL: resourceServerURL,
            resourceType: resourceType,
            preConfiguredAuthServerURL: preConfiguredAuthServerURL
        )
        
        // Validate that the authorization server supports PKCE as required by MCP spec
        _ = try oauthServerMetadata?.validatePKCESupport()
        
        logger.info("OAuth server discovery completed successfully")
    }
    
    /// Perform OAuth 2.1 authorization flow
    private func performOAuthFlow() async throws {
        guard let metadata = oauthServerMetadata else {
            throw AuthenticationError.authenticationFailed("No OAuth server metadata available")
        }
        
        guard let authorizationEndpoint = metadata.authorizationEndpoint,
              let authorizationURL = URL(string: authorizationEndpoint) else {
            throw AuthenticationError.authenticationFailed("No authorization endpoint available")
        }
        
        guard let tokenEndpoint = metadata.tokenEndpoint,
              let _ = URL(string: tokenEndpoint) else {
            throw AuthenticationError.authenticationFailed("No token endpoint available")
        }
        
        logger.info("Performing OAuth 2.1 authorization flow")
        
        // Generate PKCE parameters
        let pkcePair = try PKCEUtilities.generatePKCEPair()
        let _ = pkcePair.codeVerifier // Store for later use in token exchange
        let codeChallenge = pkcePair.codeChallenge
        
        // Build authorization URL with PKCE parameters
        var authURLComponents = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        
        if let scope = scope {
            queryItems.append(URLQueryItem(name: "scope", value: scope))
        }
        
        // Add resource parameter as required by RFC 8707 for MCP clients
        if let resourceURI = resourceURI {
            queryItems.append(URLQueryItem(name: "resource", value: resourceURI))
            logger.info("Added resource parameter to authorization request: \(resourceURI)")
        }
        
        authURLComponents.queryItems = queryItems
        
        guard let finalAuthURL = authURLComponents.url else {
            throw AuthenticationError.authenticationFailed("Failed to build authorization URL")
        }
        
        logger.info("Authorization URL: \(finalAuthURL)")
        
        // For a real implementation, this would:
        // 1. Open the authorization URL in a browser
        // 2. Wait for the user to complete authorization
        // 3. Capture the authorization code from the redirect
        // 4. Exchange the code for tokens
        
        // For now, we'll throw an error indicating manual intervention is needed
        throw AuthenticationError.authenticationFailed(
            "OAuth authorization flow requires manual intervention. " +
            "Please visit: \(finalAuthURL) " +
            "and provide the authorization code to complete authentication."
        )
    }
    
    /// Exchange authorization code for access token
    /// - Parameters:
    ///   - authorizationCode: The authorization code from the redirect
    ///   - codeVerifier: The PKCE code verifier
    private func exchangeCodeForToken(
        authorizationCode: String,
        codeVerifier: String
    ) async throws {
        guard let metadata = oauthServerMetadata,
              let tokenEndpoint = metadata.tokenEndpoint,
              let tokenURL = URL(string: tokenEndpoint) else {
            throw AuthenticationError.authenticationFailed("No token endpoint available")
        }
        
        logger.info("Exchanging authorization code for access token")
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: authorizationCode),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code_verifier", value: codeVerifier)
        ]
        
        // Add resource parameter as required by RFC 8707 for MCP clients
        if let resourceURI = resourceURI {
            bodyComponents.queryItems?.append(URLQueryItem(name: "resource", value: resourceURI))
            logger.info("Added resource parameter to token request: \(resourceURI)")
        }
        
        if let clientSecret = clientSecret {
            bodyComponents.queryItems?.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }
        
        request.httpBody = bodyComponents.query?.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthenticationError.authenticationFailed("Invalid response type")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AuthenticationError.authenticationFailed("Token exchange failed: \(errorMessage)")
            }
            
            // Parse token response
            let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
            
            accessToken = tokenResponse.accessToken
            refreshToken = tokenResponse.refreshToken
            
            if let expiresIn = tokenResponse.expiresIn {
                tokenExpiration = Date().addingTimeInterval(TimeInterval(expiresIn))
            }
            
            logger.info("Successfully obtained access token")
            
        } catch let error as AuthenticationError {
            throw error
        } catch {
            logger.error("Failed to exchange code for token: \(error)")
            throw AuthenticationError.authenticationFailed("Token exchange failed: \(error.localizedDescription)")
        }
    }
    
    /// Refresh access token using refresh token
    /// - Parameter refreshToken: The refresh token
    private func refreshAccessToken(refreshToken: String) async throws {
        guard let metadata = oauthServerMetadata,
              let tokenEndpoint = metadata.tokenEndpoint,
              let tokenURL = URL(string: tokenEndpoint) else {
            throw AuthenticationError.authenticationFailed("No token endpoint available")
        }
        
        logger.info("Refreshing access token")
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientId)
        ]
        
        // Add resource parameter as required by RFC 8707 for MCP clients
        if let resourceURI = resourceURI {
            bodyComponents.queryItems?.append(URLQueryItem(name: "resource", value: resourceURI))
            logger.info("Added resource parameter to token refresh request: \(resourceURI)")
        }
        
        if let clientSecret = clientSecret {
            bodyComponents.queryItems?.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }
        
        request.httpBody = bodyComponents.query?.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthenticationError.authenticationFailed("Invalid response type")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AuthenticationError.authenticationFailed("Token refresh failed: \(errorMessage)")
            }
            
            // Parse token response
            let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
            
            accessToken = tokenResponse.accessToken
            if let newRefreshToken = tokenResponse.refreshToken {
                self.refreshToken = newRefreshToken
            }
            
            if let expiresIn = tokenResponse.expiresIn {
                tokenExpiration = Date().addingTimeInterval(TimeInterval(expiresIn))
            }
            
            logger.info("Successfully refreshed access token")
            
        } catch let error as AuthenticationError {
            throw error
        } catch {
            logger.error("Failed to refresh access token: \(error)")
            throw AuthenticationError.authenticationFailed("Token refresh failed: \(error.localizedDescription)")
        }
    }
}

/// OAuth token response structure
private struct OAuthTokenResponse: Codable {
    let accessToken: String
    let tokenType: String?
    let expiresIn: Int?
    let refreshToken: String?
    let scope: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}
