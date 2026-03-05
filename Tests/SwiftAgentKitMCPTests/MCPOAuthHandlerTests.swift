// MCPOAuthHandler Unit Tests
// Comprehensive tests for OAuth handler with robust token storage

import Testing
import Foundation
import Logging
import SwiftAgentKitMCP
import SwiftAgentKit
import EasyJSON

/// Minimal OAuthCallbackReceiver for testing that MCPOAuthHandler accepts a custom receiver.
private struct MockOAuthCallbackReceiver: OAuthCallbackReceiver {
    func waitForCallback(timeout: TimeInterval) async throws -> OAuthCallbackServer.CallbackResult {
        OAuthCallbackServer.CallbackResult(authorizationCode: nil, state: nil, error: nil, errorDescription: nil)
    }
}

struct MCPOAuthHandlerTests {

    // MARK: - Test Configuration

    private let testService = "SwiftAgentKitMCPTests.MCPOAuthTests"

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

    private func createMockMCPConfig() -> MCPConfig.RemoteServerConfig {
        let authConfigDict: [String: Any] = [
            "clientId": "test_client_id_123",
            "clientSecret": "test_client_secret_456",
            "scope": "test_scope",
            "redirectURI": "http://localhost:8080/oauth/callback"
        ]

        let authConfig = try? JSON(authConfigDict)

        return MCPConfig.RemoteServerConfig(
            name: "test_server",
            url: "https://api.example.com/mcp",
            authType: "OAuth",
            authConfig: authConfig,
            connectionTimeout: 30.0,
            requestTimeout: 60.0,
            maxRetries: 3
        )
    }

    // MARK: - Initialization Tests

    @Test("MCPOAuthHandler initializes with default robust storage")
    func testInitializationWithDefaultStorage() async throws {
        let handler = MCPOAuthHandler()

        // Should use RobustTokenStorage by default
        #expect(handler.tokenStorage is RobustTokenStorage)
    }

    @Test("MCPOAuthHandler initializes with custom storage")
    func testInitializationWithCustomStorage() async throws {
        let customStorage = InMemoryTokenStorage()
        let handler = MCPOAuthHandler(tokenStorage: customStorage)

        // Should use the provided storage
        #expect(handler.tokenStorage is InMemoryTokenStorage)
    }

    @Test("MCPOAuthHandler initializes with callbackReceiver convenience parameter")
    func testInitializationWithCallbackReceiver() async throws {
        let receiver = MockOAuthCallbackReceiver()
        let handler = MCPOAuthHandler(callbackReceiver: receiver)
        #expect(handler.tokenStorage is RobustTokenStorage)
        // Handler uses OAuthAuthenticator(callbackReceiver:) internally; extractOAuthCredentials still works
        let config = createMockMCPConfig()
        let credentials = try handler.extractOAuthCredentials(from: config)
        #expect(credentials.clientId == "test_client_id_123")
    }

    @Test("MCPOAuthHandler initializes with custom authenticator")
    func testInitializationWithAuthenticator() async throws {
        let authenticator = OAuthAuthenticator(callbackReceiver: nil)
        let handler = MCPOAuthHandler(authenticator: authenticator)
        #expect(handler.tokenStorage is RobustTokenStorage)
        let config = createMockMCPConfig()
        let credentials = try handler.extractOAuthCredentials(from: config)
        #expect(credentials.clientId == "test_client_id_123")
    }

    @Test("MCPOAuthHandler initializes with logger")
    func testInitializationWithLogger() async throws {
        let logger = Logger(label: "test.mcp.oauth")
        let handler = MCPOAuthHandler(logger: logger)
        #expect(handler.tokenStorage is RobustTokenStorage)
    }

    // MARK: - Token Storage Integration Tests

    @Test("OAuth handler integrates with robust token storage")
    func testOAuthHandlerIntegratesWithRobustStorage() async throws {
        let handler = MCPOAuthHandler()
        let serverName = "test_server_\(UUID().uuidString)"
        let token = createTestToken()

        try await handler.tokenStorage.storeToken(token, for: serverName)

        let retrievedToken = try await handler.tokenStorage.retrieveToken(for: serverName)

        #expect(retrievedToken != nil)
        #expect(retrievedToken?.accessToken == token.accessToken)
        #expect(retrievedToken?.tokenType == token.tokenType)
        #expect(retrievedToken?.expiresIn == token.expiresIn)
        #expect(retrievedToken?.refreshToken == token.refreshToken)
        #expect(retrievedToken?.scope == token.scope)

        try await handler.tokenStorage.removeToken(for: serverName)
    }

    @Test("OAuth handler integrates with token with config storage")
    func testOAuthHandlerIntegratesWithTokenWithConfigStorage() async throws {
        let handler = MCPOAuthHandler()
        let serverName = "test_server_\(UUID().uuidString)"
        let tokenWithConfig = createTestTokenWithConfig()

        try await handler.tokenStorage.storeTokenWithConfig(tokenWithConfig, for: serverName)

        let retrievedTokenWithConfig = try await handler.tokenStorage.retrieveTokenWithConfig(for: serverName)

        #expect(retrievedTokenWithConfig != nil)
        #expect(retrievedTokenWithConfig?.token.accessToken == tokenWithConfig.token.accessToken)
        #expect(retrievedTokenWithConfig?.tokenEndpoint == tokenWithConfig.tokenEndpoint)
        #expect(retrievedTokenWithConfig?.clientId == tokenWithConfig.clientId)
        #expect(retrievedTokenWithConfig?.clientSecret == tokenWithConfig.clientSecret)
        #expect(retrievedTokenWithConfig?.scope == tokenWithConfig.scope)

        try await handler.tokenStorage.removeToken(for: serverName)
    }

    // MARK: - Authentication Management Tests

