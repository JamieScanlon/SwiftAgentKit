//
//  AuthenticationProvider.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/20/25.
//

import Foundation
import Logging

/// Authentication schemes supported by the authentication system
public enum AuthenticationScheme: Sendable, Equatable {
    case bearer
    case basic  
    case apiKey
    case oauth
    case custom(String)
    
    public var rawValue: String {
        switch self {
        case .bearer: return "Bearer"
        case .basic: return "Basic"
        case .apiKey: return "ApiKey"
        case .oauth: return "OAuth"
        case .custom(let value): return value
        }
    }
    
    public init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "bearer", "token": self = .bearer
        case "basic": self = .basic
        case "apikey", "api_key": self = .apiKey
        case "oauth": self = .oauth
        default: self = .custom(rawValue)
        }
    }
}

/// Protocol for providing authentication credentials and handling auth flows for remote services
public protocol AuthenticationProvider: Sendable {
    
    /// The authentication scheme this provider handles
    var scheme: AuthenticationScheme { get }
    
    /// Provides authentication headers for HTTP requests
    /// - Returns: Dictionary of headers to include in requests
    func authenticationHeaders() async throws -> [String: String]
    
    /// Handles authentication challenges/refreshes if needed
    /// - Parameter challenge: Authentication challenge information
    /// - Returns: Updated headers or throws if auth failed
    func handleAuthenticationChallenge(_ challenge: AuthenticationChallenge) async throws -> [String: String]
    
    /// Validates if current authentication is still valid
    /// - Returns: True if authentication is valid, false if refresh needed
    func isAuthenticationValid() async -> Bool
    
    /// Cleans up any authentication resources (tokens, sessions, etc.)
    func cleanup() async
}

/// Information about authentication challenges from servers
public struct AuthenticationChallenge: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data?
    public let serverInfo: String?
    
    public init(statusCode: Int, headers: [String: String], body: Data? = nil, serverInfo: String? = nil) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.serverInfo = serverInfo
    }
}

/// Common authentication errors
public enum AuthenticationError: LocalizedError, Sendable, Equatable {
    case invalidCredentials
    case authenticationExpired
    case authenticationFailed(String)
    case unsupportedAuthScheme(String)
    case networkError(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid authentication credentials"
        case .authenticationExpired:
            return "Authentication has expired"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .unsupportedAuthScheme(let scheme):
            return "Unsupported authentication scheme: \(scheme)"
        case .networkError(let message):
            return "Network error during authentication: \(message)"
        }
    }
}

/// OAuth manual flow required error containing all necessary metadata for launching the OAuth flow
public struct OAuthManualFlowRequired: LocalizedError, Sendable {
    /// The authorization URL that should be opened in a browser
    public let authorizationURL: URL
    /// The redirect URI that will receive the authorization code
    public let redirectURI: URL
    /// The client ID for the OAuth flow
    public let clientId: String
    /// The OAuth scope (optional)
    public let scope: String?
    /// The resource URI for RFC 8707 Resource Indicators (optional)
    public let resourceURI: String?
    /// Additional metadata that might be useful for the implementer
    public let additionalMetadata: [String: String]
    
    public var errorDescription: String? {
        return "OAuth authorization flow requires manual user intervention. Please open the authorization URL in a browser to complete authentication."
    }
    
    /// Initialize the OAuth manual flow required error
    /// - Parameters:
    ///   - authorizationURL: The URL to open in browser for OAuth authorization
    ///   - redirectURI: The redirect URI for the OAuth flow
    ///   - clientId: The OAuth client ID
    ///   - scope: The OAuth scope (optional)
    ///   - resourceURI: The resource URI (optional)
    ///   - additionalMetadata: Additional metadata for the implementer (optional)
    public init(
        authorizationURL: URL,
        redirectURI: URL,
        clientId: String,
        scope: String? = nil,
        resourceURI: String? = nil,
        additionalMetadata: [String: String] = [:]
    ) {
        self.authorizationURL = authorizationURL
        self.redirectURI = redirectURI
        self.clientId = clientId
        self.scope = scope
        self.resourceURI = resourceURI
        self.additionalMetadata = additionalMetadata
    }
}
