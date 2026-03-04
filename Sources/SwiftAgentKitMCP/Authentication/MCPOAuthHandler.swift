// MCP OAuth Integration Handler
// Integrates OAuth authentication with SwiftAgentKit MCP client connections

import Foundation
import SwiftAgentKit
import EasyJSON

/// MCP OAuth handler that manages authentication for remote MCP servers
@MainActor
public class MCPOAuthHandler: ObservableObject {
    private let authenticator: OAuthAuthenticator
    public let tokenStorage: OAuthTokenStorage

    public init(tokenStorage: OAuthTokenStorage? = nil) {
        self.authenticator = OAuthAuthenticator()
        // Use robust storage by default, which automatically handles keychain fallback
        if let tokenStorage = tokenStorage {
            self.tokenStorage = tokenStorage
        } else {
            self.tokenStorage = RobustTokenStorage()
        }
    }

    /// Attempts to connect to a remote MCP server with OAuth authentication
    public func connectToRemoteServer(
        client: MCPClient,
        config: MCPConfig.RemoteServerConfig
    ) async throws {

        do {
            // Attempt to connect with the provided server config
            try await client.connectToRemoteServer(config: config)
            print("Successfully connected to \(config.name) without OAuth")
            return

        } catch let oauthFlowError as OAuthManualFlowRequired {

            // Handle the special case where the MCPClient asks us to perform manual OAuth authentication.
            // Because this involves user interaction it is our responsibility to capture the auth token
            // and call connectToRemoteServer again with the new infomation

            print("Manual OAuth authentication required for \(config.name)")

            // Check if we have a stored token with configuration first
            if let storedTokenWithConfig = try await tokenStorage.retrieveTokenWithConfig(for: config.name) {
                print("Found stored OAuth token with config for \(config.name), retrying connection...")

                // Try to connect with the stored token and configuration
                let authenticatedConfig = createAuthenticatedConfig(
                    from: config,
                    with: storedTokenWithConfig
                )

                do {
                    try await client.connectToRemoteServer(config: authenticatedConfig)
                    print("Successfully connected to \(config.name) with stored OAuth token")
                    return
                } catch {
                    print("Connection with stored token failed: \(error)")
                    print("Error details: \(String(describing: error))")

                    // Check if it's a session-related error
                    let errorString = error.localizedDescription
                    if errorString.contains("Invalid session ID") {
                        print("⚠️  Invalid session ID error detected - token may be expired or invalid")
                        print("   Token details: accessToken=\(storedTokenWithConfig.token.accessToken.prefix(20))...")
                        print("   Token type: \(storedTokenWithConfig.token.tokenType)")
                        print("   Expires in: \(storedTokenWithConfig.token.expiresIn ?? 0) seconds")
                    }

                    // Token might be expired, remove it and continue to request new one
                    try? await tokenStorage.removeToken(for: config.name)
                }
            }

            // Extract token endpoint and client ID from the OAuth flow error
            guard let tokenEndpoint = oauthFlowError.additionalMetadata["token_endpoint"] else {
                throw OAuthError.invalidURL
            }

            // Prefer SwiftAgentKit MCP OAuth discovery path: clientID at top level of config.
            // Otherwise use authConfig.clientId, or dynamic registration from OAuth flow error.
            let clientId: String
            let clientSecret: String?

            if let topLevelClientID = config.clientID {
                // Discovery path: clientID at top level of server config
                clientId = topLevelClientID
                clientSecret = (try? extractOAuthCredentials(from: config))?.clientSecret
                print("Using client ID from top-level config (discovery path): \(clientId)")
            } else if config.authConfig != nil {
                // Static configuration - extract from authConfig
                let credentials = try extractOAuthCredentials(from: config)
                clientId = credentials.clientId
                clientSecret = credentials.clientSecret
            } else {
                // Dynamic registration - use from OAuth flow error
                clientId = oauthFlowError.clientId
                clientSecret = nil // Dynamic registration doesn't use client secrets
                print("Using dynamically registered client ID: \(clientId)")
            }

            // Perform OAuth flow using the information from OAuthManualFlowRequired error
            let token = try await performManualOAuthFlow(
                oauthFlowError: oauthFlowError,
                config: config,
                clientId: clientId,
                clientSecret: clientSecret
            )

            // Create token with configuration using the correct client ID and secret
            let tokenWithConfig = OAuthTokenWithConfig(
                token: token,
                tokenEndpoint: tokenEndpoint,
                clientId: clientId,
                clientSecret: clientSecret,
                scope: oauthFlowError.scope
            )

            // Store the new token with configuration
            try await tokenStorage.storeTokenWithConfig(tokenWithConfig, for: config.name)

            // Connect with the new token
            let authenticatedConfig = createAuthenticatedConfig(
                from: config,
                with: tokenWithConfig
            )

            try await client.connectToRemoteServer(config: authenticatedConfig)
            print("Successfully connected to \(config.name) with new OAuth token")
        } catch {
            // Re-throw non-OAuth errors - no string parsing or fallback logic
            print("Connection to \(config.name) failed: \(error)")
            print("Error details: \(String(describing: error))")

            // Check if it's a session-related error
            let errorString = error.localizedDescription
            if errorString.contains("Invalid session ID") {
                print("⚠️  Invalid session ID error detected with new token")
                print("   This suggests the OAuth flow may not be working correctly")
                print("   or the GitHub MCP server has specific requirements")
                print("   This might be a GitHub MCP server configuration issue.")
            }

            throw error
        }
    }

