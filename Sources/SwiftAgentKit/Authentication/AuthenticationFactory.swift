//
//  AuthenticationFactory.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/20/25.
//

import Foundation
import EasyJSON
import Logging

/// Factory for creating authentication providers based on configuration
public struct AuthenticationFactory {
    
    private static let logger = Logger(label: "AuthenticationFactory")
    
    /// Creates an authentication provider based on the configuration
    /// - Parameters:
    ///   - authType: Type of authentication (e.g., "bearer", "apikey", "basic")
    ///   - config: Authentication configuration as JSON
    /// - Returns: Configured authentication provider
    /// - Throws: AuthenticationError if configuration is invalid
    public static func createAuthProvider(
        authType: String,
        config: JSON
    ) throws -> any AuthenticationProvider {
        
        logger.info("Creating authentication provider for type: \(authType)")
        
        guard let scheme = AuthenticationScheme(rawValue: authType) else {
            logger.error("Unsupported authentication type: \(authType)")
            throw AuthenticationError.unsupportedAuthScheme(authType)
        }
        
        return try createAuthProvider(scheme: scheme, config: config)
    }
    
    /// Creates an authentication provider based on the scheme enum
    /// - Parameters:
    ///   - scheme: Authentication scheme enum
    ///   - config: Authentication configuration as JSON
    /// - Returns: Configured authentication provider
    /// - Throws: AuthenticationError if configuration is invalid
    public static func createAuthProvider(
        scheme: AuthenticationScheme,
        config: JSON
    ) throws -> any AuthenticationProvider {
        
        logger.info("Creating authentication provider for scheme: \(scheme.rawValue)")
        
        switch scheme {
        case .bearer:
            return try createBearerTokenProvider(config: config)
            
        case .apiKey:
            return try createAPIKeyProvider(config: config)
            
        case .basic:
            return try createBasicAuthProvider(config: config)
            
        case .oauth:
            // Check if this is a Dynamic Client Registration configuration
            if isDynamicClientRegistrationConfig(config: config) {
                return try createDynamicClientRegistrationProvider(config: config)
            }
            // Check if this is a PKCE OAuth configuration
            else if isPKCEOAuthConfig(config: config) {
                return try createPKCEOAuthProvider(config: config)
            } else if isOAuthDiscoveryConfig(config: config) {
                return try createOAuthDiscoveryProvider(config: config)
            } else if isDirectOAuthConfig(config: config) {
                return try createDirectOAuthProvider(config: config)
            } else {
                return try createOAuthProvider(config: config)
            }
            
        case .custom(let customScheme):
            logger.error("Custom authentication scheme not supported by factory: \(customScheme)")
            throw AuthenticationError.unsupportedAuthScheme(customScheme)
        }
    }
    
