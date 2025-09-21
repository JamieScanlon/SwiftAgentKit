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
    
}
