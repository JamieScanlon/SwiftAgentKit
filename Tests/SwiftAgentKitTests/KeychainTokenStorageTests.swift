// KeychainTokenStorage Unit Tests
// Comprehensive tests for secure keychain-based OAuth token storage

import Testing
import Foundation
import Security
import SwiftAgentKit

struct KeychainTokenStorageTests {

    // MARK: - Test Configuration

    private let testService = "SwiftAgentKitTests.KeychainTests"

    // Unique test identifiers for parallel execution
    private var testAccountId: String {
        return "test_\(UUID().uuidString)"
    }

    // MARK: - Helper Methods

    private func createTestToken() -> OAuthToken {
        return OAuthToken(
            accessToken: "test_access_token_\(UUID().uuidString)",
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: "test_refresh_token_\(UUID().uuidString)",
            scope: "read write"
        )
    }

    private func createTestTokenWithConfig(token: OAuthToken? = nil) -> OAuthTokenWithConfig {
        let testToken = token ?? createTestToken()
        return OAuthTokenWithConfig(
            token: testToken,
            tokenEndpoint: "https://api.example.com/oauth/token",
            clientId: "test_client_id_\(UUID().uuidString)",
            clientSecret: "test_client_secret_\(UUID().uuidString)",
            scope: "read write admin"
        )
    }

    private func isKeychainAccessAvailable() async -> Bool {
        // Test keychain access by trying to store and retrieve a small test item
        let testAccountId = "keychain_test_\(UUID().uuidString)"
        let testData = "test_data".data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: testAccountId,
            kSecValueData as String: testData,
            kSecAttrSynchronizable as String: true
        ]

        // Try to add test item
        let addStatus = SecItemAdd(query as CFDictionary, nil)

