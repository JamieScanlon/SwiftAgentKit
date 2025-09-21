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
    
    // MARK: - RFC 8707 Resource Parameter Tests
    
    @Test("Initialize PKCE OAuth configuration with resource parameter")
    func testInitializePKCEOAuthConfigurationWithResourceParameter() throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        let resourceURI = "https://mcp.example.com/mcp"
        
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "test_client_id",
            clientSecret: "test_client_secret",
            scope: "mcp read write",
            redirectURI: redirectURI,
            resourceURI: resourceURI
        )
        
        #expect(config.resourceURI == resourceURI)
        #expect(config.issuerURL == issuerURL)
        #expect(config.clientId == "test_client_id")
        #expect(config.scope == "mcp read write")
    }
    
    @Test("Resource parameter URI canonicalization during initialization")
    func testResourceParameterCanonicalization() throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        
        // Test cases for canonicalization
        let testCases: [(input: String, expected: String)] = [
            ("HTTPS://MCP.EXAMPLE.COM/MCP", "https://mcp.example.com/MCP"),
            ("https://mcp.example.com:443", "https://mcp.example.com"),
            ("https://mcp.example.com/", "https://mcp.example.com")
        ]
        
        for (input, expected) in testCases {
            let config = try PKCEOAuthConfig(
                issuerURL: issuerURL,
                clientId: "test_client_id",
                redirectURI: redirectURI,
                resourceURI: input
            )
            
            #expect(config.resourceURI == expected, "Input: \(input), Expected: \(expected), Got: \(config.resourceURI ?? "nil")")
        }
    }
    
    @Test("Invalid resource parameter URI should throw error")
    func testInvalidResourceParameterURI() {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        
        let invalidURIs = [
            "mcp.example.com", // Missing scheme
            "https://mcp.example.com#fragment", // Contains fragment
            "not-a-uri" // Invalid format
        ]
        
        for invalidURI in invalidURIs {
            #expect(throws: Error.self) {
                try PKCEOAuthConfig(
                    issuerURL: issuerURL,
                    clientId: "test_client_id",
                    redirectURI: redirectURI,
                    resourceURI: invalidURI
                )
            }
        }
    }
    
    @Test("PKCE OAuth configuration without resource parameter")
    func testPKCEOAuthConfigurationWithoutResourceParameter() throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "test_client_id",
            redirectURI: redirectURI,
            resourceURI: nil
        )
        
        #expect(config.resourceURI == nil)
        #expect(config.issuerURL == issuerURL)
        #expect(config.clientId == "test_client_id")
    }
    
    @Test("Resource parameter should be URL encoded correctly")
    func testResourceParameterURLEncoding() throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        let resourceURI = "https://mcp.example.com/mcp?version=1.0&type=api"
        
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "test_client_id",
            redirectURI: redirectURI,
            resourceURI: resourceURI
        )
        
        #expect(config.resourceURI != nil)
        
        // Test that the resource parameter can be properly encoded
        let encoded = ResourceIndicatorUtilities.createResourceParameter(canonicalURI: config.resourceURI!)
        #expect(encoded.contains("%3A%2F%2F")) // https://
        #expect(encoded.contains("%3F")) // ?
        #expect(encoded.contains("%3D")) // =
        #expect(encoded.contains("%26")) // &
    }
    
    @Test("Multiple MCP server resource URIs should be supported")
    func testMultipleMCPServerResourceURIs() throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        
        let mcpServerURIs = [
            "https://mcp1.example.com/mcp",
            "https://mcp2.example.com:8443/api/mcp",
            "https://api.example.com/v1/mcp/server1",
            "https://localhost:9000/mcp"
        ]
        
        for resourceURI in mcpServerURIs {
            let config = try PKCEOAuthConfig(
                issuerURL: issuerURL,
                clientId: "test_client_id",
                redirectURI: redirectURI,
                resourceURI: resourceURI
            )
            
            #expect(config.resourceURI != nil)
            #expect(ResourceIndicatorUtilities.isValidResourceURI(config.resourceURI!))
            
            // Ensure it can be properly encoded for OAuth requests
            let encoded = ResourceIndicatorUtilities.createResourceParameter(canonicalURI: config.resourceURI!)
            #expect(!encoded.isEmpty)
        }
    }
}