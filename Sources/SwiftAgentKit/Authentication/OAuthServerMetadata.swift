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
        case revocationEndpoint = "revocation_endpoint"
        case introspectionEndpoint = "introspection_endpoint"
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
    
    private let logger = Logger(label: "OAuthServerMetadataClient")
    private let urlSession: URLSession
    
    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }
    
    /// Discover OAuth server metadata from the well-known endpoint
    /// - Parameter issuerURL: The issuer URL (e.g., "https://auth.example.com")
    /// - Returns: OAuth server metadata
    /// - Throws: OAuthMetadataError if discovery fails
    public func discoverOAuthServerMetadata(issuerURL: URL) async throws -> OAuthServerMetadata {
        let wellKnownURL = issuerURL.appendingPathComponent(".well-known/oauth-authorization-server")
        
        logger.info("Discovering OAuth server metadata from: \(wellKnownURL)")
        
        do {
            let (data, response) = try await urlSession.data(from: wellKnownURL)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OAuthMetadataError.invalidResponse("Invalid response type")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                throw OAuthMetadataError.httpError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)")
            }
            
            let metadata = try JSONDecoder().decode(OAuthServerMetadata.self, from: data)
            
            logger.info("Successfully discovered OAuth server metadata")
            return metadata
            
        } catch let error as OAuthMetadataError {
            throw error
        } catch {
            logger.error("Failed to discover OAuth server metadata: \(error)")
            throw OAuthMetadataError.discoveryFailed(error.localizedDescription)
        }
    }
    
    /// Discover OpenID Connect provider metadata from the well-known endpoint
    /// - Parameter issuerURL: The issuer URL (e.g., "https://auth.example.com")
    /// - Returns: OpenID Connect provider metadata
    /// - Throws: OAuthMetadataError if discovery fails
    public func discoverOpenIDConnectProviderMetadata(issuerURL: URL) async throws -> OpenIDConnectProviderMetadata {
        let wellKnownURL = issuerURL.appendingPathComponent(".well-known/openid_configuration")
        
        logger.info("Discovering OpenID Connect provider metadata from: \(wellKnownURL)")
        
        do {
            let (data, response) = try await urlSession.data(from: wellKnownURL)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OAuthMetadataError.invalidResponse("Invalid response type")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                throw OAuthMetadataError.httpError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)")
            }
            
            let metadata = try JSONDecoder().decode(OpenIDConnectProviderMetadata.self, from: data)
            
            logger.info("Successfully discovered OpenID Connect provider metadata")
            return metadata
            
        } catch let error as OAuthMetadataError {
            throw error
        } catch {
            logger.error("Failed to discover OpenID Connect provider metadata: \(error)")
            throw OAuthMetadataError.discoveryFailed(error.localizedDescription)
        }
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
