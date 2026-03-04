//
//  OAuthServerMetadata.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Foundation
import Logging

/// OAuth 2.0 Authorization Server Metadata as per RFC 8414
public struct OAuthServerMetadata: Sendable, Codable {
    /// The authorization server's issuer identifier
    public let issuer: String?
    
    /// URL of the authorization server's authorization endpoint
    public let authorizationEndpoint: String?
    
    /// URL of the authorization server's token endpoint
    public let tokenEndpoint: String?
    
    /// JSON array containing a list of client authentication methods supported by this token endpoint
    public let tokenEndpointAuthMethodsSupported: [String]?
    
    /// JSON array containing a list of the OAuth 2.0 "grant_type" values that this authorization server supports
    public let grantTypesSupported: [String]?
    
    /// JSON array containing a list of PKCE code challenge methods supported
    /// This is required by MCP spec - clients MUST verify this field is present
    public let codeChallengeMethodsSupported: [String]?
    
    /// JSON array containing a list of the OAuth 2.0 "response_type" values that this authorization server supports
    public let responseTypesSupported: [String]?
    
    /// JSON array containing a list of the OAuth 2.0 "response_mode" values that this authorization server supports
    public let responseModesSupported: [String]?
    
    /// JSON array containing a list of the OAuth 2.0 "scope" values that this authorization server supports
    public let scopesSupported: [String]?
    
    /// URL of the authorization server's JWK Set document
    public let jwksUri: String?
    
    /// URL of the authorization server's userinfo endpoint
    public let userinfoEndpoint: String?
    
    /// JSON array containing a list of the OAuth 2.0 "client_id" values that this authorization server supports
    public let subjectTypesSupported: [String]?
    
    /// JSON array containing a list of the JWS signing algorithms (alg values) supported by the authorization server for the content of the JWT used to authenticate the client at the token endpoint
    public let tokenEndpointAuthSigningAlgValuesSupported: [String]?
    
    /// URL of the authorization server's registration endpoint
    public let registrationEndpoint: String?
    
    /// JSON array containing a list of client authentication methods supported by this registration endpoint
    public let registrationEndpointAuthMethodsSupported: [String]?
    
    /// JSON array containing a list of the client metadata fields that the authorization server supports
    public let registrationEndpointFieldsSupported: [String]?
    
    /// JSON array containing a list of the software statement fields that the authorization server supports
    public let softwareStatementFieldsSupported: [String]?
    
    /// URL of the authorization server's revocation endpoint
    public let revocationEndpoint: String?
    