    /// Creates authentication provider from environment variables
    /// - Parameter serverName: Name of the server for environment variable prefixing
    /// - Returns: Authentication provider or nil if no auth config found
    public static func createAuthProviderFromEnvironment(
        serverName: String
    ) -> (any AuthenticationProvider)? {
        
        let envPrefix = "\(serverName.uppercased())_"
        
        // Check for Bearer token
        if let token = ProcessInfo.processInfo.environment["\(envPrefix)TOKEN"] ?? 
                       ProcessInfo.processInfo.environment["\(envPrefix)BEARER_TOKEN"] {
            logger.info("Creating Bearer token provider from environment for server: \(serverName)")
            return BearerTokenAuthProvider(token: token)
        }
        
        // Check for API key
        if let apiKey = ProcessInfo.processInfo.environment["\(envPrefix)API_KEY"] {
            let headerName = ProcessInfo.processInfo.environment["\(envPrefix)API_HEADER"] ?? "X-API-Key"
            let prefix = ProcessInfo.processInfo.environment["\(envPrefix)API_PREFIX"]
            logger.info("Creating API key provider from environment for server: \(serverName)")
            return APIKeyAuthProvider(apiKey: apiKey, headerName: headerName, prefix: prefix)
        }
        
        // Check for Basic auth
        if let username = ProcessInfo.processInfo.environment["\(envPrefix)USERNAME"],
           let password = ProcessInfo.processInfo.environment["\(envPrefix)PASSWORD"] {
            logger.info("Creating Basic auth provider from environment for server: \(serverName)")
            return BasicAuthProvider(username: username, password: password)
        }
        
        // Check for PKCE OAuth
        if let issuerURL = ProcessInfo.processInfo.environment["\(envPrefix)PKCE_OAUTH_ISSUER_URL"],
           let clientId = ProcessInfo.processInfo.environment["\(envPrefix)PKCE_OAUTH_CLIENT_ID"],
           let redirectURI = ProcessInfo.processInfo.environment["\(envPrefix)PKCE_OAUTH_REDIRECT_URI"],
           let issuerURLParsed = URL(string: issuerURL),
           issuerURLParsed.scheme != nil,
           issuerURLParsed.host != nil,
           let redirectURIParsed = URL(string: redirectURI),
           redirectURIParsed.scheme != nil {
            
            let clientSecret = ProcessInfo.processInfo.environment["\(envPrefix)PKCE_OAUTH_CLIENT_SECRET"]
            let scope = ProcessInfo.processInfo.environment["\(envPrefix)PKCE_OAUTH_SCOPE"]
            let authorizationEndpoint = ProcessInfo.processInfo.environment["\(envPrefix)PKCE_OAUTH_AUTHORIZATION_ENDPOINT"]
            let tokenEndpoint = ProcessInfo.processInfo.environment["\(envPrefix)PKCE_OAUTH_TOKEN_ENDPOINT"]
            let useOIDCDiscovery = ProcessInfo.processInfo.environment["\(envPrefix)PKCE_OAUTH_USE_OIDC_DISCOVERY"] != "false"
            let resourceURI = ProcessInfo.processInfo.environment["\(envPrefix)PKCE_OAUTH_RESOURCE_URI"]
            
            let authorizationEndpointURL = authorizationEndpoint.flatMap(URL.init)
            let tokenEndpointURL = tokenEndpoint.flatMap(URL.init)
            
            do {
                let pkceConfig = try PKCEOAuthConfig(
                    issuerURL: issuerURLParsed,
                    clientId: clientId,
                    clientSecret: clientSecret,
                    scope: scope,
                    redirectURI: redirectURIParsed,
                    authorizationEndpoint: authorizationEndpointURL,
                    tokenEndpoint: tokenEndpointURL,
                    useOpenIDConnectDiscovery: useOIDCDiscovery,
                    resourceURI: resourceURI
                )
                
                logger.info("Creating PKCE OAuth provider from environment for server: \(serverName)")
                return PKCEOAuthAuthProvider(config: pkceConfig)
            } catch {
                logger.error("Failed to create PKCE OAuth provider from environment: \(error)")
                return nil
            }
        }
        
        // Check for OAuth (legacy)
        if let accessToken = ProcessInfo.processInfo.environment["\(envPrefix)OAUTH_ACCESS_TOKEN"],
           let tokenEndpoint = ProcessInfo.processInfo.environment["\(envPrefix)OAUTH_TOKEN_ENDPOINT"],
           let clientId = ProcessInfo.processInfo.environment["\(envPrefix)OAUTH_CLIENT_ID"],
           let tokenEndpointURL = URL(string: tokenEndpoint) {
            
            let refreshToken = ProcessInfo.processInfo.environment["\(envPrefix)OAUTH_REFRESH_TOKEN"]
            let clientSecret = ProcessInfo.processInfo.environment["\(envPrefix)OAUTH_CLIENT_SECRET"]
            let scope = ProcessInfo.processInfo.environment["\(envPrefix)OAUTH_SCOPE"]
            let tokenType = ProcessInfo.processInfo.environment["\(envPrefix)OAUTH_TOKEN_TYPE"] ?? "Bearer"
            
            let tokens = OAuthTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                tokenType: tokenType,
                scope: scope
            )
            
            do {
                let oauthConfig = try OAuthConfig(
                    tokenEndpoint: tokenEndpointURL,
                    clientId: clientId,
                    clientSecret: clientSecret,
                    scope: scope
                )
                
                logger.info("Creating OAuth provider from environment for server: \(serverName)")
                return OAuthAuthProvider(tokens: tokens, config: oauthConfig)
            } catch {
                logger.error("Failed to create OAuth config from environment: \(error)")
                return nil
            }
        }
        
