//
//  InMemoryTokenStorageTests.swift
//  SwiftAgentKitTests
//

import Testing
import Foundation
import SwiftAgentKit

/// Comprehensive tests for InMemoryTokenStorage (OAuth Manual Flow)
struct InMemoryTokenStorageTests {

    private var testAccountId: String {
        "in_memory_test_\(UUID().uuidString)"
    }

    private func createTestToken() -> OAuthToken {
        OAuthToken(
            accessToken: "test_access_\(UUID().uuidString)",
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: "test_refresh_\(UUID().uuidString)",
            scope: "read write"
        )
    }

    private func createTestTokenWithConfig(token: OAuthToken? = nil) -> OAuthTokenWithConfig {
        let t = token ?? createTestToken()
        return OAuthTokenWithConfig(
            token: t,
            tokenEndpoint: "https://api.example.com/token",
            clientId: "client_\(UUID().uuidString)",
            clientSecret: "secret_\(UUID().uuidString)",
            scope: "read write"
        )
    }

    @Test("Store and retrieve OAuth token")
    func storeAndRetrieveToken() async throws {
        let storage = InMemoryTokenStorage()
        let accountId = testAccountId
        let token = createTestToken()

        try await storage.storeToken(token, for: accountId)
        let retrieved = try await storage.retrieveToken(for: accountId)

        #expect(retrieved != nil)
        #expect(retrieved?.accessToken == token.accessToken)
        #expect(retrieved?.tokenType == token.tokenType)
        #expect(retrieved?.expiresIn == token.expiresIn)
        #expect(retrieved?.refreshToken == token.refreshToken)
        #expect(retrieved?.scope == token.scope)
    }

    @Test("Store and retrieve token with config")
    func storeAndRetrieveTokenWithConfig() async throws {
        let storage = InMemoryTokenStorage()
        let accountId = testAccountId
        let tokenWithConfig = createTestTokenWithConfig()

        try await storage.storeTokenWithConfig(tokenWithConfig, for: accountId)
        let retrieved = try await storage.retrieveTokenWithConfig(for: accountId)

        #expect(retrieved != nil)
        #expect(retrieved?.token.accessToken == tokenWithConfig.token.accessToken)
        #expect(retrieved?.tokenEndpoint == tokenWithConfig.tokenEndpoint)
        #expect(retrieved?.clientId == tokenWithConfig.clientId)
        #expect(retrieved?.clientSecret == tokenWithConfig.clientSecret)
        #expect(retrieved?.scope == tokenWithConfig.scope)

        let tokenOnly = try await storage.retrieveToken(for: accountId)
        #expect(tokenOnly?.accessToken == tokenWithConfig.token.accessToken)
    }

    @Test("Retrieve non-existent token returns nil")
    func retrieveNonExistent() async throws {
        let storage = InMemoryTokenStorage()
        let token = try await storage.retrieveToken(for: testAccountId)
        #expect(token == nil)

        let config = try await storage.retrieveTokenWithConfig(for: testAccountId)
        #expect(config == nil)
    }

    @Test("Remove token")
    func removeToken() async throws {
        let storage = InMemoryTokenStorage()
        let accountId = testAccountId
        let token = createTestToken()

        try await storage.storeToken(token, for: accountId)
        #expect(try await storage.retrieveToken(for: accountId) != nil)

        try await storage.removeToken(for: accountId)
        #expect(try await storage.retrieveToken(for: accountId) == nil)
        #expect(try await storage.retrieveTokenWithConfig(for: accountId) == nil)
    }

    @Test("Remove token clears both token and tokenWithConfig")
    func removeClearsBoth() async throws {
        let storage = InMemoryTokenStorage()
        let accountId = testAccountId
        try await storage.storeTokenWithConfig(createTestTokenWithConfig(), for: accountId)

        try await storage.removeToken(for: accountId)
        #expect(try await storage.retrieveToken(for: accountId) == nil)
        #expect(try await storage.retrieveTokenWithConfig(for: accountId) == nil)
    }

    @Test("Overwrite existing token")
    func overwriteToken() async throws {
        let storage = InMemoryTokenStorage()
        let accountId = testAccountId
        let token1 = createTestToken()
        let token2 = createTestToken()

        try await storage.storeToken(token1, for: accountId)
        try await storage.storeToken(token2, for: accountId)

        let retrieved = try await storage.retrieveToken(for: accountId)
        #expect(retrieved?.accessToken == token2.accessToken)
    }

    @Test("Clear all tokens")
    func clearAllTokens() async throws {
        let storage = InMemoryTokenStorage()
        let id1 = testAccountId
        let id2 = "\(testAccountId)_2"
        try await storage.storeToken(createTestToken(), for: id1)
        try await storage.storeToken(createTestToken(), for: id2)

        try await storage.clearAllTokens()

        #expect(try await storage.retrieveToken(for: id1) == nil)
        #expect(try await storage.retrieveToken(for: id2) == nil)
    }

    @Test("Multiple accounts isolation")
    func multipleAccountsIsolation() async throws {
        let storage = InMemoryTokenStorage()
        let id1 = testAccountId
        let id2 = "\(testAccountId)_2"
        let token1 = createTestToken()
        let token2 = createTestToken()

        try await storage.storeToken(token1, for: id1)
        try await storage.storeToken(token2, for: id2)

        let r1 = try await storage.retrieveToken(for: id1)
        let r2 = try await storage.retrieveToken(for: id2)
        #expect(r1?.accessToken == token1.accessToken)
        #expect(r2?.accessToken == token2.accessToken)
        #expect(r1?.accessToken != r2?.accessToken)
    }

    @Test("Remove non-existent token does not throw")
    func removeNonExistentDoesNotThrow() async throws {
        let storage = InMemoryTokenStorage()
        try await storage.removeToken(for: testAccountId)
    }
}
