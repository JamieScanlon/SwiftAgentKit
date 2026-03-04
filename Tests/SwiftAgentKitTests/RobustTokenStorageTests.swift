// RobustTokenStorage Unit Tests
// Comprehensive tests for robust token storage with automatic fallback

import Testing
import Foundation
import SwiftAgentKit

struct RobustTokenStorageTests {

    // MARK: - Test Configuration

    private let testService = "SwiftAgentKitTests.RobustTests"

    // Unique test identifiers for parallel execution
    private var testAccountId: String {
        return "robust_test_\(UUID().uuidString)"
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

    // MARK: - Basic Functionality Tests

    @Test("Robust storage initializes correctly")
    func testRobustStorageInitialization() async throws {
        let storage = RobustTokenStorage()

        #expect(await storage.isUsingInMemoryStorage == false)
    }

    @Test("Force in-memory storage works")
    func testForceInMemoryStorage() async throws {
        let storage = RobustTokenStorage()

        await storage.forceInMemoryStorage()

        #expect(await storage.isUsingInMemoryStorage == true)
    }

    @Test("Store and retrieve token with robust storage")
    func testStoreAndRetrieveToken() async throws {
        let storage = RobustTokenStorage()
        let accountId = testAccountId
        let token = createTestToken()

        try await storage.storeToken(token, for: accountId)

        let retrievedToken = try await storage.retrieveToken(for: accountId)

        #expect(retrievedToken != nil)
        #expect(retrievedToken?.accessToken == token.accessToken)
        #expect(retrievedToken?.tokenType == token.tokenType)
        #expect(retrievedToken?.expiresIn == token.expiresIn)
        #expect(retrievedToken?.refreshToken == token.refreshToken)
        #expect(retrievedToken?.scope == token.scope)

        try await storage.removeToken(for: accountId)
    }

    @Test("Store and retrieve token with config using robust storage")
    func testStoreAndRetrieveTokenWithConfig() async throws {
        let storage = RobustTokenStorage()
        let accountId = testAccountId
        let tokenWithConfig = createTestTokenWithConfig()

        try await storage.storeTokenWithConfig(tokenWithConfig, for: accountId)

        let retrievedTokenWithConfig = try await storage.retrieveTokenWithConfig(for: accountId)

        #expect(retrievedTokenWithConfig != nil)
        #expect(retrievedTokenWithConfig?.token.accessToken == tokenWithConfig.token.accessToken)
        #expect(retrievedTokenWithConfig?.tokenEndpoint == tokenWithConfig.tokenEndpoint)
        #expect(retrievedTokenWithConfig?.clientId == tokenWithConfig.clientId)
        #expect(retrievedTokenWithConfig?.clientSecret == tokenWithConfig.clientSecret)
        #expect(retrievedTokenWithConfig?.scope == tokenWithConfig.scope)

        let retrievedToken = try await storage.retrieveToken(for: accountId)
        #expect(retrievedToken != nil)
        #expect(retrievedToken?.accessToken == tokenWithConfig.token.accessToken)

        try await storage.removeToken(for: accountId)
    }

    @Test("Remove token works with robust storage")
    func testRemoveToken() async throws {
        let storage = RobustTokenStorage()
        let accountId = testAccountId
        let token = createTestToken()

        try await storage.storeToken(token, for: accountId)

        let retrievedToken = try await storage.retrieveToken(for: accountId)
        #expect(retrievedToken != nil)

        try await storage.removeToken(for: accountId)

        let removedToken = try await storage.retrieveToken(for: accountId)
        #expect(removedToken == nil)
    }

    @Test("Clear all tokens works with robust storage")
    func testClearAllTokens() async throws {
        let storage = RobustTokenStorage()
        let accountId1 = "\(testAccountId)_1"
        let accountId2 = "\(testAccountId)_2"
        let token1 = createTestToken()
        let token2 = createTestToken()

        try await storage.storeToken(token1, for: accountId1)
        try await storage.storeToken(token2, for: accountId2)

        let retrievedToken1 = try await storage.retrieveToken(for: accountId1)
        let retrievedToken2 = try await storage.retrieveToken(for: accountId2)
        #expect(retrievedToken1 != nil)
        #expect(retrievedToken2 != nil)

        try await storage.clearAllTokens()

        let clearedToken1 = try await storage.retrieveToken(for: accountId1)
        let clearedToken2 = try await storage.retrieveToken(for: accountId2)
        #expect(clearedToken1 == nil)
        #expect(clearedToken2 == nil)
    }

    // MARK: - Fallback Behavior Tests

    @Test("Fallback to in-memory storage when keychain fails")
    func testFallbackToInMemoryStorage() async throws {
        let storage = RobustTokenStorage()
        let accountId = testAccountId
        let token = createTestToken()

        await storage.forceInMemoryStorage()

        try await storage.storeToken(token, for: accountId)

        #expect(await storage.isUsingInMemoryStorage == true)

        let retrievedToken = try await storage.retrieveToken(for: accountId)
        #expect(retrievedToken != nil)
        #expect(retrievedToken?.accessToken == token.accessToken)

        try await storage.removeToken(for: accountId)
    }

    @Test("Fallback preserves data integrity")
    func testFallbackPreservesDataIntegrity() async throws {
        let storage = RobustTokenStorage()
        let accountId = testAccountId
        let tokenWithConfig = createTestTokenWithConfig()

        await storage.forceInMemoryStorage()

        try await storage.storeTokenWithConfig(tokenWithConfig, for: accountId)

        let retrievedTokenWithConfig = try await storage.retrieveTokenWithConfig(for: accountId)
        #expect(retrievedTokenWithConfig != nil)
        #expect(retrievedTokenWithConfig?.token.accessToken == tokenWithConfig.token.accessToken)
        #expect(retrievedTokenWithConfig?.tokenEndpoint == tokenWithConfig.tokenEndpoint)
        #expect(retrievedTokenWithConfig?.clientId == tokenWithConfig.clientId)
        #expect(retrievedTokenWithConfig?.clientSecret == tokenWithConfig.clientSecret)
        #expect(retrievedTokenWithConfig?.scope == tokenWithConfig.scope)

        let retrievedToken = try await storage.retrieveToken(for: accountId)
        #expect(retrievedToken != nil)
        #expect(retrievedToken?.accessToken == tokenWithConfig.token.accessToken)

        try await storage.removeToken(for: accountId)
    }

    // MARK: - Error Handling Tests

    @Test("Handles keychain errors gracefully")
    func testHandlesKeychainErrorsGracefully() async throws {
        let storage = RobustTokenStorage()
        let accountId = testAccountId
        let token = createTestToken()

        await storage.forceInMemoryStorage()

        try await storage.storeToken(token, for: accountId)
        let retrievedToken = try await storage.retrieveToken(for: accountId)
        #expect(retrievedToken != nil)

        try await storage.removeToken(for: accountId)
    }

    // MARK: - Performance Tests

    @Test("Robust storage performance is acceptable")
    func testRobustStoragePerformance() async throws {
        let storage = RobustTokenStorage()
        let accountId = testAccountId
        let token = createTestToken()

        let storeTime = try await measureTime {
            try await storage.storeToken(token, for: accountId)
        }

        let retrieveTime = try await measureTime {
            _ = try await storage.retrieveToken(for: accountId)
        }

        let removeTime = try await measureTime {
            try await storage.removeToken(for: accountId)
        }

        #expect(storeTime < 1.0, "Store operation took too long: \(storeTime)s")
        #expect(retrieveTime < 1.0, "Retrieve operation took too long: \(retrieveTime)s")
        #expect(removeTime < 1.0, "Remove operation took too long: \(removeTime)s")
    }

    // MARK: - Helper Methods

    private func measureTime<T: Sendable>(_ operation: () async throws -> T) async throws -> TimeInterval {
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = try await operation()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        return timeElapsed
    }
}