    /// URL of the authorization server's introspection endpoint
    public let introspectionEndpoint: String?
    
    
    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
        case grantTypesSupported = "grant_types_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case responseTypesSupported = "response_types_supported"
        case responseModesSupported = "response_modes_supported"
        case scopesSupported = "scopes_supported"
        case jwksUri = "jwks_uri"
        case userinfoEndpoint = "userinfo_endpoint"
        case subjectTypesSupported = "subject_types_supported"
        case tokenEndpointAuthSigningAlgValuesSupported = "token_endpoint_auth_signing_alg_values_supported"
        case registrationEndpoint = "registration_endpoint"
        case registrationEndpointAuthMethodsSupported = "registration_endpoint_auth_methods_supported"
        case registrationEndpointFieldsSupported = "registration_endpoint_fields_supported"
        case softwareStatementFieldsSupported = "software_statement_fields_supported"
        case revocationEndpoint = "revocation_endpoint"
        case introspectionEndpoint = "introspection_endpoint"
    }
    
    public init(
        issuer: String? = nil,
        authorizationEndpoint: String? = nil,
        tokenEndpoint: String? = nil,
        tokenEndpointAuthMethodsSupported: [String]? = nil,
        grantTypesSupported: [String]? = nil,
        codeChallengeMethodsSupported: [String]? = nil,
        responseTypesSupported: [String]? = nil,
        responseModesSupported: [String]? = nil,
        scopesSupported: [String]? = nil,
        jwksUri: String? = nil,
        userinfoEndpoint: String? = nil,
        subjectTypesSupported: [String]? = nil,
        tokenEndpointAuthSigningAlgValuesSupported: [String]? = nil,
        registrationEndpoint: String? = nil,
        registrationEndpointAuthMethodsSupported: [String]? = nil,
        registrationEndpointFieldsSupported: [String]? = nil,
        softwareStatementFieldsSupported: [String]? = nil,
        revocationEndpoint: String? = nil,
        introspectionEndpoint: String? = nil
    ) {
        self.issuer = issuer
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.tokenEndpointAuthMethodsSupported = tokenEndpointAuthMethodsSupported
        self.grantTypesSupported = grantTypesSupported
        self.codeChallengeMethodsSupported = codeChallengeMethodsSupported
        self.responseTypesSupported = responseTypesSupported
        self.responseModesSupported = responseModesSupported
        self.scopesSupported = scopesSupported
        self.jwksUri = jwksUri
        self.userinfoEndpoint = userinfoEndpoint
        self.subjectTypesSupported = subjectTypesSupported
        self.tokenEndpointAuthSigningAlgValuesSupported = tokenEndpointAuthSigningAlgValuesSupported
        self.registrationEndpoint = registrationEndpoint
        self.registrationEndpointAuthMethodsSupported = registrationEndpointAuthMethodsSupported
        self.registrationEndpointFieldsSupported = registrationEndpointFieldsSupported
        self.softwareStatementFieldsSupported = softwareStatementFieldsSupported
        self.revocationEndpoint = revocationEndpoint
        self.introspectionEndpoint = introspectionEndpoint
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.issuer = try container.decodeIfPresent(String.self, forKey: .issuer)
        self.authorizationEndpoint = try container.decodeIfPresent(String.self, forKey: .authorizationEndpoint)
        self.tokenEndpoint = try container.decodeIfPresent(String.self, forKey: .tokenEndpoint)
        self.tokenEndpointAuthMethodsSupported = try container.decodeIfPresent([String].self, forKey: .tokenEndpointAuthMethodsSupported)
        self.grantTypesSupported = try container.decodeIfPresent([String].self, forKey: .grantTypesSupported)
        self.codeChallengeMethodsSupported = try container.decodeIfPresent([String].self, forKey: .codeChallengeMethodsSupported)
        self.responseTypesSupported = try container.decodeIfPresent([String].self, forKey: .responseTypesSupported)
        self.responseModesSupported = try container.decodeIfPresent([String].self, forKey: .responseModesSupported)
        self.scopesSupported = try container.decodeIfPresent([String].self, forKey: .scopesSupported)
        self.jwksUri = try container.decodeIfPresent(String.self, forKey: .jwksUri)
        self.userinfoEndpoint = try container.decodeIfPresent(String.self, forKey: .userinfoEndpoint)
        self.subjectTypesSupported = try container.decodeIfPresent([String].self, forKey: .subjectTypesSupported)
        self.tokenEndpointAuthSigningAlgValuesSupported = try container.decodeIfPresent([String].self, forKey: .tokenEndpointAuthSigningAlgValuesSupported)
        self.registrationEndpoint = try container.decodeIfPresent(String.self, forKey: .registrationEndpoint)
        self.registrationEndpointAuthMethodsSupported = try container.decodeIfPresent([String].self, forKey: .registrationEndpointAuthMethodsSupported)
        self.registrationEndpointFieldsSupported = try container.decodeIfPresent([String].self, forKey: .registrationEndpointFieldsSupported)
        self.softwareStatementFieldsSupported = try container.decodeIfPresent([String].self, forKey: .softwareStatementFieldsSupported)
        self.revocationEndpoint = try container.decodeIfPresent(String.self, forKey: .revocationEndpoint)
        self.introspectionEndpoint = try container.decodeIfPresent(String.self, forKey: .introspectionEndpoint)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(issuer, forKey: .issuer)
        try container.encodeIfPresent(authorizationEndpoint, forKey: .authorizationEndpoint)
        try container.encodeIfPresent(tokenEndpoint, forKey: .tokenEndpoint)
        try container.encodeIfPresent(tokenEndpointAuthMethodsSupported, forKey: .tokenEndpointAuthMethodsSupported)
        try container.encodeIfPresent(grantTypesSupported, forKey: .grantTypesSupported)
        try container.encodeIfPresent(codeChallengeMethodsSupported, forKey: .codeChallengeMethodsSupported)
        try container.encodeIfPresent(responseTypesSupported, forKey: .responseTypesSupported)
        try container.encodeIfPresent(responseModesSupported, forKey: .responseModesSupported)
        try container.encodeIfPresent(scopesSupported, forKey: .scopesSupported)
        try container.encodeIfPresent(jwksUri, forKey: .jwksUri)
        try container.encodeIfPresent(userinfoEndpoint, forKey: .userinfoEndpoint)
        try container.encodeIfPresent(subjectTypesSupported, forKey: .subjectTypesSupported)
        try container.encodeIfPresent(tokenEndpointAuthSigningAlgValuesSupported, forKey: .tokenEndpointAuthSigningAlgValuesSupported)
        try container.encodeIfPresent(registrationEndpoint, forKey: .registrationEndpoint)
        try container.encodeIfPresent(registrationEndpointAuthMethodsSupported, forKey: .registrationEndpointAuthMethodsSupported)
        try container.encodeIfPresent(registrationEndpointFieldsSupported, forKey: .registrationEndpointFieldsSupported)
        try container.encodeIfPresent(softwareStatementFieldsSupported, forKey: .softwareStatementFieldsSupported)
        try container.encodeIfPresent(revocationEndpoint, forKey: .revocationEndpoint)
        try container.encodeIfPresent(introspectionEndpoint, forKey: .introspectionEndpoint)
    }
    
    /// Validate that the authorization server supports PKCE as required by MCP spec
    /// - Returns: True if PKCE is supported, false otherwise
    /// - Throws: OAuthMetadataError if PKCE support cannot be determined
    public func validatePKCESupport() throws -> Bool {
        guard let codeChallengeMethods = codeChallengeMethodsSupported else {
            throw OAuthMetadataError.pkceNotSupported("code_challenge_methods_supported field is absent from authorization server metadata")
        }
        
        guard !codeChallengeMethods.isEmpty else {
            throw OAuthMetadataError.pkceNotSupported("code_challenge_methods_supported array is empty")
        }
        
        // MCP spec requires S256 method support
        guard codeChallengeMethods.contains("S256") else {
            throw OAuthMetadataError.pkceNotSupported("Authorization server does not support S256 code challenge method")
        }
        
        return true
    }
    
    /// Check if the authorization server supports authorization code grant type
    /// - Returns: True if authorization code grant is supported
    public func supportsAuthorizationCodeGrant() -> Bool {
        return grantTypesSupported?.contains("authorization_code") ?? false
    }
    
    /// Check if the authorization server supports public client authentication
    /// - Returns: True if public client authentication is supported
    public func supportsPublicClientAuthentication() -> Bool {
        return tokenEndpointAuthMethodsSupported?.contains("none") ?? false
    }
}


