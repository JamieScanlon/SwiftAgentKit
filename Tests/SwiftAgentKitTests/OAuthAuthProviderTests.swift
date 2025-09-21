//
//  OAuthAuthProviderTests.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/20/25.
//

import Testing
import Foundation
@testable import SwiftAgentKit

@Suite("OAuthAuthProvider Tests")
struct OAuthAuthProviderTests {
    
    // MARK: - Helper Methods
    
    private func createTestTokens(
        accessToken: String = "test-access-token",
        refreshToken: String? = "test-refresh-token",
        tokenType: String = "Bearer",
        expiresIn: TimeInterval? = 3600,
        scope: String? = "read write"
    ) -> OAuthTokens {
        return OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresIn: expiresIn,
            scope: scope
        )
    }
    
    private func createTestConfig(
        tokenEndpoint: String = "https://auth.example.com/token",
        clientId: String = "test-client-id",
        clientSecret: String? = "test-client-secret",
        scope: String? = "read write"
    ) throws -> OAuthConfig {
        return try OAuthConfig(
            tokenEndpoint: URL(string: tokenEndpoint)!,
            clientId: clientId,
            clientSecret: clientSecret,
            scope: scope
        )
    }
    
    // MARK: - Basic Tests
    
    @Test("OAuth provider should have correct scheme")
    func testScheme() async throws {
        let tokens = createTestTokens()
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: tokens, config: config)
        
        let scheme = await provider.scheme
        #expect(scheme == .oauth)
        #expect(scheme.rawValue == "OAuth")
    }
    
    @Test("Authentication headers should contain OAuth token")
    func testAuthenticationHeaders() async throws {
        let tokens = createTestTokens(accessToken: "oauth-access-123", tokenType: "Bearer")
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: tokens, config: config)
        
        let headers = try await provider.authenticationHeaders()
        
        #expect(headers.count == 1)
        #expect(headers["Authorization"] == "Bearer oauth-access-123")
    }
    
    @Test("Authentication headers should handle different token types")
    func testAuthenticationHeadersDifferentTokenTypes() async throws {
        let tokenTypes = ["Bearer", "MAC", "Custom"]
        
        for tokenType in tokenTypes {
            let tokens = createTestTokens(accessToken: "token-123", tokenType: tokenType)
            let config = try createTestConfig()
            let provider = OAuthAuthProvider(tokens: tokens, config: config)
            
            let headers = try await provider.authenticationHeaders()
            #expect(headers["Authorization"] == "\(tokenType) token-123")
        }
    }
    
    @Test("Authentication should be valid when token is not expired")
    func testIsAuthenticationValidNotExpired() async throws {
        _ = Date().addingTimeInterval(3600) // 1 hour from now
        let tokens = OAuthTokens(
            accessToken: "valid-token",
            refreshToken: "refresh-token",
            tokenType: "Bearer",
            expiresIn: nil,
            scope: nil
        )
        // Manually set expiration
        let tokensWithExpiration = OAuthTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            tokenType: tokens.tokenType,
            expiresIn: 3600, // This will set expiresAt to ~1 hour from now
            scope: tokens.scope
        )
        
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: tokensWithExpiration, config: config)
        
        let isValid = await provider.isAuthenticationValid()
        #expect(isValid == true)
    }
    
    @Test("Authentication should be invalid when token is expired")
    func testIsAuthenticationValidExpired() async throws {
        let expiredTokens = OAuthTokens(
            accessToken: "expired-token",
            refreshToken: "refresh-token",
            tokenType: "Bearer",
            expiresIn: -3600, // Expired 1 hour ago
            scope: nil
        )
        
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: expiredTokens, config: config)
        
        let isValid = await provider.isAuthenticationValid()
        #expect(isValid == false)
    }
    
    @Test("Authentication should be valid when no expiration is set")
    func testIsAuthenticationValidNoExpiration() async throws {
        let tokens = createTestTokens(expiresIn: nil)
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: tokens, config: config)
        
        let isValid = await provider.isAuthenticationValid()
        #expect(isValid == true)
    }
    
    // MARK: - Token Management Tests
    
    @Test("Get current access token should return correct token")
    func testGetCurrentAccessToken() async throws {
        let tokens = createTestTokens(accessToken: "current-access-token")
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: tokens, config: config)
        
        let currentToken = await provider.getCurrentAccessToken()
        #expect(currentToken == "current-access-token")
    }
    
    @Test("Get current tokens should return all token information")
    func testGetCurrentTokens() async throws {
        let originalTokens = createTestTokens(
            accessToken: "access-123",
            refreshToken: "refresh-456",
            tokenType: "Bearer",
            scope: "read write delete"
        )
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: originalTokens, config: config)
        
        let currentTokens = await provider.getCurrentTokens()
        
        #expect(currentTokens.accessToken == "access-123")
        #expect(currentTokens.refreshToken == "refresh-456")
        #expect(currentTokens.tokenType == "Bearer")
        #expect(currentTokens.scope == "read write delete")
    }
    
    @Test("Update tokens should change provider tokens")
    func testUpdateTokens() async throws {
        let initialTokens = createTestTokens(accessToken: "initial-token")
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: initialTokens, config: config)
        
        // Verify initial state
        let initialAccessToken = await provider.getCurrentAccessToken()
        #expect(initialAccessToken == "initial-token")
        
        // Update tokens
        let newTokens = createTestTokens(accessToken: "updated-token", refreshToken: "new-refresh")
        await provider.updateTokens(newTokens)
        
        // Verify updated state
        let updatedAccessToken = await provider.getCurrentAccessToken()
        let updatedTokens = await provider.getCurrentTokens()
        
        #expect(updatedAccessToken == "updated-token")
        #expect(updatedTokens.refreshToken == "new-refresh")
    }
    
    // MARK: - Authentication Challenge Tests
    
    @Test("Handle authentication challenge should throw when no refresh token")
    func testHandleAuthenticationChallengeNoRefreshToken() async throws {
        let tokens = createTestTokens(refreshToken: nil)
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: tokens, config: config)
        
        let challenge = AuthenticationChallenge(
            statusCode: 401,
            headers: [:],
            body: nil,
            serverInfo: "test-server"
        )
        
        await #expect(throws: AuthenticationError.self) {
            try await provider.handleAuthenticationChallenge(challenge)
        }
    }
    
    @Test("Handle authentication challenge should throw for non-401 status")
    func testHandleAuthenticationChallengeNon401() async throws {
        let tokens = createTestTokens()
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: tokens, config: config)
        
        let challenge = AuthenticationChallenge(
            statusCode: 403,
            headers: [:],
            body: nil,
            serverInfo: "test-server"
        )
        
        do {
            _ = try await provider.handleAuthenticationChallenge(challenge)
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as AuthenticationError {
            if case .authenticationFailed(let message) = error {
                #expect(message.contains("Unexpected status code: 403"))
            } else {
                #expect(Bool(false), "Should have thrown authenticationFailed error")
            }
        }
    }
    
    // MARK: - Cleanup Tests
    
    @Test("Cleanup should complete without errors")
    func testCleanup() async throws {
        let tokens = createTestTokens()
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: tokens, config: config)
        
        // Should not throw
        await provider.cleanup()
    }
    
    // MARK: - Concurrency Tests
    
    @Test("Multiple concurrent calls should work correctly")
    func testConcurrentCalls() async throws {
        let tokens = createTestTokens(accessToken: "concurrent-token", tokenType: "Bearer")
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: tokens, config: config)
        
        // Run multiple concurrent authentication header requests
        await withTaskGroup(of: [String: String].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    return (try? await provider.authenticationHeaders()) ?? [:]
                }
            }
            
            var results: [[String: String]] = []
            for await result in group {
                results.append(result)
            }
            
            // All results should be identical
            #expect(results.count == 10)
            let firstResult = results[0]
            for result in results {
                #expect(result == firstResult)
            }
            #expect(firstResult["Authorization"] == "Bearer concurrent-token")
        }
    }
    
    @Test("Concurrent token updates should work correctly")
    func testConcurrentTokenUpdates() async throws {
        let initialTokens = createTestTokens(accessToken: "initial")
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: initialTokens, config: config)
        
        // Run concurrent token updates
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    let newTokens = self.createTestTokens(accessToken: "token-\(i)")
                    await provider.updateTokens(newTokens)
                }
            }
        }
        
        // Verify that one of the updates succeeded (we can't predict which one due to concurrency)
        let finalToken = await provider.getCurrentAccessToken()
        #expect(finalToken.hasPrefix("token-"))
    }
    
    // MARK: - OAuthTokens Tests
    
    @Test("OAuthTokens should calculate expiration correctly")
    func testOAuthTokensExpirationCalculation() async throws {
        let beforeCreation = Date()
        let tokens = OAuthTokens(
            accessToken: "test",
            refreshToken: nil,
            tokenType: "Bearer",
            expiresIn: 3600,
            scope: nil
        )
        _ = Date()
        
        #expect(tokens.expiresAt != nil)
        
        if let expiresAt = tokens.expiresAt {
            // Should be approximately 1 hour from creation time
            let expectedExpiration = beforeCreation.addingTimeInterval(3600)
            let timeDifference = abs(expiresAt.timeIntervalSince(expectedExpiration))
            #expect(timeDifference < 5.0) // Within 5 seconds tolerance
        }
    }
    
    @Test("OAuthTokens should handle nil expiration")
    func testOAuthTokensNilExpiration() async throws {
        let tokens = OAuthTokens(
            accessToken: "test",
            refreshToken: nil,
            tokenType: "Bearer",
            expiresIn: nil,
            scope: nil
        )
        
        #expect(tokens.expiresAt == nil)
    }
    
    @Test("OAuthTokens should preserve all fields")
    func testOAuthTokensFieldPreservation() async throws {
        let tokens = OAuthTokens(
            accessToken: "access-token-123",
            refreshToken: "refresh-token-456",
            tokenType: "MAC",
            expiresIn: 7200,
            scope: "read write admin"
        )
        
        #expect(tokens.accessToken == "access-token-123")
        #expect(tokens.refreshToken == "refresh-token-456")
        #expect(tokens.tokenType == "MAC")
        #expect(tokens.expiresIn == 7200)
        #expect(tokens.scope == "read write admin")
        #expect(tokens.expiresAt != nil)
    }
    
    // MARK: - OAuthConfig Tests
    
    @Test("OAuthConfig should preserve all fields")
    func testOAuthConfigFieldPreservation() async throws {
        let tokenEndpoint = URL(string: "https://oauth.example.com/token")!
        let config = try OAuthConfig(
            tokenEndpoint: tokenEndpoint,
            clientId: "client-123",
            clientSecret: "secret-456",
            scope: "custom scope"
        )
        
        #expect(config.tokenEndpoint == tokenEndpoint)
        #expect(config.clientId == "client-123")
        #expect(config.clientSecret == "secret-456")
        #expect(config.scope == "custom scope")
    }
    
    @Test("OAuthConfig should handle optional fields")
    func testOAuthConfigOptionalFields() async throws {
        let tokenEndpoint = URL(string: "https://oauth.example.com/token")!
        let config = try OAuthConfig(
            tokenEndpoint: tokenEndpoint,
            clientId: "public-client",
            clientSecret: nil,
            scope: nil
        )
        
        #expect(config.tokenEndpoint == tokenEndpoint)
        #expect(config.clientId == "public-client")
        #expect(config.clientSecret == nil)
        #expect(config.scope == nil)
    }
    
    // MARK: - Edge Cases
    
    @Test("Provider should handle empty access token")
    func testEmptyAccessToken() async throws {
        let tokens = createTestTokens(accessToken: "")
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: tokens, config: config)
        
        let headers = try await provider.authenticationHeaders()
        #expect(headers["Authorization"] == "Bearer ")
    }
    
    @Test("Provider should handle special characters in tokens")
    func testSpecialCharactersInTokens() async throws {
        let specialToken = "token-with-!@#$%^&*()_+{}|:<>?[]\\;'\",./"
        let tokens = createTestTokens(accessToken: specialToken)
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: tokens, config: config)
        
        let headers = try await provider.authenticationHeaders()
        #expect(headers["Authorization"] == "Bearer \(specialToken)")
    }
    
    @Test("Provider should handle Unicode in tokens")
    func testUnicodeInTokens() async throws {
        let unicodeToken = "令牌-🔑-токен"
        let tokens = createTestTokens(accessToken: unicodeToken)
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: tokens, config: config)
        
        let headers = try await provider.authenticationHeaders()
        #expect(headers["Authorization"] == "Bearer \(unicodeToken)")
    }
    
    @Test("Provider should handle very long tokens")
    func testVeryLongTokens() async throws {
        let longToken = String(repeating: "a", count: 10000)
        let tokens = createTestTokens(accessToken: longToken)
        let config = try createTestConfig()
        let provider = OAuthAuthProvider(tokens: tokens, config: config)
        
        let headers = try await provider.authenticationHeaders()
        #expect(headers["Authorization"] == "Bearer \(longToken)")
        #expect(headers["Authorization"]?.count == 10007) // "Bearer " + 10000 chars
    }
    
    // MARK: - RFC 8707 Resource Parameter Tests
    
    @Test("OAuth configuration with resource parameter")
    func testOAuthConfigurationWithResourceParameter() throws {
        let tokenEndpoint = URL(string: "https://auth.example.com/token")!
        let resourceURI = "https://mcp.example.com/mcp"
        
        let config = try OAuthConfig(
            tokenEndpoint: tokenEndpoint,
            clientId: "test_client_id",
            clientSecret: "test_client_secret",
            scope: "mcp read write",
            resourceURI: resourceURI
        )
        
        #expect(config.tokenEndpoint == tokenEndpoint)
        #expect(config.clientId == "test_client_id")
        #expect(config.clientSecret == "test_client_secret")
        #expect(config.scope == "mcp read write")
        #expect(config.resourceURI == resourceURI)
    }
    
    @Test("OAuth configuration without resource parameter")
    func testOAuthConfigurationWithoutResourceParameter() throws {
        let tokenEndpoint = URL(string: "https://auth.example.com/token")!
        
        let config = try OAuthConfig(
            tokenEndpoint: tokenEndpoint,
            clientId: "test_client_id",
            resourceURI: nil
        )
        
        #expect(config.tokenEndpoint == tokenEndpoint)
        #expect(config.clientId == "test_client_id")
        #expect(config.resourceURI == nil)
    }
    
    @Test("OAuth configuration with invalid resource parameter should throw")
    func testOAuthConfigurationWithInvalidResourceParameter() {
        let tokenEndpoint = URL(string: "https://auth.example.com/token")!
        
        let invalidURIs = [
            "mcp.example.com", // Missing scheme
            "https://mcp.example.com#fragment", // Contains fragment
            "not-a-uri" // Invalid format
        ]
        
        for invalidURI in invalidURIs {
            #expect(throws: Error.self) {
                try OAuthConfig(
                    tokenEndpoint: tokenEndpoint,
                    clientId: "test_client_id",
                    resourceURI: invalidURI
                )
            }
        }
    }
    
    @Test("OAuth configuration resource parameter canonicalization")
    func testOAuthConfigurationResourceParameterCanonicalization() throws {
        let tokenEndpoint = URL(string: "https://auth.example.com/token")!
        
        let testCases: [(input: String, expected: String)] = [
            ("HTTPS://MCP.EXAMPLE.COM/MCP", "https://mcp.example.com/MCP"),
            ("https://mcp.example.com:443", "https://mcp.example.com"),
            ("https://mcp.example.com/", "https://mcp.example.com")
        ]
        
        for (input, expected) in testCases {
            let config = try OAuthConfig(
                tokenEndpoint: tokenEndpoint,
                clientId: "test_client_id",
                resourceURI: input
            )
            
            #expect(config.resourceURI == expected, "Input: \(input), Expected: \(expected), Got: \(config.resourceURI ?? "nil")")
        }
    }
}
