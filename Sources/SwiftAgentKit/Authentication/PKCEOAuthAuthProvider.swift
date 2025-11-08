//
//  PKCEOAuthAuthProvider.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Foundation
import Logging
import CryptoKit

/// PKCE-enabled OAuth configuration for authorization code flow
public struct PKCEOAuthConfig: Sendable {
    /// The authorization server's issuer URL
    public let issuerURL: URL
    
    /// OAuth client ID
    public let clientId: String
    
    /// OAuth client secret (optional for public clients)
    public let clientSecret: String?
    
    /// OAuth scopes to request
    public let scope: String?
    
    /// Redirect URI for the authorization flow
    public let redirectURI: URL
    
    /// Custom authorization endpoint URL (optional, will use discovery if not provided)
    public let authorizationEndpoint: URL?
    
    /// Custom token endpoint URL (optional, will use discovery if not provided)
    public let tokenEndpoint: URL?
    
    /// PKCE pair (code verifier and challenge)
    public let pkcePair: PKCEUtilities.PKCEPair
    
    /// Whether to use OpenID Connect Discovery (default: true)
    public let useOpenIDConnectDiscovery: Bool
    
    /// Resource URI for RFC 8707 Resource Indicators (required for MCP clients)
    public let resourceURI: String?
    
    public init(
        issuerURL: URL,
        clientId: String,
        clientSecret: String? = nil,
        scope: String? = nil,
        redirectURI: URL,
        authorizationEndpoint: URL? = nil,
        tokenEndpoint: URL? = nil,
        pkcePair: PKCEUtilities.PKCEPair? = nil,
        useOpenIDConnectDiscovery: Bool = true,
        resourceURI: String? = nil
    ) throws {
        self.issuerURL = issuerURL
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.scope = scope
        self.redirectURI = redirectURI
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.useOpenIDConnectDiscovery = useOpenIDConnectDiscovery
        
        // Validate and canonicalize resource URI if provided
        if let resourceURI = resourceURI {
            self.resourceURI = try ResourceIndicatorUtilities.canonicalizeResourceURI(resourceURI)
        } else {
            self.resourceURI = nil
        }
        
        // Generate PKCE pair if not provided
        self.pkcePair = try pkcePair ?? PKCEUtilities.generatePKCEPair()
    }
}