/// OpenID Connect Provider Metadata (extends OAuth Server Metadata)
public struct OpenIDConnectProviderMetadata: Sendable, Codable {
    /// Base OAuth server metadata
    public let oauthMetadata: OAuthServerMetadata
    
    /// URL of the OpenID Connect Provider's UserInfo Endpoint
    public let userinfoEndpoint: String?
    
    /// JSON array containing a list of the Claim Names of the Claims that the OpenID Connect Provider MAY be able to supply values for
    public let claimsSupported: [String]?
    
    /// JSON array containing a list of the Claim Types that the OpenID Connect Provider supports
    public let claimTypesSupported: [String]?
    
    /// JSON array containing a list of the OAuth 2.0 "response_type" values that this OpenID Connect Provider supports
    public let responseTypesSupported: [String]?
    
    /// JSON array containing a list of the Subject Identifier types that this OpenID Connect Provider supports
    public let subjectTypesSupported: [String]?
    
    /// JSON array containing a list of the OAuth 2.0 "response_mode" values that this OpenID Connect Provider supports
    public let responseModesSupported: [String]?
    
    enum CodingKeys: String, CodingKey {
        case userinfoEndpoint = "userinfo_endpoint"
        case claimsSupported = "claims_supported"
        case claimTypesSupported = "claim_types_supported"
        case responseTypesSupported = "response_types_supported"
        case subjectTypesSupported = "subject_types_supported"
        case responseModesSupported = "response_modes_supported"
    }
    
