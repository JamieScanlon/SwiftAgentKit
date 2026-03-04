//
//  OAuthManualFlowTests.swift
//  SwiftAgentKitTests
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Testing
import SwiftAgentKit
import Foundation

/// Tests for the OAuthManualFlowRequired error type
struct OAuthManualFlowTests {
    
    @Test("OAuthManualFlowRequired should contain all necessary metadata")
    func testOAuthManualFlowRequiredMetadata() async throws {
        // Create a test OAuth manual flow required error
        let authURL = URL(string: "https://auth.example.com/authorize")!
        let redirectURI = URL(string: "com.example.app://oauth")!
        let clientId = "test-client-id"
        let scope = "read write"
        let resourceURI = "https://api.example.com"
        
        let additionalMetadata = [
            "authorization_endpoint": "https://auth.example.com/authorize",
            "token_endpoint": "https://auth.example.com/token",
            "code_challenge": "test-challenge",
            "code_challenge_method": "S256",
            "response_type": "code"
        ]
        
        let oauthError = OAuthManualFlowRequired(
            authorizationURL: authURL,
            redirectURI: redirectURI,
            clientId: clientId,
            scope: scope,
            resourceURI: resourceURI,
            additionalMetadata: additionalMetadata
        )
        
        // Verify the error structure
        #expect(oauthError.authorizationURL == authURL)
        #expect(oauthError.redirectURI == redirectURI)
        #expect(oauthError.clientId == clientId)
        #expect(oauthError.scope == scope)
        #expect(oauthError.resourceURI == resourceURI)
        #expect(oauthError.errorDescription?.contains("OAuth authorization flow requires manual user intervention") == true)
        
        // Verify additional metadata
        #expect(oauthError.additionalMetadata["authorization_endpoint"] == "https://auth.example.com/authorize")
        #expect(oauthError.additionalMetadata["token_endpoint"] == "https://auth.example.com/token")
        #expect(oauthError.additionalMetadata["code_challenge"] == "test-challenge")
        #expect(oauthError.additionalMetadata["code_challenge_method"] == "S256")
        #expect(oauthError.additionalMetadata["response_type"] == "code")
    }
    
    @Test("OAuthManualFlowRequired should work with minimal metadata")
    func testOAuthManualFlowRequiredMinimal() async throws {
        let authURL = URL(string: "https://auth.example.com/authorize")!
        let redirectURI = URL(string: "com.example.app://oauth")!
        let clientId = "test-client-id"
        
        let oauthError = OAuthManualFlowRequired(
            authorizationURL: authURL,
            redirectURI: redirectURI,
            clientId: clientId
        )
        
        // Verify the error structure with minimal metadata
        #expect(oauthError.authorizationURL == authURL)
        #expect(oauthError.redirectURI == redirectURI)
        #expect(oauthError.clientId == clientId)
        #expect(oauthError.scope == nil)
        #expect(oauthError.resourceURI == nil)
        #expect(oauthError.additionalMetadata.isEmpty)
        #expect(oauthError.errorDescription?.contains("OAuth authorization flow requires manual user intervention") == true)
    }
    
    @Test("OAuthManualFlowRequired should be Sendable")
    func testOAuthManualFlowRequiredSendable() async throws {
        let authURL = URL(string: "https://auth.example.com/authorize")!
        let redirectURI = URL(string: "com.example.app://oauth")!
        let clientId = "test-client-id"
        
        let oauthError = OAuthManualFlowRequired(
            authorizationURL: authURL,
            redirectURI: redirectURI,
            clientId: clientId
        )
        
        // Verify it can be used in concurrent contexts
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let _ = oauthError.authorizationURL
                let _ = oauthError.clientId
            }
            group.addTask {
                let _ = oauthError.redirectURI
                let _ = oauthError.errorDescription
            }
        }
    }

    // MARK: - OAuthToken (manual flow)

    @Test("OAuthToken init and Codable roundtrip")
    func oauthTokenCodable() throws {
        let token = OAuthToken(
            accessToken: "at_123",
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: "rt_456",
            scope: "read write"
        )
        let data = try JSONEncoder().encode(token)
        let decoded = try JSONDecoder().decode(OAuthToken.self, from: data)
        #expect(decoded.accessToken == token.accessToken)
        #expect(decoded.tokenType == token.tokenType)
        #expect(decoded.expiresIn == token.expiresIn)
        #expect(decoded.refreshToken == token.refreshToken)
        #expect(decoded.scope == token.scope)
    }

    @Test("OAuthToken CodingKeys use snake_case")
    func oauthTokenCodingKeys() throws {
        let token = OAuthToken(accessToken: "at", tokenType: "Bearer", expiresIn: 60, refreshToken: "rt", scope: "s")
        let data = try JSONEncoder().encode(token)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["access_token"] as? String == "at")
        #expect(json?["token_type"] as? String == "Bearer")
        #expect(json?["expires_in"] as? Int == 60)
        #expect(json?["refresh_token"] as? String == "rt")
        #expect(json?["scope"] as? String == "s")
    }

    @Test("OAuthToken optional fields")
    func oauthTokenOptionalFields() throws {
        let token = OAuthToken(accessToken: "at", tokenType: "Bearer")
        #expect(token.expiresIn == nil)
        #expect(token.refreshToken == nil)
        #expect(token.scope == nil)
    }

    // MARK: - OAuthError (manual flow)

    @Test("OAuthError has descriptions for key cases")
    func oauthErrorDescriptions() throws {
        #expect(OAuthError.invalidURL.localizedDescription.contains("Invalid OAuth URL"))
        #expect(OAuthError.userCancelled.localizedDescription.contains("cancelled"))
        #expect(OAuthError.authorizationCodeNotFound.localizedDescription.contains("Authorization code not found"))
        #expect(OAuthError.invalidTokenResponse.localizedDescription.contains("Invalid token response"))
        #expect(OAuthError.incorrectClientCredentials.localizedDescription.contains("client_id") || OAuthError.incorrectClientCredentials.localizedDescription.contains("client_secret"))
        #expect(OAuthError.invalidGrant.localizedDescription.contains("Invalid grant"))
        #expect(OAuthError.invalidConfiguration("x").localizedDescription.contains("x"))
    }

    @Test("OAuthError networkError and tokenExchangeFailed include message")
    func oauthErrorMessages() throws {
        let msg = "Connection failed"
        #expect(OAuthError.networkError(msg).localizedDescription.contains(msg))
        #expect(OAuthError.tokenExchangeFailed(msg).localizedDescription.contains(msg))
    }

    @Test("OAuthError oauthError includes error and optional description")
    func oauthErrorOAuthErrorCase() throws {
        let e = OAuthError.oauthError("invalid_scope", "Requested scope not allowed")
        #expect(e.localizedDescription.contains("invalid_scope"))
        #expect(e.localizedDescription.contains("Requested scope not allowed"))
        let e2 = OAuthError.oauthError("server_error", nil)
        #expect(e2.localizedDescription.contains("server_error"))
    }
}
