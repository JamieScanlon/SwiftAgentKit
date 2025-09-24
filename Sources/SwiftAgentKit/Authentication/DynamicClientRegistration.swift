//
//  DynamicClientRegistration.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Foundation
import Logging

/// OAuth 2.0 Dynamic Client Registration models as per RFC 7591
public struct DynamicClientRegistration {
    
    /// Client registration request metadata
    public struct ClientRegistrationRequest: Sendable, Codable {
        /// Array of redirection URI strings for use in redirect-based flows
        public let redirectUris: [String]
        
        /// Kind of the application (e.g., "web", "native", "mobile")
        public let applicationType: String?
        
        /// OAuth 2.0 client identifier URI
        public let clientUri: String?
        
        /// Array of strings representing ways to contact people responsible for this client
        public let contacts: [String]?
        
        /// Name of the client to be presented to the end-user
        public let clientName: String?
        
        /// URL that references a logo for the client application
        public let logoUri: String?
        
        /// URL of the home page of the client
        public let tosUri: String?
        
        /// URL that the Relying Party client provides to the End-User to read about the Relying Party's terms of service
        public let policyUri: String?
        
        /// URL for the client's JSON Web Key Set document
        public let jwksUri: String?
        
        /// Client's JSON Web Key Set document
        public let jwks: String?
        
        /// OAuth 2.0 client authentication method for the token endpoint
        public let tokenEndpointAuthMethod: String?
        
        /// Array of OAuth 2.0 grant type strings that the client can use
        public let grantTypes: [String]?
        
        /// Array of the OAuth 2.0 response type strings that the client can use
        public let responseTypes: [String]?
        
        /// String containing a space-separated list of scope values
        public let scope: String?
        
        /// Additional metadata fields
        public let additionalMetadata: [String: String]?
        
        enum CodingKeys: String, CodingKey {
            case redirectUris = "redirect_uris"
            case applicationType = "application_type"
            case clientUri = "client_uri"
            case contacts
            case clientName = "client_name"
            case logoUri = "logo_uri"
            case tosUri = "tos_uri"
            case policyUri = "policy_uri"
            case jwksUri = "jwks_uri"
            case jwks
            case tokenEndpointAuthMethod = "token_endpoint_auth_method"
            case grantTypes = "grant_types"
            case responseTypes = "response_types"
            case scope
            case additionalMetadata
        }
        
        public init(
            redirectUris: [String],
            applicationType: String? = nil,
            clientUri: String? = nil,
            contacts: [String]? = nil,
            clientName: String? = nil,
            logoUri: String? = nil,
            tosUri: String? = nil,
            policyUri: String? = nil,
            jwksUri: String? = nil,
            jwks: String? = nil,
            tokenEndpointAuthMethod: String? = nil,
            grantTypes: [String]? = nil,
            responseTypes: [String]? = nil,
            scope: String? = nil,
            additionalMetadata: [String: String]? = nil
        ) {
            self.redirectUris = redirectUris
            self.applicationType = applicationType
            self.clientUri = clientUri
            self.contacts = contacts
            self.clientName = clientName
            self.logoUri = logoUri
            self.tosUri = tosUri
            self.policyUri = policyUri
            self.jwksUri = jwksUri
            self.jwks = jwks
            self.tokenEndpointAuthMethod = tokenEndpointAuthMethod
            self.grantTypes = grantTypes
            self.responseTypes = responseTypes
            self.scope = scope
            self.additionalMetadata = additionalMetadata
        }
        
        /// Creates a registration request optimized for MCP clients
        public static func mcpClientRequest(
            redirectUris: [String],
            clientName: String? = nil,
            scope: String? = nil,
            additionalMetadata: [String: String]? = nil
        ) -> ClientRegistrationRequest {
            return ClientRegistrationRequest(
                redirectUris: redirectUris,
                applicationType: "native", // MCP clients are typically native applications
                clientName: clientName ?? "MCP Client",
                tokenEndpointAuthMethod: "none", // PKCE clients use "none" for token endpoint auth
                grantTypes: ["authorization_code", "refresh_token"],
                responseTypes: ["code"],
                scope: scope ?? "mcp", // Default scope for MCP clients
                additionalMetadata: additionalMetadata
            )
        }
    }
    
