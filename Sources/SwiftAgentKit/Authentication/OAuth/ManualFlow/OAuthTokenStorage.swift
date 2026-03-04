// OAuth Token Storage Protocol and Types
// Defines the interface for storing and retrieving OAuth tokens

import Foundation

/// OAuth token and configuration storage
public struct OAuthTokenWithConfig: Codable, Sendable {
    public let token: OAuthToken
    public let tokenEndpoint: String
    public let clientId: String
    public let clientSecret: String?
    public let scope: String?
    
    public init(token: OAuthToken, tokenEndpoint: String, clientId: String, clientSecret: String? = nil, scope: String? = nil) {
        self.token = token
        self.tokenEndpoint = tokenEndpoint
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.scope = scope
    }
}

/// Token storage protocol for OAuth tokens
public protocol OAuthTokenStorage: Sendable {
    func storeToken(_ token: OAuthToken, for serverName: String) async throws
    func retrieveToken(for serverName: String) async throws -> OAuthToken?
    func removeToken(for serverName: String) async throws
    
    // New methods for storing token with configuration
    func storeTokenWithConfig(_ tokenWithConfig: OAuthTokenWithConfig, for serverName: String) async throws
    func retrieveTokenWithConfig(for serverName: String) async throws -> OAuthTokenWithConfig?
    
    // Method to clear all stored tokens
    func clearAllTokens() async throws
}
