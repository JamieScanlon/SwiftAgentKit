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
    
    // Dynamic client registration state
    private var registeredClientId: String?
    private var registeredClientSecret: String?
    
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
        do {
            try await ensureValidAuthentication()
        } catch let oauthFlowError as OAuthManualFlowRequired {
            // Re-throw OAuth manual flow required errors to preserve metadata
            throw oauthFlowError
        } catch {
            // Re-throw other errors as-is
            throw error
        }
        
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
        
        // Check if dynamic client registration is needed and perform it
        try await ensureRegisteredClient()
        
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
    
    /// Ensure we have a registered client, performing dynamic client registration if needed
    private func ensureRegisteredClient() async throws {
        guard let metadata = oauthServerMetadata else {
            throw AuthenticationError.authenticationFailed("No OAuth server metadata available")
        }
        
        // If we already have a registered client ID, use it
        if let registeredClientId = registeredClientId {
            logger.info("Using existing registered client ID: \(registeredClientId)")
            return
        }
        
        // Check if the authorization server supports dynamic client registration
        guard let registrationEndpoint = metadata.registrationEndpoint else {
            logger.info("Authorization server does not support dynamic client registration, using provided client ID: \(clientId)")
            return
        }
        
        logger.info("Authorization server supports dynamic client registration at: \(registrationEndpoint)")
        
        // Perform dynamic client registration
        try await performDynamicClientRegistration(registrationEndpoint: registrationEndpoint, metadata: metadata)
    }
    
    /// Perform dynamic client registration with the authorization server
    private func performDynamicClientRegistration(registrationEndpoint: String, metadata: OAuthServerMetadata) async throws {
        guard let registrationURL = URL(string: registrationEndpoint) else {
            throw AuthenticationError.authenticationFailed("Invalid registration endpoint URL")
        }
        
        logger.info("Performing dynamic client registration")
        
        // Create registration configuration from server metadata
        let registrationConfig = DynamicClientRegistrationConfig(
            registrationEndpoint: registrationURL,
            registrationAuthMethod: metadata.registrationEndpointAuthMethodsSupported?.first
        )
        
        // Select appropriate scope based on server capabilities and configuration
        let selectedScope = selectOptimalScope(serverMetadata: metadata, configuredScope: scope)
        logger.info("Dynamic client registration selected scope: '\(selectedScope)' (configured: '\(scope ?? "nil")')")
        logger.info("Server supported scopes: \(metadata.scopesSupported ?? [])")
        
        // Create registration request optimized for MCP clients
        let registrationRequest = DynamicClientRegistration.ClientRegistrationRequest.mcpClientRequest(
            redirectUris: [redirectURI.absoluteString],
            clientName: "SwiftAgentKit MCP Client",
            scope: selectedScope
        )
        
        // Log the registration request for debugging
        logger.info("Sending registration request with metadata:")
        logger.info("  - redirectUris: \(registrationRequest.redirectUris)")
        logger.info("  - clientName: \(registrationRequest.clientName ?? "nil")")
        logger.info("  - applicationType: \(registrationRequest.applicationType ?? "nil")")
        logger.info("  - grantTypes: \(registrationRequest.grantTypes ?? [])")
        logger.info("  - responseTypes: \(registrationRequest.responseTypes ?? [])")
        logger.info("  - scope: \(registrationRequest.scope ?? "nil")")
        logger.info("  - tokenEndpointAuthMethod: \(registrationRequest.tokenEndpointAuthMethod ?? "nil")")
        
        // Create registration client and perform registration
        let registrationClient = DynamicClientRegistrationClient(config: registrationConfig)
        
        do {
            let response = try await registrationClient.registerClient(request: registrationRequest)
            
            logger.info("Successfully registered client with ID: \(response.clientId)")
            
            // Store the registered client credentials
            registeredClientId = response.clientId
            registeredClientSecret = response.clientSecret
            
            logger.info("Dynamic client registration completed successfully")
            logger.info("Registration Summary:")
            logger.info("  - Registered Client ID: \(response.clientId)")
            logger.info("  - Registration Scope: '\(selectedScope)'")
            logger.info("  - Server Supported Scopes: \(metadata.scopesSupported ?? [])")
            logger.info("  - This scope will be used consistently in OAuth flow")
            
        } catch let registrationError as DynamicClientRegistrationError {
            logger.error("Dynamic client registration failed with specific error: \(registrationError)")
            if case .registrationError(let errorResponse) = registrationError {
                logger.error("Registration error details: \(errorResponse.error) - \(errorResponse.errorDescription ?? "No description")")
            }
            // Fall back to using the provided client ID
            logger.info("Falling back to provided client ID: \(clientId)")
        } catch {
            logger.error("Dynamic client registration failed with unexpected error: \(error)")
            // Fall back to using the provided client ID
            logger.info("Falling back to provided client ID: \(clientId)")
        }
    }
    
    /// Select optimal scope based on server capabilities and configuration
    internal func selectOptimalScope(serverMetadata: OAuthServerMetadata, configuredScope: String?) -> String {
        let serverSupportedScopes = serverMetadata.scopesSupported ?? []
        
        // If a scope is explicitly configured, check if the server supports it
        if let configuredScope = configuredScope, !configuredScope.isEmpty {
            // Check if the configured scope is supported by the server
            if serverSupportedScopes.contains(configuredScope) {
                logger.info("Using configured scope: \(configuredScope)")
                return configuredScope
            } else {
                logger.warning("Configured scope '\(configuredScope)' not supported by server. Supported scopes: \(serverSupportedScopes)")
            }
        }
        
        // Try to find the best scope from server's supported scopes
        // First check for exact combined scopes (highest priority)
        let exactCombinedScopes = [
            "mcp",                    // Generic MCP scope
            "profile email",          // Combined scope for Zapier
            "openid profile email",   // Full OpenID Connect scope
        ]
        
        for combinedScope in exactCombinedScopes {
            if serverSupportedScopes.contains(combinedScope) {
                logger.info("Selected exact server-supported scope: \(combinedScope)")
                return combinedScope
            }
        }
        
        // Check for scope combinations we can build from individual scopes
        let builtCombinedScope = buildOptimalScope(from: serverSupportedScopes)
        if !builtCombinedScope.isEmpty {
            logger.info("Built combined scope from individual scopes: \(builtCombinedScope)")
            return builtCombinedScope
        }
        
        // Fall back to individual scopes in preference order
        let individualScopes = ["openid", "profile", "email"]
        
        for individualScope in individualScopes {
            if serverSupportedScopes.contains(individualScope) {
                logger.info("Selected individual server-supported scope: \(individualScope)")
                return individualScope
            }
        }
        
        // If no preferred scope is found, use the first available scope
        if let firstScope = serverSupportedScopes.first {
            logger.info("Using first available server scope: \(firstScope)")
            return firstScope
        }
        
        // Fallback to default scope if server doesn't specify supported scopes
        logger.info("No server-supported scopes found, using default: mcp")
        return "mcp"
    }
    
    /// Build optimal scope by combining individual scopes when possible
    private func buildOptimalScope(from serverSupportedScopes: [String]) -> String {
        // Check for common scope combinations we can build from individual scopes
        // Order by priority: most comprehensive first
        
        // Check if we can build "openid profile email" from individual scopes (highest priority)
        if serverSupportedScopes.contains("openid") && 
           serverSupportedScopes.contains("profile") && 
           serverSupportedScopes.contains("email") {
            return "openid profile email"
        }
        
        // Check if we can build "profile email" from individual scopes
        if serverSupportedScopes.contains("profile") && serverSupportedScopes.contains("email") {
            return "profile email"
        }
        
        // Check if we can build "openid profile" from individual scopes
        if serverSupportedScopes.contains("openid") && serverSupportedScopes.contains("profile") {
            return "openid profile"
        }
        
        // Check if we can build "openid email" from individual scopes
        if serverSupportedScopes.contains("openid") && serverSupportedScopes.contains("email") {
            return "openid email"
        }
        
        return ""
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
        
        // Use registered client ID if available, otherwise fall back to provided client ID
        let effectiveClientId = registeredClientId ?? clientId
        let clientIdSource = registeredClientId != nil ? "registered" : "provided"
        logger.info("OAuth flow using \(clientIdSource) client ID: \(effectiveClientId)")
        
        // Select optimal scope for OAuth flow (same logic as registration)
        let effectiveScope = selectOptimalScope(serverMetadata: metadata, configuredScope: scope)
        logger.info("OAuth flow selected scope: '\(effectiveScope)' (configured: '\(scope ?? "nil")')")
        
        // Build authorization URL with PKCE parameters
        var authURLComponents = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: effectiveClientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        
        if !effectiveScope.isEmpty {
            queryItems.append(URLQueryItem(name: "scope", value: effectiveScope))
            logger.info("Added scope parameter to authorization URL: '\(effectiveScope)'")
        } else {
            logger.warning("No scope selected for OAuth flow - this may cause issues with some servers")
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
        logger.info("Authorization URL breakdown:")
        logger.info("  - Client ID: \(effectiveClientId)")
        logger.info("  - Scope: '\(effectiveScope)'")
        logger.info("  - Redirect URI: \(redirectURI.absoluteString)")
        logger.info("  - Code Challenge: \(codeChallenge)")
        logger.info("  - Resource: \(resourceURI ?? "none")")
        
        // For a real implementation, this would:
        // 1. Open the authorization URL in a browser
        // 2. Wait for the user to complete authorization
        // 3. Capture the authorization code from the redirect
        // 4. Exchange the code for tokens
        
        // Throw the new OAuth manual flow required error with all necessary metadata
        let additionalMetadata = [
            "authorization_endpoint": authorizationEndpoint,
            "token_endpoint": tokenEndpoint,
            "code_challenge": codeChallenge,
            "code_challenge_method": "S256",
            "response_type": "code"
        ]
        
        throw OAuthManualFlowRequired(
            authorizationURL: finalAuthURL,
            redirectURI: redirectURI,
            clientId: effectiveClientId,
            scope: effectiveScope,
            resourceURI: resourceURI,
            additionalMetadata: additionalMetadata
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
        
        // Use registered client ID if available, otherwise fall back to provided client ID
        let effectiveClientId = registeredClientId ?? clientId
        let effectiveClientSecret = registeredClientSecret ?? clientSecret
        let clientIdSource = registeredClientId != nil ? "registered" : "provided"
        logger.info("Token exchange using \(clientIdSource) client ID: \(effectiveClientId)")
        
        // Ensure we use the same scope that was registered
        let effectiveScope = selectOptimalScope(serverMetadata: metadata, configuredScope: scope)
        logger.info("Token exchange using scope: '\(effectiveScope)' (same as registration)")
        
        // Critical verification: Ensure scope consistency
        if let registeredClientId = registeredClientId {
            logger.info("🔍 SCOPE CONSISTENCY CHECK:")
            logger.info("  - Using registered client ID: \(registeredClientId)")
            logger.info("  - Token exchange scope: '\(effectiveScope)'")
            logger.info("  - This scope MUST match the registration scope exactly")
        }
        
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: authorizationCode),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "client_id", value: effectiveClientId),
            URLQueryItem(name: "code_verifier", value: codeVerifier)
        ]
        
        // Add scope parameter to match the authorization request
        // Note: Some OAuth servers require the scope parameter, others don't
        // We include it to ensure consistency with the authorization request
        if !effectiveScope.isEmpty {
            bodyComponents.queryItems?.append(URLQueryItem(name: "scope", value: effectiveScope))
            logger.info("Added scope parameter to token exchange request: '\(effectiveScope)'")
            logger.info("⚠️  If token exchange fails with 'invalid_scope', try removing scope parameter from token exchange")
        }
        
        // Add resource parameter as required by RFC 8707 for MCP clients
        if let resourceURI = resourceURI {
            bodyComponents.queryItems?.append(URLQueryItem(name: "resource", value: resourceURI))
            logger.info("Added resource parameter to token request: \(resourceURI)")
        }
        
        if let clientSecret = effectiveClientSecret {
            bodyComponents.queryItems?.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }
        
        request.httpBody = bodyComponents.query?.data(using: .utf8)
        
        // Log the complete token exchange request for debugging
        if let requestBody = String(data: request.httpBody ?? Data(), encoding: .utf8) {
            logger.info("Token exchange request body: \(requestBody)")
        }
        logger.info("Token exchange request URL: \(tokenURL)")
        logger.info("Token exchange request headers: \(request.allHTTPHeaderFields ?? [:])")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthenticationError.authenticationFailed("Invalid response type")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error("Token exchange failed with status \(httpResponse.statusCode): \(errorMessage)")
                logger.error("Token exchange request that failed: \(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "unknown")")
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
        
        // Use registered client ID if available, otherwise fall back to provided client ID
        let effectiveClientId = registeredClientId ?? clientId
        let effectiveClientSecret = registeredClientSecret ?? clientSecret
        let clientIdSource = registeredClientId != nil ? "registered" : "provided"
        logger.info("Token refresh using \(clientIdSource) client ID: \(effectiveClientId)")
        
        // Ensure we use the same scope that was registered
        let effectiveScope = selectOptimalScope(serverMetadata: metadata, configuredScope: scope)
        logger.info("Token refresh using scope: '\(effectiveScope)' (same as registration)")
        
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: effectiveClientId)
        ]
        
        // Add scope parameter to match the original authorization request
        if !effectiveScope.isEmpty {
            bodyComponents.queryItems?.append(URLQueryItem(name: "scope", value: effectiveScope))
            logger.info("Added scope parameter to token refresh request: '\(effectiveScope)'")
        }
        
        // Add resource parameter as required by RFC 8707 for MCP clients
        if let resourceURI = resourceURI {
            bodyComponents.queryItems?.append(URLQueryItem(name: "resource", value: resourceURI))
            logger.info("Added resource parameter to token refresh request: \(resourceURI)")
        }
        
        if let clientSecret = effectiveClientSecret {
            bodyComponents.queryItems?.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }
        
        request.httpBody = bodyComponents.query?.data(using: .utf8)
        
        // Log the complete token refresh request for debugging
        if let requestBody = String(data: request.httpBody ?? Data(), encoding: .utf8) {
            logger.info("Token refresh request body: \(requestBody)")
        }
        logger.info("Token refresh request URL: \(tokenURL)")
        logger.info("Token refresh request headers: \(request.allHTTPHeaderFields ?? [:])")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthenticationError.authenticationFailed("Invalid response type")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error("Token refresh failed with status \(httpResponse.statusCode): \(errorMessage)")
                logger.error("Token refresh request that failed: \(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "unknown")")
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