    /// Client registration response
    public struct ClientRegistrationResponse: Sendable, Codable {
        /// OAuth 2.0 client identifier
        public let clientId: String
        
        /// OAuth 2.0 client secret (if applicable)
        public let clientSecret: String?
        
        /// Time at which the client identifier was issued
        public let clientIdIssuedAt: Int?
        
        /// Time at which the client secret will expire
        public let clientSecretExpiresAt: Int?
        
        /// Array of redirection URI strings for use in redirect-based flows
        public let redirectUris: [String]?
        
        /// Kind of the application
        public let applicationType: String?
        
        /// OAuth 2.0 client identifier URI
        public let clientUri: String?
        
        /// Array of strings representing ways to contact people responsible for this client
        public let contacts: [String]?
        
        /// Name of the client to be presented to the end-user
        public let clientName: String?
        
        /// URL that references a logo for the client application
        public let logoUri: String?
        
        /// URL of the home page of the client
        public let tosUri: String?
        
        /// URL that the Relying Party client provides to the End-User to read about the Relying Party's terms of service
        public let policyUri: String?
        
        /// URL for the client's JSON Web Key Set document
        public let jwksUri: String?
        
        /// Client's JSON Web Key Set document
        public let jwks: String?
        
        /// OAuth 2.0 client authentication method for the token endpoint
        public let tokenEndpointAuthMethod: String?
        
        /// Array of OAuth 2.0 grant type strings that the client can use
        public let grantTypes: [String]?
        
        /// Array of the OAuth 2.0 response type strings that the client can use
        public let responseTypes: [String]?
        
        /// String containing a space-separated list of scope values
        public let scope: String?
        
        /// Additional metadata fields
        public let additionalMetadata: [String: String]?
        
        enum CodingKeys: String, CodingKey {
            case clientId = "client_id"
            case clientSecret = "client_secret"
            case clientIdIssuedAt = "client_id_issued_at"
            case clientSecretExpiresAt = "client_secret_expires_at"
            case redirectUris = "redirect_uris"
            case applicationType = "application_type"
            case clientUri = "client_uri"
            case contacts
            case clientName = "client_name"
            case logoUri = "logo_uri"
            case tosUri = "tos_uri"
            case policyUri = "policy_uri"
            case jwksUri = "jwks_uri"
            case jwks
            case tokenEndpointAuthMethod = "token_endpoint_auth_method"
            case grantTypes = "grant_types"
            case responseTypes = "response_types"
            case scope
            case additionalMetadata
        }
        
        public init(
            clientId: String,
            clientSecret: String? = nil,
            clientIdIssuedAt: Int? = nil,
            clientSecretExpiresAt: Int? = nil,
            redirectUris: [String]? = nil,
            applicationType: String? = nil,
            clientUri: String? = nil,
            contacts: [String]? = nil,
            clientName: String? = nil,
            logoUri: String? = nil,
            tosUri: String? = nil,
            policyUri: String? = nil,
            jwksUri: String? = nil,
            jwks: String? = nil,
            tokenEndpointAuthMethod: String? = nil,
            grantTypes: [String]? = nil,
            responseTypes: [String]? = nil,
            scope: String? = nil,
            additionalMetadata: [String: String]? = nil
        ) {
            self.clientId = clientId
            self.clientSecret = clientSecret
            self.clientIdIssuedAt = clientIdIssuedAt
            self.clientSecretExpiresAt = clientSecretExpiresAt
            self.redirectUris = redirectUris
            self.applicationType = applicationType
            self.clientUri = clientUri
            self.contacts = contacts
            self.clientName = clientName
            self.logoUri = logoUri
            self.tosUri = tosUri
            self.policyUri = policyUri
            self.jwksUri = jwksUri
            self.jwks = jwks
            self.tokenEndpointAuthMethod = tokenEndpointAuthMethod
            self.grantTypes = grantTypes
            self.responseTypes = responseTypes
            self.scope = scope
            self.additionalMetadata = additionalMetadata
        }
    }
    