    private func createAuthenticatedConfig(
        from config: MCPConfig.RemoteServerConfig,
        with token: OAuthToken
    ) -> MCPConfig.RemoteServerConfig {
        // Create auth configuration with the OAuth token
        // SwiftAgentKit's AuthenticationFactory.createOAuthProvider expects "accessToken" key
        let authConfigDict: [String: Any] = [
            "type": "bearer",
            "accessToken": token.accessToken,
            "tokenType": token.tokenType,
            "expiresIn": token.expiresIn ?? 3600, // Default to 1 hour if not specified
            "scope": token.scope ?? ""
        ]

        let authConfig = try? JSON(authConfigDict)

        // Create new configuration with OAuth authentication
        return MCPConfig.RemoteServerConfig(
            name: config.name,
            url: config.url,
            authType: "OAuth",
            authConfig: authConfig,
            connectionTimeout: config.connectionTimeout,
            requestTimeout: config.requestTimeout,
            maxRetries: config.maxRetries
        )
    }

    private func createAuthenticatedConfig(
        from config: MCPConfig.RemoteServerConfig,
        with tokenWithConfig: OAuthTokenWithConfig
    ) -> MCPConfig.RemoteServerConfig {
        // Create auth configuration with the OAuth token and configuration
        // SwiftAgentKit's AuthenticationFactory.createOAuthProvider expects specific fields
        var authConfigDict: [String: Any] = [
            "accessToken": tokenWithConfig.token.accessToken,
            "tokenEndpoint": tokenWithConfig.tokenEndpoint,
            "clientId": tokenWithConfig.clientId,
            "tokenType": tokenWithConfig.token.tokenType,
            "expiresIn": tokenWithConfig.token.expiresIn ?? 3600, // Default to 1 hour if not specified
            "scope": tokenWithConfig.scope ?? tokenWithConfig.token.scope ?? "mcp" // Default to mcp scope
        ]

        // Add optional fields if they exist
        if let clientSecret = tokenWithConfig.clientSecret {
            authConfigDict["clientSecret"] = clientSecret
        }

        if let refreshToken = tokenWithConfig.token.refreshToken {
            authConfigDict["refreshToken"] = refreshToken
        }

        let authConfig = try? JSON(authConfigDict)

        // Debug: Print the authentication configuration being created
        print("🔐 Creating authenticated config for \(config.name):")
        print("   URL: \(config.url)")
        print("   Auth type: OAuth")
        print("   Access token: \(tokenWithConfig.token.accessToken.prefix(20))...")
        print("   Token type: \(tokenWithConfig.token.tokenType)")
        print("   Client ID: \(tokenWithConfig.clientId)")
        print("   Scope: \(tokenWithConfig.scope ?? tokenWithConfig.token.scope ?? "none")")
        print("   Token endpoint: \(tokenWithConfig.tokenEndpoint)")
        print("   Full auth config dict: \(authConfigDict)")

        // Create new configuration with OAuth authentication
        return MCPConfig.RemoteServerConfig(
            name: config.name,
            url: config.url,
            authType: "OAuth",
            authConfig: authConfig,
            connectionTimeout: config.connectionTimeout,
            requestTimeout: config.requestTimeout,
            maxRetries: config.maxRetries
        )
    }

