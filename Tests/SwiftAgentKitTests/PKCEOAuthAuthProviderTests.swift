//
//  PKCEOAuthAuthProviderTests.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Testing
import Foundation
import SwiftAgentKit

@Suite("PKCEOAuthAuthProvider Tests")
struct PKCEOAuthAuthProviderTests {
    
    @Test("Initialize PKCE OAuth configuration")
    func testInitializePKCEOAuthConfiguration() throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "test_client_id",
            clientSecret: "test_client_secret",
            scope: "openid profile",
            redirectURI: redirectURI,
            useOpenIDConnectDiscovery: true
        )
        
        #expect(config.issuerURL == issuerURL)
        #expect(config.clientId == "test_client_id")
        #expect(config.clientSecret == "test_client_secret")
        #expect(config.scope == "openid profile")
        #expect(config.redirectURI == redirectURI)
        #expect(config.useOpenIDConnectDiscovery == true)
        #expect(config.pkcePair.codeChallengeMethod == "S256")
        #expect(!config.pkcePair.codeVerifier.isEmpty)
        #expect(!config.pkcePair.codeChallenge.isEmpty)
    }
    
    @Test("Initialize PKCE OAuth configuration - public client")
    func testInitializePKCEOAuthConfigurationPublicClient() throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "test_client_id",
            clientSecret: nil, // Public client
            scope: "openid profile",
            redirectURI: redirectURI,
            useOpenIDConnectDiscovery: true
        )
        
        #expect(config.clientSecret == nil)
        #expect(config.clientId == "test_client_id")
        #expect(config.scope == "openid profile")
    }
    
    @Test("Initialize PKCE OAuth authentication provider")
    func testInitializePKCEOAuthAuthenticationProvider() async throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "test_client_id",
            redirectURI: redirectURI
        )
        
        let provider = PKCEOAuthAuthProvider(config: config)
        
        #expect(await provider.scheme == .oauth)
    }
    
    @Test("Authentication not valid without tokens")
    func testAuthenticationNotValidWithoutTokens() async throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "test_client_id",
            redirectURI: redirectURI
        )
        
        let provider = PKCEOAuthAuthProvider(config: config)
        
        let isValid = await provider.isAuthenticationValid()
        #expect(isValid == false)
    }
    
    @Test("Authentication headers without tokens throws error")
    func testAuthenticationHeadersWithoutTokensThrowsError() async throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "test_client_id",
            redirectURI: redirectURI
        )
        
        let provider = PKCEOAuthAuthProvider(config: config)
        
        // Test that authentication headers throw an error when no tokens are available
        do {
            _ = try await provider.authenticationHeaders()
            #expect(Bool(false), "Expected authenticationHeaders to throw an error")
        } catch {
            #expect(error is AuthenticationError)
        }
    }
    
    @Test("Handle authentication challenge without tokens")
    func testHandleAuthenticationChallengeWithoutTokens() async throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "test_client_id",
            redirectURI: redirectURI
        )
        
        let provider = PKCEOAuthAuthProvider(config: config)
        
        let challenge = AuthenticationChallenge(
            statusCode: 401,
            headers: [:],
            body: nil,
            serverInfo: "Test server"
        )
        
        // Test that handleAuthenticationChallenge throws an error when no tokens are available
        do {
            _ = try await provider.handleAuthenticationChallenge(challenge)
            #expect(Bool(false), "Expected handleAuthenticationChallenge to throw an error")
        } catch {
            #expect(error is AuthenticationError)
        }
    }
    
    @Test("Cleanup provider")
    func testCleanupProvider() async throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "test_client_id",
            redirectURI: redirectURI
        )
        
        let provider = PKCEOAuthAuthProvider(config: config)
        
        await provider.cleanup()
        
        let isValid = await provider.isAuthenticationValid()
        #expect(isValid == false)
    }
    
    @Test("PKCE pair generation")
    func testPKCEPairGeneration() throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "test_client_id",
            redirectURI: redirectURI
        )
        
        // Test that PKCE pair is generated correctly
        #expect(config.pkcePair.codeChallengeMethod == "S256")
        #expect(!config.pkcePair.codeVerifier.isEmpty)
        #expect(!config.pkcePair.codeChallenge.isEmpty)
        #expect(config.pkcePair.codeVerifier.count >= 43)
        #expect(config.pkcePair.codeVerifier.count <= 128)
        #expect(config.pkcePair.codeChallenge.count == 43)
    }
    
    @Test("PKCE pair validation")
    func testPKCEPairValidation() throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "test_client_id",
            redirectURI: redirectURI
        )
        
        // Test that the code verifier matches the code challenge
        let isValid = PKCEUtilities.validateCodeVerifier(
            config.pkcePair.codeVerifier,
            against: config.pkcePair.codeChallenge
        )
        #expect(isValid == true)
    }
    
    @Test("Public client configuration")
    func testPublicClientConfiguration() throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "test_client_id",
            clientSecret: nil, // Public client
            redirectURI: redirectURI
        )
        
        #expect(config.clientSecret == nil)
        #expect(config.clientId == "test_client_id")
    }
    
    @Test("Confidential client configuration")
    func testConfidentialClientConfiguration() throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "test_client_id",
            clientSecret: "test_client_secret", // Confidential client
            redirectURI: redirectURI
        )
        
        #expect(config.clientSecret == "test_client_secret")
        #expect(config.clientId == "test_client_id")
    }
    
    @Test("Custom endpoints configuration")
    func testCustomEndpointsConfiguration() throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        let authEndpoint = URL(string: "https://custom.example.com/oauth/authorize")!
        let tokenEndpoint = URL(string: "https://custom.example.com/oauth/token")!
        
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "test_client_id",
            redirectURI: redirectURI,
            authorizationEndpoint: authEndpoint,
            tokenEndpoint: tokenEndpoint,
            useOpenIDConnectDiscovery: false
        )
        
        #expect(config.authorizationEndpoint == authEndpoint)
        #expect(config.tokenEndpoint == tokenEndpoint)
        #expect(config.useOpenIDConnectDiscovery == false)
    }
}