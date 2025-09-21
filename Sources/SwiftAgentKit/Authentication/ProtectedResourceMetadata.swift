//
//  ProtectedResourceMetadata.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Foundation
import Logging

/// Protected Resource Metadata as per RFC 9728
public struct ProtectedResourceMetadata: Sendable, Codable {
    /// The authorization server's issuer identifier
    public let issuer: String?
    
    /// URL of the authorization server's authorization endpoint
    public let authorizationEndpoint: String?
    
    /// URL of the authorization server's token endpoint
    public let tokenEndpoint: String?
    
    /// URL of the authorization server's JWK Set document
    public let jwksUri: String?
    
    /// JSON array containing a list of client authentication methods supported by this token endpoint
    public let tokenEndpointAuthMethodsSupported: [String]?
    
    /// JSON array containing a list of the OAuth 2.0 "grant_type" values that this authorization server supports
    public let grantTypesSupported: [String]?
    
    /// JSON array containing a list of PKCE code challenge methods supported
    public let codeChallengeMethodsSupported: [String]?
    
    /// JSON array containing a list of the OAuth 2.0 "response_type" values that this authorization server supports
    public let responseTypesSupported: [String]?
    
    /// JSON array containing a list of the OAuth 2.0 "response_mode" values that this authorization server supports
    public let responseModesSupported: [String]?
    
    /// JSON array containing a list of the OAuth 2.0 "scope" values that this authorization server supports
    public let scopesSupported: [String]?
    
    /// URL of the authorization server's userinfo endpoint
    public let userinfoEndpoint: String?
    
    /// JSON array containing a list of the OAuth 2.0 "client_id" values that this authorization server supports
    public let subjectTypesSupported: [String]?
    
    /// JSON array containing a list of authorization server URLs (RFC 9728)
    public let authorizationServers: [String]?
    
    /// JSON array containing a list of the JWS signing algorithms (alg values) supported by the authorization server for the content of the JWT used to authenticate the client at the token endpoint
    public let tokenEndpointAuthSigningAlgValuesSupported: [String]?
    
    /// URL of the authorization server's revocation endpoint
    public let revocationEndpoint: String?
    
    /// URL of the authorization server's introspection endpoint
    public let introspectionEndpoint: String?
    
    /// The resource server's identifier
    public let resource: String?
    
    /// JSON array containing a list of the OAuth 2.0 authorization request parameters that the resource server accepts
    public let authorizationRequestParametersSupported: [String]?
    