        logger.debug("No authentication configuration found in environment for server: \(serverName)")
        return nil
    }
    
    // MARK: - Private Factory Methods
    
    private static func createBearerTokenProvider(config: JSON) throws -> BearerTokenAuthProvider {
        guard case .object(let configDict) = config else {
            throw AuthenticationError.authenticationFailed("Bearer token config must be an object")
        }
        
        guard case .string(let token) = configDict["token"] else {
            throw AuthenticationError.authenticationFailed("Bearer token config missing 'token' field")
        }
        
        // Check for expiration and refresh handler
        if case .string(let expiresAtString) = configDict["expiresAt"] {
            let formatter = ISO8601DateFormatter()
            let expiresAt = formatter.date(from: expiresAtString)
            
            // Note: In a real implementation, you might want to support refresh handlers
            // For now, we'll create a simple token provider
            return BearerTokenAuthProvider(token: token, expiresAt: expiresAt, refreshHandler: nil)
        } else {
            return BearerTokenAuthProvider(token: token)
        }
    }
    
    private static func createAPIKeyProvider(config: JSON) throws -> APIKeyAuthProvider {
        guard case .object(let configDict) = config else {
            throw AuthenticationError.authenticationFailed("API key config must be an object")
        }
        
        guard case .string(let apiKey) = configDict["apiKey"] else {
            throw AuthenticationError.authenticationFailed("API key config missing 'apiKey' field")
        }
        
        let headerName: String
        if case .string(let header) = configDict["headerName"] {
            headerName = header
        } else {
            headerName = "X-API-Key"
        }
        
        let prefix: String?
        if case .string(let prefixValue) = configDict["prefix"] {
            prefix = prefixValue
        } else {
            prefix = nil
        }
        
        return APIKeyAuthProvider(apiKey: apiKey, headerName: headerName, prefix: prefix)
    }
    
    private static func createBasicAuthProvider(config: JSON) throws -> BasicAuthProvider {
        guard case .object(let configDict) = config else {
            throw AuthenticationError.authenticationFailed("Basic auth config must be an object")
        }
        
        guard case .string(let username) = configDict["username"] else {
            throw AuthenticationError.authenticationFailed("Basic auth config missing 'username' field")
        }
        
        guard case .string(let password) = configDict["password"] else {
            throw AuthenticationError.authenticationFailed("Basic auth config missing 'password' field")
        }
        
        return BasicAuthProvider(username: username, password: password)
    }
    
    private static func createOAuthProvider(config: JSON) throws -> OAuthAuthProvider {
        guard case .object(let configDict) = config else {
            throw AuthenticationError.authenticationFailed("OAuth config must be an object")
        }
        
        // Required fields
        guard case .string(let accessToken) = configDict["accessToken"] else {
            throw AuthenticationError.authenticationFailed("OAuth config missing 'accessToken' field")
        }
        
        guard case .string(let tokenEndpointString) = configDict["tokenEndpoint"] else {
            throw AuthenticationError.authenticationFailed("OAuth config missing 'tokenEndpoint' field")
        }
        
        guard let tokenEndpoint = URL(string: tokenEndpointString),
              tokenEndpoint.scheme != nil,
              tokenEndpoint.host != nil else {
            throw AuthenticationError.authenticationFailed("Invalid token endpoint URL: \(tokenEndpointString)")
        }
        
        guard case .string(let clientId) = configDict["clientId"] else {
            throw AuthenticationError.authenticationFailed("OAuth config missing 'clientId' field")
        }
        
        // Optional fields
        let refreshToken: String?
        if case .string(let token) = configDict["refreshToken"] {
            refreshToken = token
        } else {
            refreshToken = nil
        }
        
        let clientSecret: String?
        if case .string(let secret) = configDict["clientSecret"] {
            clientSecret = secret
        } else {
            clientSecret = nil
        }
        
        let scope: String?
        if case .string(let scopeValue) = configDict["scope"] {
            scope = scopeValue
        } else {
            scope = nil
        }
        
        let tokenType: String
        if case .string(let type) = configDict["tokenType"] {
            tokenType = type
        } else {
            tokenType = "Bearer"
        }
        
        let expiresIn: TimeInterval?
        if case .double(let expires) = configDict["expiresIn"] {
            expiresIn = TimeInterval(expires)
        } else if case .integer(let expires) = configDict["expiresIn"] {
            expiresIn = TimeInterval(expires)
        } else {
            expiresIn = nil
        }
        
        // Create tokens and config
        let tokens = OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresIn: expiresIn,
            scope: scope
        )
        
        let oauthConfig = try OAuthConfig(
            tokenEndpoint: tokenEndpoint,
            clientId: clientId,
            clientSecret: clientSecret,
            scope: scope
        )
        
        return OAuthAuthProvider(tokens: tokens, config: oauthConfig)
    }
    
    private static func isPKCEOAuthConfig(config: JSON) -> Bool {
        guard case .object(let configDict) = config else {
            return false
        }
        
        // Check if this is a PKCE OAuth configuration by looking for required PKCE fields
        return configDict["issuerURL"] != nil && 
               configDict["redirectURI"] != nil &&
               configDict["clientId"] != nil
    }
    
    private static func isOAuthDiscoveryConfig(config: JSON) -> Bool {
        guard case .object(let configDict) = config else {
            return false
        }
        
        // Check if this is an OAuth Discovery configuration by looking for required fields
        return configDict["resourceServerURL"] != nil && 
               configDict["clientId"] != nil &&
               configDict["redirectURI"] != nil &&
               configDict["useOAuthDiscovery"] != nil
    }
    
    private static func isDirectOAuthConfig(config: JSON) -> Bool {
        guard case .object(let configDict) = config else {
            return false
        }
        
        // Check if this is a direct OAuth configuration with clientId and clientSecret
        // but without accessToken (which would indicate a pre-existing token)
        // and without issuerURL (which would indicate PKCE OAuth)
        // and without useOAuthDiscovery flag (which would indicate OAuth Discovery)
        return configDict["clientId"] != nil && 
               configDict["clientSecret"] != nil &&
               configDict["redirectURI"] != nil &&
               configDict["accessToken"] == nil &&
               configDict["issuerURL"] == nil &&
               configDict["useOAuthDiscovery"] == nil &&
               configDict["useDynamicClientRegistration"] == nil
    }
    
    private static func createPKCEOAuthProvider(config: JSON) throws -> PKCEOAuthAuthProvider {
        guard case .object(let configDict) = config else {
            throw AuthenticationError.authenticationFailed("PKCE OAuth config must be an object")
        }
        
        // Required fields
        guard case .string(let issuerURLString) = configDict["issuerURL"] else {
            throw AuthenticationError.authenticationFailed("PKCE OAuth config missing 'issuerURL' field")
        }
        
        guard let issuerURL = URL(string: issuerURLString),
              issuerURL.scheme != nil,
              issuerURL.host != nil else {
            throw AuthenticationError.authenticationFailed("Invalid issuer URL: \(issuerURLString)")
        }
        
        guard case .string(let clientId) = configDict["clientId"] else {
            throw AuthenticationError.authenticationFailed("PKCE OAuth config missing 'clientId' field")
        }
        
        guard case .string(let redirectURIString) = configDict["redirectURI"] else {
            throw AuthenticationError.authenticationFailed("PKCE OAuth config missing 'redirectURI' field")
        }
        
        guard let redirectURI = URL(string: redirectURIString),
              redirectURI.scheme != nil else {
            throw AuthenticationError.authenticationFailed("Invalid redirect URI: \(redirectURIString)")
        }
        
        // Optional fields
        let clientSecret: String?
        if case .string(let secret) = configDict["clientSecret"] {
            clientSecret = secret
        } else {
            clientSecret = nil
        }
        
        let scope: String?
        if case .string(let scopeValue) = configDict["scope"] {
            scope = scopeValue
        } else {
            scope = nil
        }
        
        let authorizationEndpoint: URL?
        if case .string(let authEndpointString) = configDict["authorizationEndpoint"],
           let authEndpoint = URL(string: authEndpointString) {
            authorizationEndpoint = authEndpoint
        } else {
            authorizationEndpoint = nil
        }
        
        let tokenEndpoint: URL?
        if case .string(let tokenEndpointString) = configDict["tokenEndpoint"],
           let tokenEndpointURL = URL(string: tokenEndpointString) {
            tokenEndpoint = tokenEndpointURL
        } else {
            tokenEndpoint = nil
        }
        
        let useOpenIDConnectDiscovery: Bool
        if case .boolean(let useOIDC) = configDict["useOpenIDConnectDiscovery"] {
            useOpenIDConnectDiscovery = useOIDC
        } else {
            useOpenIDConnectDiscovery = true
        }
        
        let resourceURI: String?
        if case .string(let resource) = configDict["resourceURI"] {
            resourceURI = resource
        } else {
            resourceURI = nil
        }
        
        // Create PKCE OAuth configuration
        let pkceConfig = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: clientId,
            clientSecret: clientSecret,
            scope: scope,
            redirectURI: redirectURI,
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint,
            useOpenIDConnectDiscovery: useOpenIDConnectDiscovery,
            resourceURI: resourceURI
        )
        
        return PKCEOAuthAuthProvider(config: pkceConfig)
    }
    
    private static func createOAuthDiscoveryProvider(config: JSON) throws -> OAuthDiscoveryAuthProvider {
        guard case .object(let configDict) = config else {
            throw AuthenticationError.authenticationFailed("OAuth Discovery config must be an object")
        }
        
        // Required fields
        guard case .string(let resourceServerURLString) = configDict["resourceServerURL"] else {
            throw AuthenticationError.authenticationFailed("OAuth Discovery config missing 'resourceServerURL' field")
        }
        
        guard let resourceServerURL = URL(string: resourceServerURLString),
              resourceServerURL.scheme != nil,
              resourceServerURL.host != nil else {
            throw AuthenticationError.authenticationFailed("Invalid resource server URL: \(resourceServerURLString)")
        }
        
        guard case .string(let clientId) = configDict["clientId"], !clientId.isEmpty else {
            throw AuthenticationError.authenticationFailed("OAuth Discovery config missing 'clientId' field")
        }
        
        guard case .string(let redirectURIString) = configDict["redirectURI"] else {
            throw AuthenticationError.authenticationFailed("OAuth Discovery config missing 'redirectURI' field")
        }
        
        guard let redirectURI = URL(string: redirectURIString),
              redirectURI.scheme != nil else {
            throw AuthenticationError.authenticationFailed("Invalid redirect URI: \(redirectURIString)")
        }
        
        // Optional fields
        let clientSecret: String?
        if case .string(let secret) = configDict["clientSecret"] {
            clientSecret = secret
        } else {
            clientSecret = nil
        }
        
        let scope: String?
        if case .string(let scopeValue) = configDict["scope"] {
            scope = scopeValue
        } else {
            scope = nil
        }
        
        let resourceType: String?
        if case .string(let type) = configDict["resourceType"] {
            resourceType = type
        } else {
            resourceType = "mcp"
        }
        
        let preConfiguredAuthServerURL: URL?
        if case .string(let authServerURLString) = configDict["preConfiguredAuthServerURL"],
           let authServerURL = URL(string: authServerURLString) {
            preConfiguredAuthServerURL = authServerURL
        } else {
            preConfiguredAuthServerURL = nil
        }
        
        return try OAuthDiscoveryAuthProvider(
            resourceServerURL: resourceServerURL,
            clientId: clientId,
            clientSecret: clientSecret,
            scope: scope,
            redirectURI: redirectURI,
            resourceType: resourceType,
            preConfiguredAuthServerURL: preConfiguredAuthServerURL
        )
    }
    
    private static func createDirectOAuthProvider(config: JSON) throws -> OAuthDiscoveryAuthProvider {
        guard case .object(let configDict) = config else {
            throw AuthenticationError.authenticationFailed("Direct OAuth config must be an object")
        }
        
        // Required fields
        guard case .string(let clientId) = configDict["clientId"], !clientId.isEmpty else {
            throw AuthenticationError.authenticationFailed("Direct OAuth config missing 'clientId' field")
        }
        
        guard case .string(let redirectURIString) = configDict["redirectURI"] else {
            throw AuthenticationError.authenticationFailed("Direct OAuth config missing 'redirectURI' field")
        }
        
        guard let redirectURI = URL(string: redirectURIString),
              redirectURI.scheme != nil else {
            throw AuthenticationError.authenticationFailed("Invalid redirect URI: \(redirectURIString)")
        }
        
        // Optional fields
        let clientSecret: String?
        if case .string(let secret) = configDict["clientSecret"] {
            clientSecret = secret
        } else {
            clientSecret = nil
        }
        
        let scope: String?
        if case .string(let scopeValue) = configDict["scope"] {
            scope = scopeValue
        } else {
            scope = nil
        }
        
        // For direct OAuth, resourceServerURL should be provided by MCPManager automatically
        // If not present, we'll use a placeholder that should be replaced by the MCPManager
        let resourceServerURLString: String
        if case .string(let urlString) = configDict["resourceServerURL"] {
            resourceServerURLString = urlString
        } else {
            // This should not happen if MCPManager is working correctly
            // Use a placeholder URL that will be replaced
            resourceServerURLString = "https://placeholder.mcp.server"
        }
        
        guard let resourceServerURL = URL(string: resourceServerURLString),
              resourceServerURL.scheme != nil,
              resourceServerURL.host != nil else {
            throw AuthenticationError.authenticationFailed("Invalid resource server URL: \(resourceServerURLString)")
        }
        
        let resourceType: String?
        if case .string(let type) = configDict["resourceType"] {
            resourceType = type
        } else {
            resourceType = "mcp"
        }
        
        let preConfiguredAuthServerURL: URL?
        if case .string(let authServerURLString) = configDict["preConfiguredAuthServerURL"],
           let authServerURL = URL(string: authServerURLString) {
            preConfiguredAuthServerURL = authServerURL
        } else {
            preConfiguredAuthServerURL = nil
        }
        
        // Use OAuthDiscoveryAuthProvider but with the user's credentials
        // This will respect the user's clientId and clientSecret instead of using hardcoded values
        return try OAuthDiscoveryAuthProvider(
            resourceServerURL: resourceServerURL,
            clientId: clientId,
            clientSecret: clientSecret,
            scope: scope,
            redirectURI: redirectURI,
            resourceType: resourceType,
            preConfiguredAuthServerURL: preConfiguredAuthServerURL
        )
    }
    
    private static func isDynamicClientRegistrationConfig(config: JSON) -> Bool {
        guard case .object(let configDict) = config else {
            return false
        }
        
        // Check if this is a Dynamic Client Registration configuration by looking for required fields
        return configDict["registrationEndpoint"] != nil && 
               configDict["redirectUris"] != nil &&
               configDict["useDynamicClientRegistration"] != nil
    }
    
    private static func createDynamicClientRegistrationProvider(config: JSON) throws -> DynamicClientRegistrationAuthProvider {
        guard case .object(let configDict) = config else {
            throw AuthenticationError.authenticationFailed("Dynamic Client Registration config must be an object")
        }
        
        // Required fields
        guard case .string(let registrationEndpointString) = configDict["registrationEndpoint"] else {
            throw AuthenticationError.authenticationFailed("Dynamic Client Registration config missing 'registrationEndpoint' field")
        }
        
        guard let registrationEndpoint = URL(string: registrationEndpointString),
              registrationEndpoint.scheme != nil,
              registrationEndpoint.host != nil else {
            throw AuthenticationError.authenticationFailed("Invalid registration endpoint URL: \(registrationEndpointString)")
        }
        
        guard case .array(let redirectUrisArray) = configDict["redirectUris"] else {
            throw AuthenticationError.authenticationFailed("Dynamic Client Registration config missing 'redirectUris' field")
        }
        
        let redirectUris = redirectUrisArray.compactMap { uri in
            if case .string(let uriString) = uri {
                return uriString
            }
            return nil
        }
        
        guard !redirectUris.isEmpty else {
            throw AuthenticationError.authenticationFailed("Dynamic Client Registration config must have at least one redirect URI")
        }
        
        // Optional fields
        let initialAccessToken: String?
        if case .string(let token) = configDict["initialAccessToken"] {
            initialAccessToken = token
        } else {
            initialAccessToken = nil
        }
        
        let clientName: String?
        if case .string(let name) = configDict["clientName"] {
            clientName = name
        } else {
            clientName = nil
        }
        
        let scope: String?
        if case .string(let scopeValue) = configDict["scope"] {
            scope = scopeValue
        } else {
            scope = nil
        }
        
        let softwareStatement: String?
        if case .string(let statement) = configDict["softwareStatement"] {
            softwareStatement = statement
        } else {
            softwareStatement = nil
        }
        
        let additionalMetadata: [String: String]?
        if case .object(let metadataDict) = configDict["additionalMetadata"] {
            var metadata: [String: String] = [:]
            for (key, value) in metadataDict {
                if case .string(let stringValue) = value {
                    metadata[key] = stringValue
                }
            }
            additionalMetadata = metadata.isEmpty ? nil : metadata
        } else {
            additionalMetadata = nil
        }
        
        let requestTimeout: TimeInterval?
        if case .double(let timeout) = configDict["requestTimeout"] {
            requestTimeout = TimeInterval(timeout)
        } else if case .integer(let timeout) = configDict["requestTimeout"] {
            requestTimeout = TimeInterval(timeout)
        } else {
            requestTimeout = nil
        }
        
        // Create registration configuration
        let registrationConfig = DynamicClientRegistrationConfig(
            registrationEndpoint: registrationEndpoint,
            initialAccessToken: initialAccessToken,
            requestTimeout: requestTimeout
        )
        
        // Create registration request
        let registrationRequest = DynamicClientRegistration.ClientRegistrationRequest.mcpClientRequest(
            redirectUris: redirectUris,
            clientName: clientName,
            scope: scope,
            additionalMetadata: additionalMetadata
        )
        
        // Create credential storage (optional)
        let credentialStorage: DynamicClientCredentialStorage?
        if case .boolean(let useStorage) = configDict["useCredentialStorage"], useStorage {
            credentialStorage = DefaultDynamicClientCredentialStorage()
        } else {
            credentialStorage = nil
        }
        
        return DynamicClientRegistrationAuthProvider(
            registrationConfig: registrationConfig,
            registrationRequest: registrationRequest,
            softwareStatement: softwareStatement,
            credentialStorage: credentialStorage
        )
    }
}