        if addStatus == errSecSuccess {
            // Clean up test item
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService,
                kSecAttrAccount as String: testAccountId,
                kSecAttrSynchronizable as String: true
            ]
            SecItemDelete(deleteQuery as CFDictionary)
            return true
        } else {
            return false
        }
    }

    private func measureTime<T: Sendable>(_ operation: () async throws -> T) async throws -> TimeInterval {
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = try await operation()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        return timeElapsed
    }

    // MARK: - Basic CRUD Operations Tests

    @Test("Store and retrieve OAuth token")
    func testStoreAndRetrieveToken() async throws {
        // Skip test if keychain access is not available
        guard await isKeychainAccessAvailable() else {
            #expect(Bool(true), "Keychain access not available - skipping test")
            return
        }

        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId
        let token = createTestToken()

        // Store token
        try await storage.storeToken(token, for: accountId)

        // Retrieve token
        let retrievedToken = try await storage.retrieveToken(for: accountId)

        #expect(retrievedToken != nil)
        #expect(retrievedToken?.accessToken == token.accessToken)
        #expect(retrievedToken?.tokenType == token.tokenType)
        #expect(retrievedToken?.expiresIn == token.expiresIn)
        #expect(retrievedToken?.refreshToken == token.refreshToken)
        #expect(retrievedToken?.scope == token.scope)

        // Cleanup
        try await storage.removeToken(for: accountId)
    }

    @Test("Store and retrieve token with configuration")
    func testStoreAndRetrieveTokenWithConfig() async throws {
        // Skip test if keychain access is not available
        guard await isKeychainAccessAvailable() else {
            #expect(Bool(true), "Keychain access not available - skipping test")
            return
        }

        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId
        let tokenWithConfig = createTestTokenWithConfig()

        // Store token with config
        try await storage.storeTokenWithConfig(tokenWithConfig, for: accountId)

        // Retrieve token with config
        let retrievedTokenWithConfig = try await storage.retrieveTokenWithConfig(for: accountId)

        #expect(retrievedTokenWithConfig != nil)
        #expect(retrievedTokenWithConfig?.token.accessToken == tokenWithConfig.token.accessToken)
        #expect(retrievedTokenWithConfig?.tokenEndpoint == tokenWithConfig.tokenEndpoint)
        #expect(retrievedTokenWithConfig?.clientId == tokenWithConfig.clientId)
        #expect(retrievedTokenWithConfig?.clientSecret == tokenWithConfig.clientSecret)
        #expect(retrievedTokenWithConfig?.scope == tokenWithConfig.scope)

        // Also verify the token is stored separately for backward compatibility
        let retrievedToken = try await storage.retrieveToken(for: accountId)
        #expect(retrievedToken != nil)
        #expect(retrievedToken?.accessToken == tokenWithConfig.token.accessToken)

        // Cleanup
        try await storage.removeToken(for: accountId)
    }

    @Test("Remove stored token")
    func testRemoveToken() async throws {
        // Skip test if keychain access is not available
        guard await isKeychainAccessAvailable() else {
            #expect(Bool(true), "Keychain access not available - skipping test")
            return
        }

        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId
        let token = createTestToken()

        // Store token
        try await storage.storeToken(token, for: accountId)

        // Verify token exists
        let retrievedToken = try await storage.retrieveToken(for: accountId)
        #expect(retrievedToken != nil)

        // Remove token
        try await storage.removeToken(for: accountId)

        // Verify token is removed
        let removedToken = try await storage.retrieveToken(for: accountId)
        #expect(removedToken == nil)
    }

    @Test("Remove token with configuration")
    func testRemoveTokenWithConfig() async throws {
        // Skip test if keychain access is not available
        guard await isKeychainAccessAvailable() else {
            #expect(Bool(true), "Keychain access not available - skipping test")
            return
        }

        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId
        let tokenWithConfig = createTestTokenWithConfig()

        // Store token with config
        try await storage.storeTokenWithConfig(tokenWithConfig, for: accountId)

        // Verify both token and config exist
        let retrievedToken = try await storage.retrieveToken(for: accountId)
        let retrievedConfig = try await storage.retrieveTokenWithConfig(for: accountId)
        #expect(retrievedToken != nil)
        #expect(retrievedConfig != nil)

        // Remove token (should remove both)
        try await storage.removeToken(for: accountId)

        // Verify both are removed
        let removedToken = try await storage.retrieveToken(for: accountId)
        let removedConfig = try await storage.retrieveTokenWithConfig(for: accountId)
        #expect(removedToken == nil)
        #expect(removedConfig == nil)
    }

    // MARK: - Edge Cases and Error Handling Tests

    @Test("Retrieve non-existent token")
    func testRetrieveNonExistentToken() async throws {
        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId

        // Try to retrieve non-existent token
        let token = try await storage.retrieveToken(for: accountId)
        #expect(token == nil)
    }

    @Test("Retrieve non-existent token with configuration")
    func testRetrieveNonExistentTokenWithConfig() async throws {
        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId

        // Try to retrieve non-existent token with config
        let tokenWithConfig = try await storage.retrieveTokenWithConfig(for: accountId)
        #expect(tokenWithConfig == nil)
    }

    @Test("Remove non-existent token")
    func testRemoveNonExistentToken() async throws {
        // Skip test if keychain access is not available
        guard await isKeychainAccessAvailable() else {
            #expect(Bool(true), "Keychain access not available - skipping test")
            return
        }

        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId

        // Try to remove non-existent token (should not throw)
        try await storage.removeToken(for: accountId)
        // Test passes if no exception is thrown
    }

    @Test("Overwrite existing token")
    func testOverwriteExistingToken() async throws {
        // Skip test if keychain access is not available
        guard await isKeychainAccessAvailable() else {
            #expect(Bool(true), "Keychain access not available - skipping test")
            return
        }

        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId
        let originalToken = createTestToken()
        let newToken = createTestToken()

        // Store original token
        try await storage.storeToken(originalToken, for: accountId)

        // Verify original token is stored
        let retrievedOriginal = try await storage.retrieveToken(for: accountId)
        #expect(retrievedOriginal?.accessToken == originalToken.accessToken)

        // Overwrite with new token
        try await storage.storeToken(newToken, for: accountId)

        // Verify new token is stored
        let retrievedNew = try await storage.retrieveToken(for: accountId)
        #expect(retrievedNew?.accessToken == newToken.accessToken)
        #expect(retrievedNew?.accessToken != originalToken.accessToken)

        // Cleanup
        try await storage.removeToken(for: accountId)
    }

    // MARK: - Data Integrity Tests

    @Test("Token data integrity with special characters")
    func testTokenDataIntegrity() async throws {
        // Skip test if keychain access is not available
        guard await isKeychainAccessAvailable() else {
            #expect(Bool(true), "Keychain access not available - skipping test")
            return
        }

        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId
        let originalToken = OAuthToken(
            accessToken: "complex_token_with_special_chars_!@#$%^&*()",
            tokenType: "Bearer",
            expiresIn: 7200,
            refreshToken: "refresh_with_unicode_🚀_tokens",
            scope: "read:user write:repo admin:org"
        )

        // Store and retrieve token
        try await storage.storeToken(originalToken, for: accountId)
        let retrievedToken = try await storage.retrieveToken(for: accountId)

        // Verify all data is preserved exactly
        #expect(retrievedToken != nil)
        #expect(retrievedToken?.accessToken == originalToken.accessToken)
        #expect(retrievedToken?.tokenType == originalToken.tokenType)
        #expect(retrievedToken?.expiresIn == originalToken.expiresIn)
        #expect(retrievedToken?.refreshToken == originalToken.refreshToken)
        #expect(retrievedToken?.scope == originalToken.scope)

        // Cleanup
        try await storage.removeToken(for: accountId)
    }

    // MARK: - Multiple Accounts Tests

    @Test("Multiple accounts isolation")
    func testMultipleAccountsIsolation() async throws {
        // Skip test if keychain access is not available
        guard await isKeychainAccessAvailable() else {
            #expect(Bool(true), "Keychain access not available - skipping test")
            return
        }

        let storage = KeychainTokenStorage(service: testService)
        let accountId1 = testAccountId
        let accountId2 = testAccountId
        let token1 = createTestToken()
        let token2 = createTestToken()

        // Store different tokens for different accounts
        try await storage.storeToken(token1, for: accountId1)
        try await storage.storeToken(token2, for: accountId2)

        // Verify tokens are isolated
        let retrievedToken1 = try await storage.retrieveToken(for: accountId1)
        let retrievedToken2 = try await storage.retrieveToken(for: accountId2)

        #expect(retrievedToken1 != nil)
        #expect(retrievedToken2 != nil)
        #expect(retrievedToken1?.accessToken == token1.accessToken)
        #expect(retrievedToken2?.accessToken == token2.accessToken)
        #expect(retrievedToken1?.accessToken != retrievedToken2?.accessToken)

        // Cleanup
        try await storage.removeToken(for: accountId1)
        try await storage.removeToken(for: accountId2)
    }

    // MARK: - Service Isolation Tests

    @Test("Service isolation")
    func testServiceIsolation() async throws {
        // Skip test if keychain access is not available
        guard await isKeychainAccessAvailable() else {
            #expect(Bool(true), "Keychain access not available - skipping test")
            return
        }

        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId
        let token = createTestToken()
        let otherServiceStorage = KeychainTokenStorage(service: "SwiftAgentKitTests.OtherService")

        // Store token in test service
        try await storage.storeToken(token, for: accountId)

        // Verify token exists in test service
        let retrievedFromTestService = try await storage.retrieveToken(for: accountId)
        #expect(retrievedFromTestService != nil)

        // Verify token does not exist in other service
        let retrievedFromOtherService = try await otherServiceStorage.retrieveToken(for: accountId)
        #expect(retrievedFromOtherService == nil)

        // Cleanup
        try await storage.removeToken(for: accountId)
    }

    // MARK: - iCloud Keychain Sync Tests

    @Test("iCloud Keychain sync attribute")
    func testICloudKeychainSyncAttribute() async throws {
        // Skip test if keychain access is not available
        guard await isKeychainAccessAvailable() else {
            #expect(Bool(true), "Keychain access not available - skipping test")
            return
        }

        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId
        let token = createTestToken()

        // Store token
        try await storage.storeToken(token, for: accountId)

        // Verify the token is stored with iCloud sync attribute
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: accountId,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        #expect(status == errSecSuccess)
        #expect(result != nil)

        if let attributes = result as? [String: Any] {
            // Verify iCloud sync is enabled
            let isSynchronizable = attributes[kSecAttrSynchronizable as String] as? Bool
            #expect(isSynchronizable == true)
        }

        // Cleanup
        try await storage.removeToken(for: accountId)
    }

    // MARK: - Performance Tests

    @Test("Store and retrieve performance")
    func testStoreRetrievePerformance() async throws {
        // Skip test if keychain access is not available
        guard await isKeychainAccessAvailable() else {
            #expect(Bool(true), "Keychain access not available - skipping test")
            return
        }

        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId
        let token = createTestToken()

        // Measure store performance
        let storeTime = try await measureTime {
            try await storage.storeToken(token, for: accountId)
        }

        // Measure retrieve performance
        let retrieveTime = try await measureTime {
            _ = try await storage.retrieveToken(for: accountId)
        }

        // Performance assertions (adjust thresholds as needed)
        #expect(storeTime < 1.0, "Token storage should complete within 1 second")
        #expect(retrieveTime < 1.0, "Token retrieval should complete within 1 second")

        // Cleanup
        try await storage.removeToken(for: accountId)
    }
}
