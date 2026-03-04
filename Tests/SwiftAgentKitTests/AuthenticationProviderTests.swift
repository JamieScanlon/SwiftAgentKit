//
//  AuthenticationProviderTests.swift
//  SwiftAgentKitTests
//

import Testing
import Foundation
import SwiftAgentKit

/// Tests for core Authentication types: AuthenticationScheme, AuthenticationChallenge, AuthenticationError
struct AuthenticationProviderTests {

    // MARK: - AuthenticationScheme

    @Test("AuthenticationScheme rawValue returns correct string for bearer")
    func schemeBearerRawValue() throws {
        #expect(AuthenticationScheme.bearer.rawValue == "Bearer")
    }

    @Test("AuthenticationScheme rawValue returns correct string for basic")
    func schemeBasicRawValue() throws {
        #expect(AuthenticationScheme.basic.rawValue == "Basic")
    }

    @Test("AuthenticationScheme rawValue returns correct string for apiKey")
    func schemeApiKeyRawValue() throws {
        #expect(AuthenticationScheme.apiKey.rawValue == "ApiKey")
    }

    @Test("AuthenticationScheme rawValue returns correct string for oauth")
    func schemeOAuthRawValue() throws {
        #expect(AuthenticationScheme.oauth.rawValue == "OAuth")
    }

    @Test("AuthenticationScheme rawValue returns custom string for custom scheme")
    func schemeCustomRawValue() throws {
        #expect(AuthenticationScheme.custom("CustomAuth").rawValue == "CustomAuth")
    }

    @Test("AuthenticationScheme init from bearer string")
    func schemeInitBearer() throws {
        #expect(AuthenticationScheme(rawValue: "bearer") == .bearer)
        #expect(AuthenticationScheme(rawValue: "Bearer") == .bearer)
        #expect(AuthenticationScheme(rawValue: "token") == .bearer)
    }

    @Test("AuthenticationScheme init from basic string")
    func schemeInitBasic() throws {
        #expect(AuthenticationScheme(rawValue: "basic") == .basic)
        #expect(AuthenticationScheme(rawValue: "Basic") == .basic)
    }

    @Test("AuthenticationScheme init from apiKey string")
    func schemeInitApiKey() throws {
        #expect(AuthenticationScheme(rawValue: "apikey") == .apiKey)
        #expect(AuthenticationScheme(rawValue: "api_key") == .apiKey)
    }

    @Test("AuthenticationScheme init from oauth string")
    func schemeInitOAuth() throws {
        #expect(AuthenticationScheme(rawValue: "oauth") == .oauth)
        #expect(AuthenticationScheme(rawValue: "OAuth") == .oauth)
    }

    @Test("AuthenticationScheme init from unknown string returns custom")
    func schemeInitCustom() throws {
        let scheme = AuthenticationScheme(rawValue: "x-custom-scheme")
        #expect(scheme != nil)
        if case .custom("x-custom-scheme") = scheme! {} else {
            Issue.record("Expected custom scheme")
        }
    }

    @Test("AuthenticationScheme init from unknown string is case-sensitive for custom")
    func schemeInitCustomPreservesValue() throws {
        let scheme = AuthenticationScheme(rawValue: "CustomScheme")
        #expect(scheme != nil)
        if case .custom(let value) = scheme! {
            #expect(value == "CustomScheme")
        } else {
            Issue.record("Expected custom scheme")
        }
    }

    @Test("AuthenticationScheme init from invalid string returns nil for empty")
    func schemeInitEmptyReturnsCustom() throws {
        let scheme = AuthenticationScheme(rawValue: "")
        #expect(scheme != nil)
        if case .custom("") = scheme! {} else {
            Issue.record("Expected custom with empty string")
        }
    }

    // MARK: - AuthenticationChallenge

    @Test("AuthenticationChallenge init stores all properties")
    func challengeInit() throws {
        let headers = ["WWW-Authenticate": "Bearer realm=\"api\""]
        let body = Data("error=invalid_token".utf8)
        let challenge = AuthenticationChallenge(
            statusCode: 401,
            headers: headers,
            body: body,
            serverInfo: "Test Server"
        )
        #expect(challenge.statusCode == 401)
        #expect(challenge.headers["WWW-Authenticate"] == "Bearer realm=\"api\"")
        #expect(challenge.body == body)
        #expect(challenge.serverInfo == "Test Server")
    }

    @Test("AuthenticationChallenge init with optional nil body and serverInfo")
    func challengeInitOptionalDefaults() throws {
        let challenge = AuthenticationChallenge(statusCode: 403, headers: [:])
        #expect(challenge.statusCode == 403)
        #expect(challenge.headers.isEmpty)
        #expect(challenge.body == nil)
        #expect(challenge.serverInfo == nil)
    }

    // MARK: - AuthenticationError

    @Test("AuthenticationError invalidCredentials has description")
    func errorInvalidCredentials() throws {
        let error = AuthenticationError.invalidCredentials
        #expect(error.localizedDescription.contains("Invalid authentication credentials"))
    }

    @Test("AuthenticationError authenticationExpired has description")
    func errorAuthenticationExpired() throws {
        let error = AuthenticationError.authenticationExpired
        #expect(error.localizedDescription.contains("expired"))
    }

    @Test("AuthenticationError authenticationFailed has message")
    func errorAuthenticationFailed() throws {
        let error = AuthenticationError.authenticationFailed("Token revoked")
        #expect(error.localizedDescription.contains("Token revoked"))
        #expect(error.localizedDescription.contains("Authentication failed"))
    }

    @Test("AuthenticationError unsupportedAuthScheme has scheme")
    func errorUnsupportedAuthScheme() throws {
        let error = AuthenticationError.unsupportedAuthScheme("digest")
        #expect(error.localizedDescription.contains("digest"))
        #expect(error.localizedDescription.contains("Unsupported"))
    }

    @Test("AuthenticationError networkError has message")
    func errorNetworkError() throws {
        let error = AuthenticationError.networkError("Connection timed out")
        #expect(error.localizedDescription.contains("Connection timed out"))
        #expect(error.localizedDescription.contains("Network error"))
    }

    @Test("AuthenticationError is Equatable")
    func errorEquatable() throws {
        #expect(AuthenticationError.invalidCredentials == AuthenticationError.invalidCredentials)
        #expect(AuthenticationError.authenticationFailed("x") == AuthenticationError.authenticationFailed("x"))
        #expect(AuthenticationError.authenticationFailed("x") != AuthenticationError.authenticationFailed("y"))
        #expect(AuthenticationError.invalidCredentials != AuthenticationError.authenticationExpired)
    }
}