    @Test("Has stored authentication works correctly")
    func testHasStoredAuthentication() async throws {
        let handler = MCPOAuthHandler()
        let serverName = "test_server_\(UUID().uuidString)"
        let token = createTestToken()

        let hasAuthInitially = await handler.hasStoredAuthentication(for: serverName)
        #expect(hasAuthInitially == false)

        try await handler.tokenStorage.storeToken(token, for: serverName)

        let hasAuthAfterStore = await handler.hasStoredAuthentication(for: serverName)
        #expect(hasAuthAfterStore == true)

        try await handler.tokenStorage.removeToken(for: serverName)

        let hasAuthAfterRemove = await handler.hasStoredAuthentication(for: serverName)
        #expect(hasAuthAfterRemove == false)
    }

    @Test("Remove authentication works correctly")
    func testRemoveAuthentication() async throws {
        let handler = MCPOAuthHandler()
        let serverName = "test_server_\(UUID().uuidString)"
        let token = createTestToken()

        try await handler.tokenStorage.storeToken(token, for: serverName)

        let hasAuthBeforeRemove = await handler.hasStoredAuthentication(for: serverName)
        #expect(hasAuthBeforeRemove == true)

        try await handler.removeAuthentication(for: serverName)

        let hasAuthAfterRemove = await handler.hasStoredAuthentication(for: serverName)
        #expect(hasAuthAfterRemove == false)
    }

    // MARK: - Configuration Parsing Tests

    @Test("Extract OAuth credentials from config works correctly")
    func testExtractOAuthCredentialsFromConfig() async throws {
        let handler = MCPOAuthHandler()
        let config = createMockMCPConfig()

        let credentials = try handler.extractOAuthCredentials(from: config)

        #expect(credentials.clientId == "test_client_id_123")
        #expect(credentials.clientSecret == "test_client_secret_456")
    }

    @Test("Extract OAuth credentials handles missing client ID")
    func testExtractOAuthCredentialsHandlesMissingClientId() async throws {
        let handler = MCPOAuthHandler()

        let authConfigDict: [String: Any] = [
            "clientSecret": "test_client_secret_456",
            "scope": "test_scope"
        ]

        let authConfig = try? JSON(authConfigDict)
        let config = MCPConfig.RemoteServerConfig(
            name: "test_server",
            url: "https://api.example.com/mcp",
            authType: "OAuth",
            authConfig: authConfig,
            connectionTimeout: 30.0,
            requestTimeout: 60.0,
            maxRetries: 3
        )

        do {
            _ = try handler.extractOAuthCredentials(from: config)
            #expect(Bool(false), "Should have thrown error for missing clientId")
        } catch let oauthError as OAuthError {
            #expect(oauthError.localizedDescription.contains("Missing clientId"))
        } catch {
            #expect(Bool(false), "Unexpected error type: \(type(of: error))")
        }
    }

    @Test("Extract OAuth credentials handles missing auth config")
    func testExtractOAuthCredentialsHandlesMissingAuthConfig() async throws {
        let handler = MCPOAuthHandler()

        let config = MCPConfig.RemoteServerConfig(
            name: "test_server",
            url: "https://api.example.com/mcp",
            authType: "OAuth",
            authConfig: nil,
            connectionTimeout: 30.0,
            requestTimeout: 60.0,
            maxRetries: 3
        )

        do {
            _ = try handler.extractOAuthCredentials(from: config)
            #expect(Bool(false), "Should have thrown error for missing authConfig")
        } catch let oauthError as OAuthError {
            #expect(oauthError.localizedDescription.contains("No auth configuration found"))
        } catch {
            #expect(Bool(false), "Unexpected error type: \(type(of: error))")
        }
    }

    @Test("Extract OAuth credentials handles optional client secret")
    func testExtractOAuthCredentialsHandlesOptionalClientSecret() async throws {
        let handler = MCPOAuthHandler()

        let authConfigDict: [String: Any] = [
            "clientId": "test_client_id_123",
            "scope": "test_scope"
        ]

        let authConfig = try? JSON(authConfigDict)
        let config = MCPConfig.RemoteServerConfig(
            name: "test_server",
            url: "https://api.example.com/mcp",
            authType: "OAuth",
            authConfig: authConfig,
            connectionTimeout: 30.0,
            requestTimeout: 60.0,
            maxRetries: 3
        )

        let credentials = try handler.extractOAuthCredentials(from: config)

        #expect(credentials.clientId == "test_client_id_123")
        #expect(credentials.clientSecret == nil)
    }

    // MARK: - Error Handling Tests

    @Test("Handles token storage errors gracefully")
    func testHandlesTokenStorageErrorsGracefully() async throws {
        let handler = MCPOAuthHandler(tokenStorage: InMemoryTokenStorage())
        let serverName = "test_server_\(UUID().uuidString)"
        let token = createTestToken()

        try await handler.tokenStorage.storeToken(token, for: serverName)

        let retrievedToken = try await handler.tokenStorage.retrieveToken(for: serverName)
        #expect(retrievedToken != nil)

        try await handler.tokenStorage.removeToken(for: serverName)
    }

    // MARK: - Performance Tests

    @Test("OAuth handler performance is acceptable")
    func testOAuthHandlerPerformance() async throws {
        let handler = MCPOAuthHandler(tokenStorage: InMemoryTokenStorage())
        let serverName = "test_server_\(UUID().uuidString)"
        let token = createTestToken()

        let storeTime = try await measureTime {
            try await handler.tokenStorage.storeToken(token, for: serverName)
        }

        let retrieveTime = try await measureTime {
            _ = await handler.hasStoredAuthentication(for: serverName)
        }

        let removeTime = try await measureTime {
            try await handler.removeAuthentication(for: serverName)
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
