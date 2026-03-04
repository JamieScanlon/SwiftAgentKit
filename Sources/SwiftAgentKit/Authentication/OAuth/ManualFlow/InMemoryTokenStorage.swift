// In-Memory OAuth Token Storage
// Simple in-memory storage implementation for development and testing

import Foundation
import Logging

/// Simple in-memory token storage (for development/testing)
public actor InMemoryTokenStorage: OAuthTokenStorage {
    private var tokens: [String: OAuthToken] = [:]
    private var tokensWithConfig: [String: OAuthTokenWithConfig] = [:]
    private let logger: Logger
    
    public init(logger: Logger? = nil) {
        self.logger = logger ?? SwiftAgentKitLogging.logger(for: .authentication("InMemoryTokenStorage"))
    }
    
    public func storeToken(_ token: OAuthToken, for serverName: String) async throws {
        tokens[serverName] = token
        logger.debug("Stored OAuth token for server", metadata: ["serverName": .string(serverName)])
    }
    
    public func retrieveToken(for serverName: String) async throws -> OAuthToken? {
        return tokens[serverName]
    }
    
    public func removeToken(for serverName: String) async throws {
        tokens.removeValue(forKey: serverName)
        tokensWithConfig.removeValue(forKey: serverName)
        logger.debug("Removed OAuth token for server", metadata: ["serverName": .string(serverName)])
    }
    
    public func storeTokenWithConfig(_ tokenWithConfig: OAuthTokenWithConfig, for serverName: String) async throws {
        tokensWithConfig[serverName] = tokenWithConfig
        tokens[serverName] = tokenWithConfig.token
        logger.debug("Stored OAuth token with config for server", metadata: ["serverName": .string(serverName)])
    }
    
    public func retrieveTokenWithConfig(for serverName: String) async throws -> OAuthTokenWithConfig? {
        return tokensWithConfig[serverName]
    }
    
    public func clearAllTokens() async throws {
        tokens.removeAll()
        tokensWithConfig.removeAll()
        logger.debug("Cleared all OAuth tokens from in-memory storage")
    }
}
