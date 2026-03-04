// Robust Token Storage with Automatic Fallback
// Automatically falls back to in-memory storage when keychain fails

import Foundation
import Logging

/// Robust token storage that automatically falls back to in-memory storage
/// when keychain operations fail due to permission issues
public actor RobustTokenStorage: OAuthTokenStorage {
    private let keychainStorage: KeychainTokenStorage
    private let inMemoryStorage: InMemoryTokenStorage
    private let logger: Logger
    private var useInMemoryStorage = false
    private var hasWarnedAboutFallback = false
    
    public init(logger: Logger? = nil) {
        let resolvedLogger = logger ?? SwiftAgentKitLogging.logger(for: .authentication("RobustTokenStorage"))
        self.logger = resolvedLogger
        self.keychainStorage = KeychainTokenStorage(service: "SwiftAgentKit.OAuth", logger: resolvedLogger)
        self.inMemoryStorage = InMemoryTokenStorage(logger: resolvedLogger)
    }
    
    /// Attempts to use keychain storage, falls back to in-memory if it fails
    private func attemptKeychainOperation<T: Sendable>(_ operation: @escaping () async throws -> T) async throws -> T {
        if useInMemoryStorage {
            // We're already using in-memory storage, skip keychain
            throw KeychainError.permissionDenied
        }
        
        do {
            return try await operation()
        } catch let keychainError as KeychainError {
            // Keychain failed, switch to in-memory storage
            if !hasWarnedAboutFallback {
                self.logger.warning(
                    "Keychain storage failed, switching to in-memory storage (tokens won't persist between sessions)",
                    metadata: ["error": .string(keychainError.localizedDescription)]
                )
                hasWarnedAboutFallback = true
            }
            useInMemoryStorage = true
            throw keychainError
        } catch {
            // Other errors, re-throw
            throw error
        }
    }
    
    public func storeToken(_ token: OAuthToken, for serverName: String) async throws {
        do {
            try await attemptKeychainOperation {
                try await self.keychainStorage.storeToken(token, for: serverName)
            }
        } catch {
            // Fallback to in-memory storage
            try await inMemoryStorage.storeToken(token, for: serverName)
        }
    }
    
    public func retrieveToken(for serverName: String) async throws -> OAuthToken? {
        if useInMemoryStorage {
            return try await inMemoryStorage.retrieveToken(for: serverName)
        }
        
        do {
            return try await keychainStorage.retrieveToken(for: serverName)
        } catch {
            // If keychain fails, try in-memory as fallback
            return try await inMemoryStorage.retrieveToken(for: serverName)
        }
    }
    
    public func removeToken(for serverName: String) async throws {
        if useInMemoryStorage {
            try await inMemoryStorage.removeToken(for: serverName)
        } else {
            do {
                try await keychainStorage.removeToken(for: serverName)
            } catch {
                // Also try to remove from in-memory as fallback
                try? await inMemoryStorage.removeToken(for: serverName)
            }
        }
    }
    
    public func storeTokenWithConfig(_ tokenWithConfig: OAuthTokenWithConfig, for serverName: String) async throws {
        do {
            try await attemptKeychainOperation {
                try await self.keychainStorage.storeTokenWithConfig(tokenWithConfig, for: serverName)
            }
        } catch {
            // Fallback to in-memory storage
            try await inMemoryStorage.storeTokenWithConfig(tokenWithConfig, for: serverName)
        }
    }
    
    public func retrieveTokenWithConfig(for serverName: String) async throws -> OAuthTokenWithConfig? {
        if useInMemoryStorage {
            return try await inMemoryStorage.retrieveTokenWithConfig(for: serverName)
        }
        
        do {
            return try await keychainStorage.retrieveTokenWithConfig(for: serverName)
        } catch {
            // If keychain fails, try in-memory as fallback
            return try await inMemoryStorage.retrieveTokenWithConfig(for: serverName)
        }
    }
    
    public func clearAllTokens() async throws {
        if useInMemoryStorage {
            try await inMemoryStorage.clearAllTokens()
        } else {
            do {
                try await keychainStorage.clearAllTokens()
            } catch {
                // Also clear in-memory storage
                try? await inMemoryStorage.clearAllTokens()
            }
        }
    }
    
    /// Returns true if currently using in-memory storage due to keychain issues
    public var isUsingInMemoryStorage: Bool {
        return useInMemoryStorage
    }
    
    /// Forces the use of in-memory storage (useful for testing or when keychain is known to be problematic)
    public func forceInMemoryStorage() {
        useInMemoryStorage = true
        logger.info("Forced to use in-memory storage (tokens won't persist between sessions)")
    }
}