/// PKCE-enabled OAuth authentication provider for MCP clients
/// Implements OAuth 2.1 authorization code flow with PKCE as required by MCP specification
public actor PKCEOAuthAuthProvider: AuthenticationProvider {
    
    public let scheme: AuthenticationScheme = .oauth
    private let logger: Logger
    
    private let config: PKCEOAuthConfig
    private let urlSession: URLSession
    private let metadataClient: OAuthServerMetadataClient
    
    private var tokens: OAuthTokens? = nil
    private var serverMetadata: OAuthServerMetadata? = nil
    
    /// Initialize with PKCE OAuth configuration
    /// - Parameters:
    ///   - config: PKCE OAuth configuration
    ///   - urlSession: Custom URLSession (optional)
    ///   - metadataClient: Custom metadata discovery client (optional)
    public init(
        config: PKCEOAuthConfig,
        urlSession: URLSession,
        metadataClient: OAuthServerMetadataClient?,
        logger: Logger?
    ) {
        self.config = config
        self.urlSession = urlSession
        let providerLogger = logger ?? SwiftAgentKitLogging.logger(
            for: .authentication("PKCEOAuthAuthProvider"),
            metadata: [
                "issuerURL": .string(config.issuerURL.absoluteString),
                "clientId": .string(config.clientId)
            ]
        )
        self.logger = providerLogger
        if let metadataClient {
            self.metadataClient = metadataClient
        } else {
            self.metadataClient = OAuthServerMetadataClient(
                urlSession: urlSession,
                logger: SwiftAgentKitLogging.logger(
                    for: .authentication("OAuthServerMetadataClient"),
                    metadata: ["issuerURL": .string(config.issuerURL.absoluteString)]
                )
            )
        }
    }
    
    public init(
        config: PKCEOAuthConfig,
        urlSession: URLSession = .shared,
        metadataClient: OAuthServerMetadataClient? = nil
    ) {
        self.init(config: config, urlSession: urlSession, metadataClient: metadataClient, logger: nil)
    }
    
    public func authenticationHeaders() async throws -> [String: String] {
        // Ensure we have valid tokens
        guard let tokens = tokens, await isAuthenticationValid() else {
            throw AuthenticationError.authenticationExpired
        }
        
        return ["Authorization": "\(tokens.tokenType) \(tokens.accessToken)"]
    }
    
    public func handleAuthenticationChallenge(_ challenge: AuthenticationChallenge) async throws -> [String: String] {
        logger.info(
            "Handling PKCE OAuth authentication challenge",
            metadata: ["status": .stringConvertible(challenge.statusCode)]
        )
        
        guard challenge.statusCode == 401 else {
            throw AuthenticationError.authenticationFailed("Unexpected status code: \(challenge.statusCode)")
        }
        
        // Try to refresh the access token if we have a refresh token
        if let refreshToken = tokens?.refreshToken {
            try await refreshAccessToken(refreshToken: refreshToken)
            return ["Authorization": "\(tokens?.tokenType ?? "Bearer") \(tokens?.accessToken ?? "")"]
        } else {
            // No refresh token available, need to re-authenticate
            throw AuthenticationError.authenticationExpired
        }
    }
    
    public func isAuthenticationValid() async -> Bool {
        guard let tokens = tokens else {
            return false
        }
        
        guard let expiresAt = tokens.expiresAt else {
            // No expiration set, assume token is valid
            return true
        }
        
        // Check if token expires within the next 5 minutes
        let refreshThreshold = Date().addingTimeInterval(300)
        return expiresAt > refreshThreshold
    }
    
    public func cleanup() async {
        // In a production app, you might want to revoke the tokens
        logger.info("PKCE OAuth authentication cleaned up")
        self.tokens = nil
        self.serverMetadata = nil
    }
    
    /// Start the PKCE OAuth authorization flow
    /// This method should be called to initiate the authorization process
    /// - Returns: Authorization URL that the user should visit
    /// - Throws: OAuthMetadataError if server metadata cannot be discovered or PKCE is not supported
    public func startAuthorizationFlow() async throws -> URL {
        logger.info("Starting PKCE OAuth authorization flow")
        
        // Discover server metadata and validate PKCE support
        try await discoverAndValidateServerMetadata()
        
        guard let authorizationEndpoint = await getAuthorizationEndpoint() else {
            throw OAuthMetadataError.invalidResponse("Authorization endpoint not found in server metadata")
        }
        
        // Build authorization URL with PKCE parameters
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI.absoluteString),
            URLQueryItem(name: "code_challenge", value: config.pkcePair.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: config.pkcePair.codeChallengeMethod),
            URLQueryItem(name: "state", value: generateState())
        ]
        
        if let scope = config.scope {
            components?.queryItems?.append(URLQueryItem(name: "scope", value: scope))
        }
        
        // Add resource parameter as required by RFC 8707 for MCP clients
        if let resourceURI = config.resourceURI {
            components?.queryItems?.append(URLQueryItem(name: "resource", value: resourceURI))
            logger.info(
                "Added resource parameter to authorization request",
                metadata: ["resourceURI": .string(resourceURI)]
            )
        }
        
        guard let authorizationURL = components?.url else {
            throw AuthenticationError.authenticationFailed("Failed to build authorization URL")
        }
        
        logger.info(
            "Authorization URL generated",
            metadata: ["authorizationURL": .string(authorizationURL.absoluteString)]
        )
        return authorizationURL
    }
    
    /// Complete the PKCE OAuth authorization flow by exchanging authorization code for tokens
    /// - Parameter authorizationCode: The authorization code received from the authorization server
    /// - Parameter state: The state parameter from the authorization response (for validation)
    /// - Throws: AuthenticationError if token exchange fails
    public func completeAuthorizationFlow(authorizationCode: String, state: String? = nil) async throws {
        logger.info("Completing PKCE OAuth authorization flow")
        
        guard let tokenEndpoint = await getTokenEndpoint() else {
            throw OAuthMetadataError.invalidResponse("Token endpoint not found in server metadata")
        }
        
        // Build token request
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Build request body
        var bodyComponents = [
            "grant_type=authorization_code",
            "code=\(authorizationCode)",
            "redirect_uri=\(config.redirectURI.absoluteString)",
            "code_verifier=\(config.pkcePair.codeVerifier)"
        ]
        
        // Add resource parameter as required by RFC 8707 for MCP clients
        if let resourceURI = config.resourceURI {
            bodyComponents.append("resource=\(ResourceIndicatorUtilities.createResourceParameter(canonicalURI: resourceURI))")
            logger.info(
                "Added resource parameter to token request",
                metadata: ["resourceURI": .string(resourceURI)]
            )
        }
        
        // Add client authentication
        if let clientSecret = config.clientSecret {
            // Use client credentials in body
            bodyComponents.append("client_id=\(config.clientId)")
            bodyComponents.append("client_secret=\(clientSecret)")
        } else {
            // Public client (PKCE flow)
            bodyComponents.append("client_id=\(config.clientId)")
        }
        
        let bodyString = bodyComponents.joined(separator: "&")
        request.httpBody = bodyString.data(using: String.Encoding.utf8)
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthenticationError.networkError("Invalid response type")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error(
                    "PKCE OAuth token exchange failed",
                    metadata: [
                        "status": .stringConvertible(httpResponse.statusCode),
                        "payload": .string(errorMessage)
                    ]
                )
                throw AuthenticationError.authenticationFailed("Token exchange failed: \(errorMessage)")
            }
            
            // Parse token response
            let newTokens = try parseTokenResponse(data)
            self.tokens = newTokens
            
            logger.info("Successfully completed PKCE OAuth authorization flow")
            
        } catch {
            logger.error(
                "Failed to complete PKCE OAuth authorization flow",
                metadata: ["error": .string(String(describing: error))]
            )
            if error is AuthenticationError {
                throw error
            } else {
                throw AuthenticationError.networkError(error.localizedDescription)
            }
        }
    }
    
    /// Get current access token (useful for debugging or logging)
    public func getCurrentAccessToken() async -> String? {
        return tokens?.accessToken
    }
    
    /// Get current tokens (useful for persisting to storage)
    public func getCurrentTokens() async -> OAuthTokens? {
        return tokens
    }
    
    /// Update tokens (useful when tokens are refreshed externally)
    public func updateTokens(_ newTokens: OAuthTokens) async {
        self.tokens = newTokens
        logger.info("PKCE OAuth tokens updated")
    }
    
    /// Get the authorization endpoint URL
    public func getAuthorizationEndpoint() async -> URL? {
        return getAuthorizationEndpointInternal()
    }
    
    /// Get the token endpoint URL
    public func getTokenEndpoint() async -> URL? {
        return getTokenEndpointInternal()
    }
    
    // MARK: - Private Methods
    
    private func discoverAndValidateServerMetadata() async throws {
        if serverMetadata == nil {
            if config.useOpenIDConnectDiscovery {
                do {
                    let oidcMetadata = try await metadataClient.discoverOpenIDConnectProviderMetadata(issuerURL: config.issuerURL)
                    serverMetadata = oidcMetadata.oauthMetadata
                } catch {
                    // Fall back to OAuth server metadata discovery
                    logger.info("OpenID Connect discovery failed, falling back to OAuth server metadata discovery")
                    serverMetadata = try await metadataClient.discoverOAuthServerMetadata(issuerURL: config.issuerURL)
                }
            } else {
                serverMetadata = try await metadataClient.discoverOAuthServerMetadata(issuerURL: config.issuerURL)
            }
        }
        
        // Validate PKCE support as required by MCP spec
        guard let metadata = serverMetadata else {
            throw OAuthMetadataError.discoveryFailed("Server metadata not available")
        }
        
        let _ = try metadata.validatePKCESupport()
        logger.info("PKCE support validated for authorization server")
    }
    
    private func getAuthorizationEndpointInternal() -> URL? {
        if let customEndpoint = config.authorizationEndpoint {
            return customEndpoint
        }
        
        guard let endpointString = serverMetadata?.authorizationEndpoint else {
            return nil
        }
        
        return URL(string: endpointString)
    }
    
    private func getTokenEndpointInternal() -> URL? {
        if let customEndpoint = config.tokenEndpoint {
            return customEndpoint
        }
        
        guard let endpointString = serverMetadata?.tokenEndpoint else {
            return nil
        }
        
        return URL(string: endpointString)
    }
    
    private func generateState() -> String {
        // Generate a random state parameter for CSRF protection
        let randomBytes = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        return randomBytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func refreshAccessToken(refreshToken: String) async throws {
        guard let tokenEndpoint = await getTokenEndpoint() else {
            throw OAuthMetadataError.invalidResponse("Token endpoint not found in server metadata")
        }
        
        logger.info("Refreshing PKCE OAuth access token")
        
        // Prepare refresh token request
        var request = URLRequest(url: tokenEndpoint)
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
            logger.info(
                "Added resource parameter to token refresh request",
                metadata: ["resourceURI": .string(resourceURI)]
            )
        }
        
        // Add client authentication
        if let clientSecret = config.clientSecret {
            // Use client credentials in body
            bodyComponents.append("client_id=\(config.clientId)")
            bodyComponents.append("client_secret=\(clientSecret)")
        } else {
            // Public client (PKCE flow)
            bodyComponents.append("client_id=\(config.clientId)")
        }
        
        let bodyString = bodyComponents.joined(separator: "&")
        request.httpBody = bodyString.data(using: String.Encoding.utf8)
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthenticationError.networkError("Invalid response type")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error(
                    "PKCE OAuth token refresh failed",
                    metadata: [
                        "status": .stringConvertible(httpResponse.statusCode),
                        "payload": .string(errorMessage)
                    ]
                )
                throw AuthenticationError.authenticationFailed("Token refresh failed: \(errorMessage)")
            }
            
            // Parse token response
            let newTokens = try parseTokenResponse(data)
            self.tokens = newTokens
            
            logger.info("Successfully refreshed PKCE OAuth access token")
            
        } catch {
            logger.error(
                "Failed to refresh PKCE OAuth token",
                metadata: ["error": .string(String(describing: error))]
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
        
        let refreshToken = json["refresh_token"] as? String ?? tokens?.refreshToken // Keep existing refresh token if not provided
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
