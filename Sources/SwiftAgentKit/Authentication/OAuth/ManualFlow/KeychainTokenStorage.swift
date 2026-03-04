// Keychain-based OAuth Token Storage
// Secure token storage using iOS/macOS Keychain with iCloud Keychain sync support

import Foundation
import Logging

/// Keychain-specific error types for better error handling
public enum KeychainError: Error, LocalizedError {
    case permissionDenied
    case userInteractionRequired
    case authenticationFailed
    case storageFailed(OSStatus)
    case retrievalFailed(OSStatus)
    
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Keychain access denied. Please check your keychain permissions."
        case .userInteractionRequired:
            return "Keychain requires user interaction. Please unlock your keychain and grant access."
        case .authenticationFailed:
            return "Keychain authentication failed. Please unlock your keychain."
        case .storageFailed(let status):
            return "Failed to store data in keychain (error: \(status))"
        case .retrievalFailed(let status):
            return "Failed to retrieve data from keychain (error: \(status))"
        }
    }
}

/// Keychain-based token storage (more secure for production)
/// Compatible with iCloud Keychain synchronization across devices
public actor KeychainTokenStorage: OAuthTokenStorage {
    private let service: String
    private let logger: Logger
    private var hasPermissionIssues = false
    
    public init(service: String = "SwiftAgentKit.OAuth", logger: Logger? = nil) {
        self.service = service
        self.logger = logger ?? SwiftAgentKitLogging.logger(for: .authentication("KeychainTokenStorage"), metadata: ["service": .string(service)])
    }
    
    /// Checks if keychain access is available and working
    private func checkKeychainAccess() async -> Bool {
        // Try a simple read operation to test keychain access
        let testQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "test_access_check",
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(testQuery as CFDictionary, &result)
        
        // errSecSuccess or errSecItemNotFound both indicate keychain access is working
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// Attempts to resolve keychain permission issues
    private func resolvePermissionIssues() async -> Bool {
        logger.info("Keychain permission issue detected, attempting to resolve")
        
        // Try to trigger keychain access permission dialog
        let testData = "test".data(using: .utf8)!
        let testQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "permission_test",
            kSecValueData as String: testData
        ]
        
        // Delete any existing test item
        SecItemDelete(testQuery as CFDictionary)
        
        // Try to add a test item to trigger permission dialog
        let status = SecItemAdd(testQuery as CFDictionary, nil)
        
        if status == errSecSuccess {
            // Clean up test item
            SecItemDelete(testQuery as CFDictionary)
            logger.info("Keychain permissions resolved successfully")
            return true
        } else if status == errSecInteractionNotAllowed {
            logger.warning(
                "Keychain requires user interaction: Open Keychain Access app, look for '\(service)' entries, unlock keychain if needed, grant access when prompted",
                metadata: ["service": .string(service)]
            )
            return false
        } else {
            logger.error("Unable to resolve keychain permissions", metadata: ["status": .stringConvertible(status)])
            return false
        }
    }
    
    public func storeToken(_ token: OAuthToken, for serverName: String) async throws {
        // Check if we've already detected permission issues
        if hasPermissionIssues {
            throw KeychainError.permissionDenied
        }
        
        // Check keychain access before attempting to store
        let hasAccess = await checkKeychainAccess()
        if !hasAccess {
            logger.warning("Keychain access check failed, attempting to resolve permissions")
            let resolved = await resolvePermissionIssues()
            if !resolved {
                hasPermissionIssues = true
                throw KeychainError.permissionDenied
            }
        }
        
        let tokenData = try JSONEncoder().encode(token)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverName,
            kSecValueData as String: tokenData,
            kSecAttrSynchronizable as String: true  // Enable iCloud Keychain sync
        ]
        
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            // Handle specific keychain errors
            if status == errSecInteractionNotAllowed {
                logger.warning(
                    "Keychain requires user interaction: Open Keychain Access app, look for '\(service)' entries, unlock keychain if needed, grant access when prompted",
                    metadata: ["serverName": .string(serverName)]
                )
                hasPermissionIssues = true
                throw KeychainError.userInteractionRequired
            } else if status == errSecAuthFailed {
                logger.error("Keychain authentication failed; unlock your keychain")
                hasPermissionIssues = true
                throw KeychainError.authenticationFailed
            } else {
                logger.error("Keychain storage failed", metadata: ["status": .stringConvertible(status), "serverName": .string(serverName)])
                throw KeychainError.storageFailed(status)
            }
        }
        
        logger.debug("Stored OAuth token in keychain for server", metadata: ["serverName": .string(serverName)])
    }
    
    public func retrieveToken(for serverName: String) async throws -> OAuthToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: true  // Enable iCloud Keychain sync
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to retrieve OAuth token from keychain"
            ])
        }
        
        guard let tokenData = result as? Data else {
            return nil
        }
        
        return try JSONDecoder().decode(OAuthToken.self, from: tokenData)
    }
    
    public func removeToken(for serverName: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverName,
            kSecAttrSynchronizable as String: true  // Enable iCloud Keychain sync
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to remove OAuth token from keychain"
            ])
        }
        
        logger.debug("Removed OAuth token from keychain for server", metadata: ["serverName": .string(serverName)])
    }
    
    public func storeTokenWithConfig(_ tokenWithConfig: OAuthTokenWithConfig, for serverName: String) async throws {
        // Check if we've already detected permission issues
        if hasPermissionIssues {
            throw KeychainError.permissionDenied
        }
        
        // Check keychain access before attempting to store
        let hasAccess = await checkKeychainAccess()
        if !hasAccess {
            logger.warning("Keychain access check failed, attempting to resolve permissions")
            let resolved = await resolvePermissionIssues()
            if !resolved {
                hasPermissionIssues = true
                throw KeychainError.permissionDenied
            }
        }
        
        do {
            let tokenWithConfigData = try JSONEncoder().encode(tokenWithConfig)
            logger.debug("Successfully encoded OAuthTokenWithConfig for server", metadata: ["serverName": .string(serverName)])
            
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "\(serverName)_config",
                kSecValueData as String: tokenWithConfigData,
                kSecAttrSynchronizable as String: true  // Enable iCloud Keychain sync
            ]
            
            // Delete any existing item first
            SecItemDelete(query as CFDictionary)
            
            let status = SecItemAdd(query as CFDictionary, nil)
            
            guard status == errSecSuccess else {
                // Handle specific keychain errors
                if status == errSecInteractionNotAllowed {
                    logger.warning(
                        "Keychain requires user interaction for storing config: Open Keychain Access app, look for '\(service)' entries, unlock keychain if needed, grant access when prompted",
                        metadata: ["serverName": .string(serverName)]
                    )
                    hasPermissionIssues = true
                    throw KeychainError.userInteractionRequired
                } else if status == errSecAuthFailed {
                    logger.error("Keychain authentication failed; unlock your keychain")
                    hasPermissionIssues = true
                    throw KeychainError.authenticationFailed
                } else {
                    logger.error("Keychain storage failed", metadata: ["status": .stringConvertible(status), "serverName": .string(serverName)])
                    throw KeychainError.storageFailed(status)
                }
            }
            
            // Also store the token separately for backward compatibility
            try await storeToken(tokenWithConfig.token, for: serverName)
            
            logger.debug("Stored OAuth token with config in keychain for server", metadata: ["serverName": .string(serverName)])
        } catch let keychainError as KeychainError {
            throw keychainError
        } catch {
            logger.error("Error in storeTokenWithConfig", metadata: ["error": .string(String(describing: error)), "serverName": .string(serverName)])
            throw error
        }
    }
    
    public func retrieveTokenWithConfig(for serverName: String) async throws -> OAuthTokenWithConfig? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(serverName)_config",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: true  // Enable iCloud Keychain sync
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to retrieve OAuth token with config from keychain"
            ])
        }
        
        guard let tokenWithConfigData = result as? Data else {
            return nil
        }
        
        return try JSONDecoder().decode(OAuthTokenWithConfig.self, from: tokenWithConfigData)
    }
    
    /// Clears all stored OAuth tokens for this service
    public func clearAllTokens() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: true
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            let errorMessage = if status == errSecInteractionNotAllowed {
                "Failed to clear OAuth tokens from keychain: User interaction required (keychain may be locked). Please unlock your keychain and try again."
            } else if status == errSecItemNotFound {
                "No OAuth tokens found in keychain to clear"
            } else {
                "Failed to clear OAuth tokens from keychain (error code: \(status))"
            }
            
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: errorMessage
            ])
        }
        
        if status == errSecItemNotFound {
            logger.info("No OAuth tokens found in keychain to clear", metadata: ["service": .string(service)])
        } else {
            logger.debug("Cleared all OAuth tokens from keychain for service", metadata: ["service": .string(service)])
        }
    }
}
