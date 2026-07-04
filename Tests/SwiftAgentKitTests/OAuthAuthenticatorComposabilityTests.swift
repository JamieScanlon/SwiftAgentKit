// OAuthAuthenticator composability tests
// Verifies that custom callback receiver, token exchanger, and URL opener are used when provided.

import Testing
import Foundation
import SwiftAgentKit

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

    // MARK: - OAuth state validation

    private final class CapturingUrlOpener: @unchecked Sendable {
        private let lock = NSLock()
        private var _capturedURL: URL?

        var capturedURL: URL? {
            lock.lock()
            defer { lock.unlock() }
            return _capturedURL
        }

        var opener: @Sendable (URL) -> Void {
            { [weak self] url in
                guard let self else { return }
                self.lock.lock()
                self._capturedURL = url
                self.lock.unlock()
            }
        }
    }

    private struct ScriptedCallbackReceiver: OAuthCallbackReceiver {
        let result: OAuthCallbackServer.CallbackResult

        func waitForCallback(timeout: TimeInterval) async throws -> OAuthCallbackServer.CallbackResult {
            result
        }
    }

    private final class StateEchoCallbackReceiver: OAuthCallbackReceiver, @unchecked Sendable {
        private let capturer: CapturingUrlOpener

        init(capturer: CapturingUrlOpener) {
            self.capturer = capturer
        }

        func waitForCallback(timeout: TimeInterval) async throws -> OAuthCallbackServer.CallbackResult {
            let state = capturer.capturedURL.flatMap { url in
                URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "state" })?
                    .value
            }
            return OAuthCallbackServer.CallbackResult(
                authorizationCode: "test-code",
                state: state,
                error: nil,
                errorDescription: nil
            )
        }
    }

    private func makeManualFlowError() -> OAuthManualFlowRequired {
        OAuthManualFlowRequired(
            authorizationURL: URL(string: "https://auth.example.com/authorize")!,
            redirectURI: URL(string: "http://localhost:8080/oauth/callback")!,
            clientId: "test-client",
            additionalMetadata: [
                "authorization_endpoint": "https://auth.example.com/authorize",
                "token_endpoint": "https://auth.example.com/token"
            ]
        )
    }

    private func makeTestAuthenticator(
        capturer: CapturingUrlOpener,
        receiver: any OAuthCallbackReceiver
    ) -> OAuthAuthenticator {
        let token = OAuthToken(accessToken: "at", tokenType: "Bearer")
        return OAuthAuthenticator(
            callbackReceiver: receiver,
            tokenExchanger: MockTokenExchanger(token: token),
            urlOpener: capturer.opener
        )
    }

    @Test("completeManualOAuthFlow includes state in authorization URL")
    func manualFlowIncludesStateInAuthURL() async throws {
        let capturer = CapturingUrlOpener()
        let receiver = ScriptedCallbackReceiver(
            result: OAuthCallbackServer.CallbackResult(
                authorizationCode: "code",
                state: "placeholder",
                error: nil,
                errorDescription: nil
            )
        )
        let authenticator = makeTestAuthenticator(capturer: capturer, receiver: receiver)

        do {
            _ = try await authenticator.completeManualOAuthFlow(
                oauthFlowError: makeManualFlowError(),
                clientId: "test-client",
                clientSecret: nil
            )
        } catch OAuthError.stateMismatch {
            // Expected when callback state does not match generated state
        }

        let state = capturer.capturedURL.flatMap { url in
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "state" })?
                .value
        }
        #expect(state != nil)
        #expect(state?.isEmpty == false)
    }

    @Test("completeManualOAuthFlow succeeds when callback state matches")
    func manualFlowSucceedsWithMatchingState() async throws {
        let capturer = CapturingUrlOpener()
        let receiver = StateEchoCallbackReceiver(capturer: capturer)
        let authenticator = makeTestAuthenticator(capturer: capturer, receiver: receiver)

        let token = try await authenticator.completeManualOAuthFlow(
            oauthFlowError: makeManualFlowError(),
            clientId: "test-client",
            clientSecret: nil
        )

        #expect(token.accessToken == "at")
        #expect(token.tokenType == "Bearer")
    }

    @Test("completeManualOAuthFlow throws stateMismatch for mismatched callback state")
    func manualFlowThrowsOnStateMismatch() async throws {
        let capturer = CapturingUrlOpener()
        let receiver = ScriptedCallbackReceiver(
            result: OAuthCallbackServer.CallbackResult(
                authorizationCode: "code",
                state: "wrong-state",
                error: nil,
                errorDescription: nil
            )
        )
        let authenticator = makeTestAuthenticator(capturer: capturer, receiver: receiver)

        do {
            _ = try await authenticator.completeManualOAuthFlow(
                oauthFlowError: makeManualFlowError(),
                clientId: "test-client",
                clientSecret: nil
            )
            #expect(Bool(false), "Expected stateMismatch")
        } catch let error as OAuthError {
            if case .stateMismatch = error {
                // expected
            } else {
                #expect(Bool(false), "Expected stateMismatch, got \(error)")
            }
        }
    }

    @Test("completeManualOAuthFlow throws stateMismatch when callback state is missing")
    func manualFlowThrowsOnMissingState() async throws {
        let capturer = CapturingUrlOpener()
        let receiver = ScriptedCallbackReceiver(
            result: OAuthCallbackServer.CallbackResult(
                authorizationCode: "code",
                state: nil,
                error: nil,
                errorDescription: nil
            )
        )
        let authenticator = makeTestAuthenticator(capturer: capturer, receiver: receiver)

        do {
            _ = try await authenticator.completeManualOAuthFlow(
                oauthFlowError: makeManualFlowError(),
                clientId: "test-client",
                clientSecret: nil
            )
            #expect(Bool(false), "Expected stateMismatch")
        } catch let error as OAuthError {
            if case .stateMismatch = error {
                // expected
            } else {
                #expect(Bool(false), "Expected stateMismatch, got \(error)")
            }
        }
    }
}
