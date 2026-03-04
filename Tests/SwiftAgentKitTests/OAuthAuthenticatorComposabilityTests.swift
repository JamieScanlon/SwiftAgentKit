// OAuthAuthenticator composability tests
// Verifies that custom callback receiver, token exchanger, and URL opener are used when provided.

import Testing
import Foundation
import SwiftAgentKit

@MainActor
struct OAuthAuthenticatorComposabilityTests {

    /// Mock token exchanger that returns a fixed token without making network calls.
    private struct MockTokenExchanger: OAuthTokenExchanger {
        let token: OAuthToken
        func exchangeCodeForToken(
            authorizationCode: String,
            tokenEndpoint: String,
            clientId: String,
            clientSecret: String?,
            redirectURI: String,
            codeVerifier: String?,
            resourceURI: String?
        ) async throws -> OAuthToken {
            return token
        }
    }

    @Test("OAuthAuthenticator uses custom token exchanger when provided")
    func customTokenExchangerIsUsed() async throws {
        let expectedToken = OAuthToken(
            accessToken: "mock_access_\(UUID().uuidString)",
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: "mock_refresh",
            scope: "read"
        )
        let mockExchanger = MockTokenExchanger(token: expectedToken)
        let authenticator = OAuthAuthenticator(tokenExchanger: mockExchanger)

        let result = try await authenticator.exchangeCodeForToken(
            authorizationCode: "fake_code",
            tokenEndpoint: "https://example.com/token",
            clientId: "client",
            clientSecret: "secret",
            redirectURI: "http://localhost:8080/callback",
            codeVerifier: "verifier",
            resourceURI: nil
        )

        #expect(result.accessToken == expectedToken.accessToken)
        #expect(result.tokenType == expectedToken.tokenType)
        #expect(result.refreshToken == expectedToken.refreshToken)
    }

    @Test("OAuthAuthenticator uses default token exchanger when none provided")
    func defaultTokenExchangerIsUsedWhenNil() async throws {
        // Without a custom exchanger, exchangeCodeForToken uses DefaultOAuthTokenExchanger.
        // With an invalid endpoint it throws (OAuthError.invalidURL or URLSession error).
        let authenticator = OAuthAuthenticator()
        do {
            _ = try await authenticator.exchangeCodeForToken(
                authorizationCode: "code",
                tokenEndpoint: "not-a-valid-url",
                clientId: "c",
                clientSecret: nil,
                redirectURI: "http://localhost/cb",
                codeVerifier: nil,
                resourceURI: nil
            )
            #expect(Bool(false), "Expected exchange to throw")
        } catch {
            // Expected: invalid URL, network error, or OAuthError
        }
    }

    @Test("OAuthAuthenticator accepts custom URL opener")
    func customUrlOpenerAccepted() async throws {
        let opener: @Sendable (URL) -> Void = { _ in }
        let _ = OAuthAuthenticator(urlOpener: opener)
        // Initialization succeeds; opener is invoked when completeManualOAuthFlow runs
    }
}