    /// JSON array containing a list of the OAuth 2.0 authorization response parameters that the resource server accepts
    public let authorizationResponseParametersSupported: [String]?
    
    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case jwksUri = "jwks_uri"
        case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
        case grantTypesSupported = "grant_types_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case responseTypesSupported = "response_types_supported"
        case responseModesSupported = "response_modes_supported"
        case scopesSupported = "scopes_supported"
        case userinfoEndpoint = "userinfo_endpoint"
        case subjectTypesSupported = "subject_types_supported"
        case authorizationServers = "authorization_servers"
        case tokenEndpointAuthSigningAlgValuesSupported = "token_endpoint_auth_signing_alg_values_supported"
        case revocationEndpoint = "revocation_endpoint"
        case introspectionEndpoint = "introspection_endpoint"
        case resource
        case authorizationRequestParametersSupported = "authorization_request_parameters_supported"
        case authorizationResponseParametersSupported = "authorization_response_parameters_supported"
    }
    
    public init(
        issuer: String? = nil,
        authorizationEndpoint: String? = nil,
        tokenEndpoint: String? = nil,
        jwksUri: String? = nil,
        tokenEndpointAuthMethodsSupported: [String]? = nil,
        grantTypesSupported: [String]? = nil,
        codeChallengeMethodsSupported: [String]? = nil,
        responseTypesSupported: [String]? = nil,
        responseModesSupported: [String]? = nil,
        scopesSupported: [String]? = nil,
        userinfoEndpoint: String? = nil,
        subjectTypesSupported: [String]? = nil,
        authorizationServers: [String]? = nil,
        tokenEndpointAuthSigningAlgValuesSupported: [String]? = nil,
        revocationEndpoint: String? = nil,
        introspectionEndpoint: String? = nil,
        resource: String? = nil,
        authorizationRequestParametersSupported: [String]? = nil,
        authorizationResponseParametersSupported: [String]? = nil
    ) {
        self.issuer = issuer
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.jwksUri = jwksUri
        self.tokenEndpointAuthMethodsSupported = tokenEndpointAuthMethodsSupported
        self.grantTypesSupported = grantTypesSupported
        self.codeChallengeMethodsSupported = codeChallengeMethodsSupported
        self.responseTypesSupported = responseTypesSupported
        self.responseModesSupported = responseModesSupported
        self.scopesSupported = scopesSupported
        self.userinfoEndpoint = userinfoEndpoint
        self.subjectTypesSupported = subjectTypesSupported
        self.authorizationServers = authorizationServers
        self.tokenEndpointAuthSigningAlgValuesSupported = tokenEndpointAuthSigningAlgValuesSupported
        self.revocationEndpoint = revocationEndpoint
        self.introspectionEndpoint = introspectionEndpoint
        self.resource = resource
        self.authorizationRequestParametersSupported = authorizationRequestParametersSupported
        self.authorizationResponseParametersSupported = authorizationResponseParametersSupported
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.issuer = try container.decodeIfPresent(String.self, forKey: .issuer)
        self.authorizationEndpoint = try container.decodeIfPresent(String.self, forKey: .authorizationEndpoint)
        self.tokenEndpoint = try container.decodeIfPresent(String.self, forKey: .tokenEndpoint)
        self.jwksUri = try container.decodeIfPresent(String.self, forKey: .jwksUri)
        self.tokenEndpointAuthMethodsSupported = try container.decodeIfPresent([String].self, forKey: .tokenEndpointAuthMethodsSupported)
        self.grantTypesSupported = try container.decodeIfPresent([String].self, forKey: .grantTypesSupported)
        self.codeChallengeMethodsSupported = try container.decodeIfPresent([String].self, forKey: .codeChallengeMethodsSupported)
        self.responseTypesSupported = try container.decodeIfPresent([String].self, forKey: .responseTypesSupported)
        self.responseModesSupported = try container.decodeIfPresent([String].self, forKey: .responseModesSupported)
        self.scopesSupported = try container.decodeIfPresent([String].self, forKey: .scopesSupported)
        self.userinfoEndpoint = try container.decodeIfPresent(String.self, forKey: .userinfoEndpoint)
        self.subjectTypesSupported = try container.decodeIfPresent([String].self, forKey: .subjectTypesSupported)
        self.authorizationServers = try container.decodeIfPresent([String].self, forKey: .authorizationServers)
        self.tokenEndpointAuthSigningAlgValuesSupported = try container.decodeIfPresent([String].self, forKey: .tokenEndpointAuthSigningAlgValuesSupported)
        self.revocationEndpoint = try container.decodeIfPresent(String.self, forKey: .revocationEndpoint)
        self.introspectionEndpoint = try container.decodeIfPresent(String.self, forKey: .introspectionEndpoint)
        self.resource = try container.decodeIfPresent(String.self, forKey: .resource)
        self.authorizationRequestParametersSupported = try container.decodeIfPresent([String].self, forKey: .authorizationRequestParametersSupported)
        self.authorizationResponseParametersSupported = try container.decodeIfPresent([String].self, forKey: .authorizationResponseParametersSupported)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(issuer, forKey: .issuer)
        try container.encodeIfPresent(authorizationEndpoint, forKey: .authorizationEndpoint)
        try container.encodeIfPresent(tokenEndpoint, forKey: .tokenEndpoint)
        try container.encodeIfPresent(jwksUri, forKey: .jwksUri)
        try container.encodeIfPresent(tokenEndpointAuthMethodsSupported, forKey: .tokenEndpointAuthMethodsSupported)
        try container.encodeIfPresent(grantTypesSupported, forKey: .grantTypesSupported)
        try container.encodeIfPresent(codeChallengeMethodsSupported, forKey: .codeChallengeMethodsSupported)
        try container.encodeIfPresent(responseTypesSupported, forKey: .responseTypesSupported)
        try container.encodeIfPresent(responseModesSupported, forKey: .responseModesSupported)
        try container.encodeIfPresent(scopesSupported, forKey: .scopesSupported)
        try container.encodeIfPresent(userinfoEndpoint, forKey: .userinfoEndpoint)
        try container.encodeIfPresent(subjectTypesSupported, forKey: .subjectTypesSupported)
        try container.encodeIfPresent(authorizationServers, forKey: .authorizationServers)
        try container.encodeIfPresent(tokenEndpointAuthSigningAlgValuesSupported, forKey: .tokenEndpointAuthSigningAlgValuesSupported)
        try container.encodeIfPresent(revocationEndpoint, forKey: .revocationEndpoint)
        try container.encodeIfPresent(introspectionEndpoint, forKey: .introspectionEndpoint)
        try container.encodeIfPresent(resource, forKey: .resource)
        try container.encodeIfPresent(authorizationRequestParametersSupported, forKey: .authorizationRequestParametersSupported)
        try container.encodeIfPresent(authorizationResponseParametersSupported, forKey: .authorizationResponseParametersSupported)
    }
    
    /// Validate that the authorization server supports PKCE as required by MCP spec
    /// - Returns: True if PKCE is supported, false otherwise
    /// - Throws: ProtectedResourceMetadataError if PKCE support cannot be determined
    public func validatePKCESupport() throws -> Bool {
        guard let codeChallengeMethods = codeChallengeMethodsSupported else {
            throw ProtectedResourceMetadataError.pkceNotSupported("code_challenge_methods_supported field is absent from protected resource metadata")
        }
        
        guard !codeChallengeMethods.isEmpty else {
            throw ProtectedResourceMetadataError.pkceNotSupported("code_challenge_methods_supported array is empty")
        }
        
        // MCP spec requires S256 method support
        guard codeChallengeMethods.contains("S256") else {
            throw ProtectedResourceMetadataError.pkceNotSupported("Authorization server does not support S256 code challenge method")
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
    
    /// Extract the authorization server URL from the metadata
    /// Checks both the issuer field (RFC 8414) and authorization_servers array (RFC 9728)
    /// - Returns: URL of the authorization server or nil if not available
    public func authorizationServerURL() -> URL? {
        // First try the issuer field (RFC 8414 - OAuth 2.0 Authorization Server Metadata)
        if let issuer = issuer {
            return URL(string: issuer)
        }
        
        // Then try the authorization_servers array (RFC 9728 - OAuth 2.0 Protected Resource Metadata)
        if let authorizationServers = authorizationServers,
           let firstAuthServer = authorizationServers.first {
            return URL(string: firstAuthServer)
        }
        
        return nil
    }
}

/// WWW-Authenticate header parser for OAuth 2.0 challenges
public struct WWWAuthenticateParser {
    
    /// Parse WWW-Authenticate header to extract OAuth 2.0 challenge parameters
    /// - Parameter headerValue: The value of the WWW-Authenticate header
    /// - Returns: Dictionary of challenge parameters
    public static func parseWWWAuthenticateHeader(_ headerValue: String) -> [String: String] {
        var parameters: [String: String] = [:]
        
        // Split by comma to handle multiple challenges, but be careful about quoted values
        let challenges = splitChallenges(headerValue)
        
        // Process all challenges, looking for OAuth 2.0 schemes
        for challenge in challenges {
            // Check if this challenge has a scheme (starts with a known scheme)
            let challengeLower = challenge.lowercased()
            if challengeLower.hasPrefix("bearer ") || challengeLower.hasPrefix("oauth ") {
                // Extract scheme and parameters
                if let schemeEnd = challenge.firstIndex(of: " ") {
                    let _ = String(challenge[..<schemeEnd])
                    let paramsString = String(challenge[challenge.index(after: schemeEnd)...])
                    
                    let params = parseChallengeParameters(paramsString)
                    // Later challenges override earlier ones (last one wins)
                    for (key, value) in params {
                        parameters[key] = value
                    }
                }
            } else {
                // Challenge without scheme - only process if we've already seen an OAuth scheme
                if !parameters.isEmpty {
                    let params = parseChallengeParameters(challenge)
                    for (key, value) in params {
                        parameters[key] = value
                    }
                }
            }
        }
        
        return parameters
    }
    
    /// Split challenges while respecting quoted values
    private static func splitChallenges(_ headerValue: String) -> [String] {
        var challenges: [String] = []
        var currentChallenge = ""
        var inQuotes = false
        
        for char in headerValue {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                if !currentChallenge.isEmpty {
                    challenges.append(currentChallenge.trimmingCharacters(in: .whitespaces))
                    currentChallenge = ""
                }
                continue
            }
            currentChallenge.append(char)
        }
        
        if !currentChallenge.isEmpty {
            challenges.append(currentChallenge.trimmingCharacters(in: .whitespaces))
        }
        
        return challenges
    }
    
    /// Parse challenge parameters from a parameter string
    /// - Parameter paramsString: String containing key=value pairs
    /// - Returns: Dictionary of parsed parameters
    private static func parseChallengeParameters(_ paramsString: String) -> [String: String] {
        var parameters: [String: String] = [:]
        
        // Split by comma while respecting quoted values
        let pairs = splitParameters(paramsString)
        
        for pair in pairs {
            if let equalIndex = pair.firstIndex(of: "=") {
                let key = String(pair[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(pair[pair.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)
                
                // Remove quotes if present
                let cleanValue = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                parameters[key] = cleanValue
            }
        }
        
        return parameters
    }
    
    /// Split parameters while respecting quoted values
    private static func splitParameters(_ paramsString: String) -> [String] {
        var pairs: [String] = []
        var currentPair = ""
        var inQuotes = false
        
        for char in paramsString {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                if !currentPair.isEmpty {
                    pairs.append(currentPair.trimmingCharacters(in: .whitespaces))
                    currentPair = ""
                }
                continue
            }
            currentPair.append(char)
        }
        
        if !currentPair.isEmpty {
            pairs.append(currentPair.trimmingCharacters(in: .whitespaces))
        }
        
        return pairs
    }
}

/// Protected resource metadata discovery client
public actor ProtectedResourceMetadataClient {
    
    private let logger = Logger(label: "ProtectedResourceMetadataClient")
    private let urlSession: URLSession
    
    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }
    
    /// Discover protected resource metadata from WWW-Authenticate header
    /// - Parameter challenge: Authentication challenge containing WWW-Authenticate header
    /// - Returns: Protected resource metadata or nil if not available
    /// - Throws: ProtectedResourceMetadataError if discovery fails
    public func discoverFromWWWAuthenticateHeader(_ challenge: AuthenticationChallenge) async throws -> ProtectedResourceMetadata? {
        // Handle case-insensitive header lookup (same issue as in RemoteTransport)
        let wwwAuthenticateHeader = challenge.headers["WWW-Authenticate"] ??
                                  challenge.headers["Www-Authenticate"] ??
                                  challenge.headers["www-authenticate"]
        
        guard let wwwAuthenticateHeader = wwwAuthenticateHeader else {
            logger.debug("No WWW-Authenticate header found in challenge")
            return nil
        }
        
        logger.info("Parsing WWW-Authenticate header for resource metadata")
        
        let parameters = WWWAuthenticateParser.parseWWWAuthenticateHeader(wwwAuthenticateHeader)
        
        // Look for resource_metadata parameter
        guard let resourceMetadataURLString = parameters["resource_metadata"] else {
            logger.debug("No resource_metadata parameter found in WWW-Authenticate header")
            return nil
        }
        
        guard let resourceMetadataURL = URL(string: resourceMetadataURLString) else {
            throw ProtectedResourceMetadataError.invalidURL("Invalid resource_metadata URL: \(resourceMetadataURLString)")
        }
        
        logger.info("Found resource_metadata URL: \(resourceMetadataURL)")
        
        return try await fetchProtectedResourceMetadata(from: resourceMetadataURL)
    }
    
    /// Discover protected resource metadata using well-known URI probing
    /// - Parameters:
    ///   - baseURL: Base URL of the resource server
    ///   - resourceType: Type of resource (e.g., "mcp" for MCP servers)
    /// - Returns: Protected resource metadata or nil if not found
    /// - Throws: ProtectedResourceMetadataError if discovery fails
    public func discoverFromWellKnownURI(baseURL: URL, resourceType: String? = nil) async throws -> ProtectedResourceMetadata? {
        var urlsToTry: [URL] = []
        
        // Build URLs to try based on RFC 9728
        if let resourceType = resourceType {
            // Try sub-path first: /.well-known/oauth-protected-resource/{resourceType}
            let subPathURL = baseURL.appendingPathComponent(".well-known/oauth-protected-resource/\(resourceType)")
            urlsToTry.append(subPathURL)
        }
        
        // Try root path: /.well-known/oauth-protected-resource
        let rootPathURL = baseURL.appendingPathComponent(".well-known/oauth-protected-resource")
        urlsToTry.append(rootPathURL)
        
        logger.info("Attempting well-known URI discovery for base URL: \(baseURL)")
        
        for url in urlsToTry {
            logger.debug("Trying well-known URI: \(url)")
            
            do {
                let metadata = try await fetchProtectedResourceMetadata(from: url)
                logger.info("Successfully discovered protected resource metadata from: \(url)")
                return metadata
            } catch let error as ProtectedResourceMetadataError {
                if case .httpError(let statusCode, _) = error, statusCode == 404 {
                    logger.debug("Well-known URI not found: \(url) (404)")
                    continue // Try next URL
                } else {
                    throw error
                }
            } catch {
                logger.debug("Failed to fetch from well-known URI \(url): \(error)")
                continue // Try next URL
            }
        }
        
        logger.debug("No protected resource metadata found via well-known URIs")
        return nil
    }
    
    /// Fetch protected resource metadata from a specific URL
    /// - Parameter url: URL to fetch metadata from
    /// - Returns: Protected resource metadata
    /// - Throws: ProtectedResourceMetadataError if fetch fails
    private func fetchProtectedResourceMetadata(from url: URL) async throws -> ProtectedResourceMetadata {
        logger.debug("Fetching protected resource metadata from: \(url)")
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ProtectedResourceMetadataError.invalidResponse("Invalid response type")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                throw ProtectedResourceMetadataError.httpError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)")
            }
            
            let metadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: data)
            
            logger.info("Successfully fetched protected resource metadata")
            return metadata
            
        } catch let error as ProtectedResourceMetadataError {
            throw error
        } catch {
            logger.error("Failed to fetch protected resource metadata: \(error)")
            throw ProtectedResourceMetadataError.discoveryFailed(error.localizedDescription)
        }
    }
}

/// Protected resource metadata discovery errors
public enum ProtectedResourceMetadataError: LocalizedError, Sendable {
    case discoveryFailed(String)
    case invalidResponse(String)
    case httpError(Int, String)
    case pkceNotSupported(String)
    case invalidURL(String)
    case noAuthorizationServerURL
    
    public var errorDescription: String? {
        switch self {
        case .discoveryFailed(let message):
            return "Protected resource metadata discovery failed: \(message)"
        case .invalidResponse(let message):
            return "Invalid response from resource server: \(message)"
        case .httpError(let code, let message):
            return "HTTP error \(code): \(message)"
        case .pkceNotSupported(let message):
            return "PKCE not supported: \(message)"
        case .invalidURL(let message):
            return "Invalid URL: \(message)"
        case .noAuthorizationServerURL:
            return "No authorization server URL found in protected resource metadata"
        }
    }
}