    public init(from decoder: Decoder) throws {
        // First decode the base OAuth metadata
        self.oauthMetadata = try OAuthServerMetadata(from: decoder)
        
        // Then decode OpenID Connect specific fields
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.userinfoEndpoint = try container.decodeIfPresent(String.self, forKey: .userinfoEndpoint)
        self.claimsSupported = try container.decodeIfPresent([String].self, forKey: .claimsSupported)
        self.claimTypesSupported = try container.decodeIfPresent([String].self, forKey: .claimTypesSupported)
        self.responseTypesSupported = try container.decodeIfPresent([String].self, forKey: .responseTypesSupported)
        self.subjectTypesSupported = try container.decodeIfPresent([String].self, forKey: .subjectTypesSupported)
        self.responseModesSupported = try container.decodeIfPresent([String].self, forKey: .responseModesSupported)
    }
    
    public func encode(to encoder: Encoder) throws {
        // Encode base OAuth metadata first
        try oauthMetadata.encode(to: encoder)
        
        // Then encode OpenID Connect specific fields
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(userinfoEndpoint, forKey: .userinfoEndpoint)
        try container.encodeIfPresent(claimsSupported, forKey: .claimsSupported)
        try container.encodeIfPresent(claimTypesSupported, forKey: .claimTypesSupported)
        try container.encodeIfPresent(responseTypesSupported, forKey: .responseTypesSupported)
        try container.encodeIfPresent(subjectTypesSupported, forKey: .subjectTypesSupported)
        try container.encodeIfPresent(responseModesSupported, forKey: .responseModesSupported)
    }
    
    /// Validate that the OpenID Connect provider supports PKCE
    /// This includes checking the code_challenge_methods_supported field as required by MCP spec
    /// - Returns: True if PKCE is supported
    /// - Throws: OAuthMetadataError if PKCE support cannot be determined
    public func validatePKCESupport() throws -> Bool {
        return try oauthMetadata.validatePKCESupport()
    }
}