    /// Client registration error response
    public struct ClientRegistrationError: Sendable, Codable {
        /// Error code as per RFC 7591
        public let error: String
        
        /// Human-readable ASCII text providing additional information
        public let errorDescription: String?
        
        /// URI identifying a human-readable web page with information about the error
        public let errorUri: String?
        
        public init(error: String, errorDescription: String? = nil, errorUri: String? = nil) {
            self.error = error
            self.errorDescription = errorDescription
            self.errorUri = errorUri
        }
    }
    
    /// Standard error codes for client registration
    public enum RegistrationErrorCode: String, Sendable {
        case invalidRedirectUri = "invalid_redirect_uri"
        case invalidClientMetadata = "invalid_client_metadata"
        case invalidSoftwareStatement = "invalid_software_statement"
        case unapprovedSoftwareStatement = "unapproved_software_statement"
        case unsupportedGrantType = "unsupported_grant_type"
        case unsupportedResponseType = "unsupported_response_type"
        case invalidClientId = "invalid_client_id"
        case invalidClientSecret = "invalid_client_secret"
        case invalidRequest = "invalid_request"
        case accessDenied = "access_denied"
        case unsupportedTokenType = "unsupported_token_type"
        case invalidScope = "invalid_scope"
        case invalidGrant = "invalid_grant"
        case invalidRequestUri = "invalid_request_uri"
        case invalidRequestObject = "invalid_request_object"
        case requestUriNotSupported = "request_uri_not_supported"
        case requestNotSupported = "request_not_supported"
        case registrationNotSupported = "registration_not_supported"
    }
}

/// Configuration for Dynamic Client Registration
public struct DynamicClientRegistrationConfig: Sendable, Codable {
    /// URL of the authorization server's registration endpoint
    public let registrationEndpoint: URL
    
    /// Initial access token for registration (if required by the server)
    public let initialAccessToken: String?
    
    /// Client authentication method for registration requests
    public let registrationAuthMethod: String?
    
    /// Additional headers to include in registration requests
    public let additionalHeaders: [String: String]?
    
    /// Timeout for registration requests
    public let requestTimeout: TimeInterval?
    
    public init(
        registrationEndpoint: URL,
        initialAccessToken: String? = nil,
        registrationAuthMethod: String? = nil,
        additionalHeaders: [String: String]? = nil,
        requestTimeout: TimeInterval? = nil
    ) {
        self.registrationEndpoint = registrationEndpoint
        self.initialAccessToken = initialAccessToken
        self.registrationAuthMethod = registrationAuthMethod
        self.additionalHeaders = additionalHeaders
        self.requestTimeout = requestTimeout
    }
    
    /// Creates configuration from OAuth server metadata
    /// - Parameters:
    ///   - serverMetadata: OAuth server metadata containing registration endpoint
    ///   - initialAccessToken: Optional initial access token
    ///   - additionalHeaders: Optional additional headers
    /// - Returns: Dynamic client registration configuration
    public static func fromServerMetadata(
        _ serverMetadata: OAuthServerMetadata,
        initialAccessToken: String? = nil,
        additionalHeaders: [String: String]? = nil
    ) -> DynamicClientRegistrationConfig? {
        guard let registrationEndpointString = serverMetadata.registrationEndpoint,
              let registrationEndpoint = URL(string: registrationEndpointString) else {
            return nil
        }
        
        return DynamicClientRegistrationConfig(
            registrationEndpoint: registrationEndpoint,
            initialAccessToken: initialAccessToken,
            registrationAuthMethod: serverMetadata.registrationEndpointAuthMethodsSupported?.first,
            additionalHeaders: additionalHeaders
        )
    }
}

