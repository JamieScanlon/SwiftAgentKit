// MCP OAuth Integration Handler
// Integrates OAuth authentication with SwiftAgentKit MCP client connections

import Foundation
import Logging
import SwiftAgentKit
import EasyJSON

/// MCP OAuth handler that manages authentication for remote MCP servers.
///
/// **Sendable safety:** This type is `@unchecked Sendable` so it can be passed into `MCPManager` (an actor).
/// It is safe to send across isolation boundaries only when the following rule is observed:
///
/// - **REQUIRED: One handler per manager.** Do *not* pass the same `MCPOAuthHandler` instance to more than
///   one `MCPManager`, and do *not* use a single handler with multiple managers that might call
///   `initialize(configFileURL:)` (or otherwise run `createClients`) concurrently. Sharing one handler across
///   managers would allow concurrent access to the handler's state and can cause data races. Create a separate
///   handler per manager (or let each manager create its own when none is provided).
///
/// When that rule is followed, safety holds because: (1) all use happens inside one `MCPManager`'s actor, and
/// (2) the manager calls `handler.connectToRemoteServer(client:config:)` only from `createClients`, in a
/// sequential `for` loop with `try await` on each call, so handler methods are never executed concurrently
/// on the same instance.
public final class MCPOAuthHandler: @unchecked Sendable {
    private let authenticator: OAuthAuthenticator
    public let tokenStorage: OAuthTokenStorage
    private let logger: Logger

    /// - Parameters:
    ///   - tokenStorage: Optional token storage; if nil, a default `RobustTokenStorage` is used.
    ///   - logger: Optional logger; if nil, a default scoped to `.mcp("MCPOAuthHandler")` is used.
    public init(tokenStorage: OAuthTokenStorage? = nil, logger: Logger? = nil) {
        self.logger = logger ?? SwiftAgentKitLogging.logger(for: .mcp("MCPOAuthHandler"))
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
            logger.info(
                "Successfully connected to remote MCP server without OAuth",
                metadata: SwiftAgentKitLogging.metadata(("server", .string(config.name)))
            )
            return

        } catch let oauthFlowError as OAuthManualFlowRequired {

            // Handle the special case where the MCPClient asks us to perform manual OAuth authentication.
            // Because this involves user interaction it is our responsibility to capture the auth token
            // and call connectToRemoteServer again with the new infomation

            logger.info(
                "Manual OAuth authentication required for remote MCP server",
                metadata: SwiftAgentKitLogging.metadata(("server", .string(config.name)))
            )

            // Check if we have a stored token with configuration first
            if let storedTokenWithConfig = try await tokenStorage.retrieveTokenWithConfig(for: config.name) {
                logger.info(
                    "Found stored OAuth token with config, retrying connection",
                    metadata: SwiftAgentKitLogging.metadata(("server", .string(config.name)))
                )

                // Try to connect with the stored token and configuration
                let authenticatedConfig = createAuthenticatedConfig(
                    from: config,
                    with: storedTokenWithConfig
                )

                do {
                    try await client.connectToRemoteServer(config: authenticatedConfig)
                    logger.info(
                        "Successfully connected to remote MCP server with stored OAuth token",
                        metadata: SwiftAgentKitLogging.metadata(("server", .string(config.name)))
                    )
                    return
                } catch {
                    logger.warning(
                        "Connection with stored token failed",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("server", .string(config.name)),
                            ("error", .string(String(describing: error)))
                        )
                    )

                    // Check if it's a session-related error
                    let errorString = error.localizedDescription
                    if errorString.contains("Invalid session ID") {
                        logger.warning(
                            "Invalid session ID - token may be expired or invalid",
                            metadata: SwiftAgentKitLogging.metadata(
                                ("server", .string(config.name)),
                                ("tokenType", .string(storedTokenWithConfig.token.tokenType)),
                                ("expiresIn", .stringConvertible(storedTokenWithConfig.token.expiresIn ?? 0))
                            )
                        )
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
                logger.debug(
                    "Using client ID from top-level config (discovery path)",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("server", .string(config.name)),
                        ("clientId", .string(clientId))
                    )
                )
            } else if config.authConfig != nil {
                // Static configuration - extract from authConfig
                let credentials = try extractOAuthCredentials(from: config)
                clientId = credentials.clientId
                clientSecret = credentials.clientSecret
            } else {
                // Dynamic registration - use from OAuth flow error
                clientId = oauthFlowError.clientId
                clientSecret = nil // Dynamic registration doesn't use client secrets
                logger.debug(
                    "Using dynamically registered client ID",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("server", .string(config.name)),
                        ("clientId", .string(clientId))
                    )
                )
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
            logger.info(
                "Successfully connected to remote MCP server with new OAuth token",
                metadata: SwiftAgentKitLogging.metadata(("server", .string(config.name)))
            )
        } catch {
            // Re-throw non-OAuth errors - no string parsing or fallback logic
            logger.error(
                "Connection to remote MCP server failed",
                metadata: SwiftAgentKitLogging.metadata(
                    ("server", .string(config.name)),
                    ("error", .string(String(describing: error)))
                )
            )

            // Check if it's a session-related error
            let errorString = error.localizedDescription
            if errorString.contains("Invalid session ID") {
                logger.warning(
                    "Invalid session ID with new token - OAuth flow or server configuration may need adjustment",
                    metadata: SwiftAgentKitLogging.metadata(("server", .string(config.name)))
                )
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

        logger.debug(
            "Creating authenticated config for remote MCP server",
            metadata: SwiftAgentKitLogging.metadata(
                ("server", .string(config.name)),
                ("url", .string(config.url)),
                ("tokenType", .string(tokenWithConfig.token.tokenType)),
                ("clientId", .string(tokenWithConfig.clientId)),
                ("tokenEndpoint", .string(tokenWithConfig.tokenEndpoint))
            )
        )

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
        logger.info(
            "Starting manual OAuth flow (PKCE + discovery metadata)",
            metadata: SwiftAgentKitLogging.metadata(
                ("server", .string(config.name)),
                ("redirectURI", .string(oauthFlowError.redirectURI.absoluteString)),
                ("clientId", .string(clientId))
            )
        )
        return try await authenticator.completeManualOAuthFlow(
            oauthFlowError: oauthFlowError,
            clientId: clientId,
            clientSecret: clientSecret
        )
    }

    /// Removes stored authentication for a server
    public func removeAuthentication(for serverName: String) async throws {
        try await tokenStorage.removeToken(for: serverName)
        logger.info(
            "Removed authentication for server",
            metadata: SwiftAgentKitLogging.metadata(("server", .string(serverName)))
        )
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
        logger.info("Cleared all stored OAuth tokens")
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