/// OAuth server metadata discovery client
public actor OAuthServerMetadataClient {
    
    private let logger: Logger
    private let urlSession: URLSession
    
    public init(
        urlSession: URLSession,
        logger: Logger?
    ) {
        self.urlSession = urlSession
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .authentication("OAuthServerMetadataClient")
        )
    }
    
    public init(urlSession: URLSession = .shared) {
        self.init(urlSession: urlSession, logger: nil)
    }
    
    /// Generate MCP-compliant well-known discovery URLs for an issuer
    /// - Parameter issuerURL: The issuer URL
    /// - Returns: Array of discovery URLs in priority order as per MCP spec
    private func generateDiscoveryURLs(for issuerURL: URL) -> [URL] {
        var discoveryURLs: [URL] = []
        
        let pathComponents = issuerURL.pathComponents.filter { $0 != "/" }
        let hasPathComponents = !pathComponents.isEmpty
        
        if hasPathComponents {
            // For issuer URLs with path components (e.g., https://auth.example.com/tenant1)
            // Priority order as per MCP spec:
            
            // 1. OAuth 2.0 Authorization Server Metadata with path insertion:
            //    https://auth.example.com/.well-known/oauth-authorization-server/tenant1
            if let oauthPathInsertionURL = constructPathInsertionURL(
                issuerURL: issuerURL,
                wellKnownPath: ".well-known/oauth-authorization-server"
            ) {
                discoveryURLs.append(oauthPathInsertionURL)
            }
            
            // 2. OpenID Connect Discovery 1.0 with path insertion:
            //    https://auth.example.com/.well-known/openid-configuration/tenant1
            if let oidcPathInsertionURL = constructPathInsertionURL(
                issuerURL: issuerURL,
                wellKnownPath: ".well-known/openid-configuration"
            ) {
                discoveryURLs.append(oidcPathInsertionURL)
            }
            
            // 3. OpenID Connect Discovery 1.0 path appending:
            //    https://auth.example.com/tenant1/.well-known/openid-configuration
            let oidcPathAppendingURL = issuerURL.appendingPathComponent(".well-known/openid-configuration")
            discoveryURLs.append(oidcPathAppendingURL)
            
        } else {
            // For issuer URLs without path components (e.g., https://auth.example.com)
            
            // 1. OAuth 2.0 Authorization Server Metadata:
            //    https://auth.example.com/.well-known/oauth-authorization-server
            let oauthURL = issuerURL.appendingPathComponent(".well-known/oauth-authorization-server")
            discoveryURLs.append(oauthURL)
            
            // 2. OpenID Connect Discovery 1.0:
            //    https://auth.example.com/.well-known/openid-configuration
            let oidcURL = issuerURL.appendingPathComponent(".well-known/openid-configuration")
            discoveryURLs.append(oidcURL)
        }
        
        return discoveryURLs
    }
    
    /// Construct a path insertion URL for well-known endpoints
    /// - Parameters:
    ///   - issuerURL: The original issuer URL
    ///   - wellKnownPath: The well-known path (e.g., ".well-known/oauth-authorization-server")
    /// - Returns: URL with path components inserted after the well-known path
    private func constructPathInsertionURL(issuerURL: URL, wellKnownPath: String) -> URL? {
        guard var components = URLComponents(url: issuerURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        // Extract the path components from the issuer URL (excluding root "/")
        let originalPathComponents = issuerURL.pathComponents.filter { $0 != "/" }
        
        // Build the new path: /.well-known/endpoint/path1/path2/...
        let wellKnownComponents = wellKnownPath.split(separator: "/").map(String.init)
        let pathComponents = wellKnownComponents + originalPathComponents
        
        // Join path components properly with leading slash
        components.path = "/" + pathComponents.joined(separator: "/")
        
        return components.url
    }
    
    /// Discover OAuth server metadata from a specific well-known endpoint
    /// - Parameter wellKnownURL: The well-known endpoint URL
    /// - Returns: OAuth server metadata
    /// - Throws: OAuthMetadataError if discovery fails
    private func fetchOAuthServerMetadata(from wellKnownURL: URL) async throws -> OAuthServerMetadata {
        logger.debug(
            "Attempting to fetch OAuth server metadata",
            metadata: ["url": .string(wellKnownURL.absoluteString)]
        )
        
        let (data, response) = try await urlSession.data(from: wellKnownURL)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthMetadataError.invalidResponse("Invalid response type")
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw OAuthMetadataError.httpError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)")
        }
        
        let metadata = try JSONDecoder().decode(OAuthServerMetadata.self, from: data)
        logger.info(
            "Successfully fetched OAuth server metadata",
            metadata: ["url": .string(wellKnownURL.absoluteString)]
        )
        return metadata
    }
    
    /// Discover OpenID Connect provider metadata from a specific well-known endpoint
    /// - Parameter wellKnownURL: The well-known endpoint URL
    /// - Returns: OpenID Connect provider metadata
    /// - Throws: OAuthMetadataError if discovery fails
    private func fetchOpenIDConnectProviderMetadata(from wellKnownURL: URL) async throws -> OpenIDConnectProviderMetadata {
        logger.debug(
            "Attempting to fetch OpenID Connect provider metadata",
            metadata: ["url": .string(wellKnownURL.absoluteString)]
        )
        
        let (data, response) = try await urlSession.data(from: wellKnownURL)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthMetadataError.invalidResponse("Invalid response type")
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw OAuthMetadataError.httpError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)")
        }
        
        let metadata = try JSONDecoder().decode(OpenIDConnectProviderMetadata.self, from: data)
        logger.info(
            "Successfully fetched OpenID Connect provider metadata",
            metadata: ["url": .string(wellKnownURL.absoluteString)]
        )
        return metadata
    }
    
    /// Discover OAuth server metadata from the well-known endpoint (RFC 8414)
    /// - Parameter issuerURL: The issuer URL (e.g., "https://auth.example.com")
    /// - Returns: OAuth server metadata
    /// - Throws: OAuthMetadataError if discovery fails
    public func discoverOAuthServerMetadata(issuerURL: URL) async throws -> OAuthServerMetadata {
        // For backward compatibility, use the first OAuth 2.0 endpoint from MCP-compliant discovery
        let discoveryURLs = generateDiscoveryURLs(for: issuerURL)
        let oauthURLs = discoveryURLs.filter { $0.path.contains("oauth-authorization-server") }
        
        guard let firstOAuthURL = oauthURLs.first else {
            throw OAuthMetadataError.discoveryFailed("No OAuth 2.0 discovery URL could be generated")
        }
        
        logger.info(
            "Discovering OAuth server metadata",
            metadata: ["url": .string(firstOAuthURL.absoluteString)]
        )
        
        do {
            return try await fetchOAuthServerMetadata(from: firstOAuthURL)
        } catch let error as OAuthMetadataError {
            throw error
        } catch {
            logger.error(
                "Failed to discover OAuth server metadata",
                metadata: ["error": .string(String(describing: error))]
            )
            throw OAuthMetadataError.discoveryFailed(error.localizedDescription)
        }
    }
    
    /// Discover OpenID Connect provider metadata from the well-known endpoint
    /// - Parameter issuerURL: The issuer URL (e.g., "https://auth.example.com")
    /// - Returns: OpenID Connect provider metadata
    /// - Throws: OAuthMetadataError if discovery fails
    public func discoverOpenIDConnectProviderMetadata(issuerURL: URL) async throws -> OpenIDConnectProviderMetadata {
        // For backward compatibility, use the first OIDC endpoint from MCP-compliant discovery
        let discoveryURLs = generateDiscoveryURLs(for: issuerURL)
        let oidcURLs = discoveryURLs.filter { $0.path.contains("openid-configuration") }
        
        guard let firstOidcURL = oidcURLs.first else {
            throw OAuthMetadataError.discoveryFailed("No OpenID Connect discovery URL could be generated")
        }
        
        logger.info(
            "Discovering OpenID Connect provider metadata",
            metadata: ["url": .string(firstOidcURL.absoluteString)]
        )
        
        do {
            return try await fetchOpenIDConnectProviderMetadata(from: firstOidcURL)
        } catch let error as OAuthMetadataError {
            throw error
        } catch {
            logger.error(
                "Failed to discover OpenID Connect provider metadata",
                metadata: ["error": .string(String(describing: error))]
            )
            throw OAuthMetadataError.discoveryFailed(error.localizedDescription)
        }
    }
    
    /// Discover authorization server metadata with MCP-compliant priority ordering
    /// Implements the full MCP specification for authorization server metadata discovery
    /// - Parameter issuerURL: The issuer URL (e.g., "https://auth.example.com")
    /// - Returns: OAuth server metadata (from the first successful endpoint)
    /// - Throws: OAuthMetadataError if all discovery methods fail
    public func discoverAuthorizationServerMetadata(issuerURL: URL) async throws -> OAuthServerMetadata {
        logger.info(
            "Discovering authorization server metadata with MCP-compliant priority ordering",
            metadata: ["issuerURL": .string(issuerURL.absoluteString)]
        )
        
        let discoveryURLs = generateDiscoveryURLs(for: issuerURL)
        var lastError: Error?
        
        for (index, discoveryURL) in discoveryURLs.enumerated() {
            do {
                logger.debug(
                    "Trying discovery endpoint",
                    metadata: [
                        "index": .stringConvertible(index + 1),
                        "total": .stringConvertible(discoveryURLs.count),
                        "url": .string(discoveryURL.absoluteString)
                    ]
                )
                
                if discoveryURL.path.contains("oauth-authorization-server") {
                    // OAuth 2.0 Authorization Server Metadata endpoint
                    let metadata = try await fetchOAuthServerMetadata(from: discoveryURL)
                    logger.info(
                        "Successfully discovered authorization server metadata via OAuth 2.0",
                        metadata: ["url": .string(discoveryURL.absoluteString)]
                    )
                    return metadata
                } else if discoveryURL.path.contains("openid-configuration") {
                    // OpenID Connect Discovery endpoint
                    let oidcMetadata = try await fetchOpenIDConnectProviderMetadata(from: discoveryURL)
                    logger.info(
                        "Successfully discovered authorization server metadata via OpenID Connect",
                        metadata: ["url": .string(discoveryURL.absoluteString)]
                    )
                    return oidcMetadata.oauthMetadata
                }
                
            } catch let error as OAuthMetadataError {
                if case .httpError(let statusCode, _) = error, statusCode == 404 {
                    logger.debug(
                        "Discovery endpoint not found (404)",
                        metadata: ["url": .string(discoveryURL.absoluteString)]
                    )
                } else {
                    logger.warning(
                        "Discovery failed for endpoint",
                        metadata: [
                            "url": .string(discoveryURL.absoluteString),
                            "error": .string(String(describing: error))
                        ]
                    )
                }
                lastError = error
            } catch {
                logger.warning(
                    "Discovery failed for endpoint with unexpected error",
                    metadata: [
                        "url": .string(discoveryURL.absoluteString),
                        "error": .string(String(describing: error))
                    ]
                )
                lastError = error
            }
        }
        
        logger.error("All MCP-compliant discovery endpoints failed")
        let errorMessage = lastError?.localizedDescription ?? "All discovery endpoints failed"
        throw OAuthMetadataError.discoveryFailed("Failed to discover authorization server metadata using MCP-compliant discovery: \(errorMessage)")
    }
    
    /// Discover authorization server metadata from protected resource metadata
    /// - Parameter protectedResourceMetadata: The protected resource metadata containing authorization server info
    /// - Returns: OAuth server metadata from the authorization server
    /// - Throws: OAuthMetadataError if discovery fails
    public func discoverFromProtectedResourceMetadata(_ protectedResourceMetadata: ProtectedResourceMetadata) async throws -> OAuthServerMetadata {
        guard let authorizationServerURL = protectedResourceMetadata.authorizationServerURL() else {
            throw OAuthMetadataError.invalidIssuerURL("No authorization server URL found in protected resource metadata")
        }
        
        logger.info(
            "Discovering authorization server metadata from protected resource metadata",
            metadata: ["authorizationServerURL": .string(authorizationServerURL.absoluteString)]
        )
        
        return try await discoverAuthorizationServerMetadata(issuerURL: authorizationServerURL)
    }
}

/// OAuth metadata discovery errors
public enum OAuthMetadataError: LocalizedError, Sendable {
    case discoveryFailed(String)
    case invalidResponse(String)
    case httpError(Int, String)
    case pkceNotSupported(String)
    case invalidIssuerURL(String)
    
    public var errorDescription: String? {
        switch self {
        case .discoveryFailed(let message):
            return "OAuth metadata discovery failed: \(message)"
        case .invalidResponse(let message):
            return "Invalid response from authorization server: \(message)"
        case .httpError(let code, let message):
            return "HTTP error \(code): \(message)"
        case .pkceNotSupported(let message):
            return "PKCE not supported: \(message)"
        case .invalidIssuerURL(let message):
            return "Invalid issuer URL: \(message)"
        }
    }
}