    /// Initiates the manual OAuth flow using SwiftAgentKit's OAuthManualFlowRequired.
    /// Uses SwiftAgentKit PKCE and error metadata only (no duplicate URL building or OAuthConfig).
    private func performManualOAuthFlow(
        oauthFlowError: OAuthManualFlowRequired,
        config: MCPConfig.RemoteServerConfig,
        clientId: String,
        clientSecret: String?
    ) async throws -> OAuthToken {
        print("Starting OAuth flow (SwiftAgentKit PKCE + discovery metadata)...")
        print("Redirect URI: \(oauthFlowError.redirectURI)")
        print("Client ID: \(clientId)")
        return try await authenticator.completeManualOAuthFlow(
            oauthFlowError: oauthFlowError,
            clientId: clientId,
            clientSecret: clientSecret
        )
    }

    /// Removes stored authentication for a server
    public func removeAuthentication(for serverName: String) async throws {
        try await tokenStorage.removeToken(for: serverName)
        print("Removed authentication for server: \(serverName)")
    }

    /// Checks if a server has stored authentication
    public func hasStoredAuthentication(for serverName: String) async -> Bool {
        do {
            let token = try await tokenStorage.retrieveToken(for: serverName)
            return token != nil
        } catch {
            return false
        }
    }

    /// Clears all stored authentication (useful for debugging)
    public func clearAllAuthentication() async throws {
        try await tokenStorage.clearAllTokens()
        print("Cleared all stored OAuth tokens")
    }

    /// Extracts OAuth credentials from the MCP config.
    /// Supports SwiftAgentKit discovery path: clientID at top level of config, or clientId inside authConfig.
    public func extractOAuthCredentials(from config: MCPConfig.RemoteServerConfig) throws -> (clientId: String, clientSecret: String?) {
        // Discovery path: top-level clientID on server config (SwiftAgentKit MCP OAuth discovery)
        if let topLevelClientID = config.clientID {
            var clientSecret: String? = nil
            if let authConfig = config.authConfig,
               let authConfigDict = authConfig.literalValue as? [String: Any] {
                clientSecret = authConfigDict["clientSecret"] as? String
            }
            return (clientId: topLevelClientID, clientSecret: clientSecret)
        }

        // Fallback: clientId inside authConfig
        guard let authConfig = config.authConfig else {
            throw OAuthError.invalidConfiguration("No auth configuration found for server: \(config.name)")
        }

        guard let authConfigDict = authConfig.literalValue as? [String: Any] else {
            throw OAuthError.invalidConfiguration("Invalid auth configuration format for server: \(config.name)")
        }

        guard let clientId = authConfigDict["clientId"] as? String else {
            throw OAuthError.invalidConfiguration("Missing clientId in auth configuration for server: \(config.name)")
        }

        let clientSecret = authConfigDict["clientSecret"] as? String
        return (clientId: clientId, clientSecret: clientSecret)
    }
}
