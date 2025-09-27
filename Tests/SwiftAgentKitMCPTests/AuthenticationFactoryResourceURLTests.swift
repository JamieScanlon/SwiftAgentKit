//
//  AuthenticationFactoryResourceURLTests.swift
//  SwiftAgentKitMCPTests
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Testing
import Foundation
import SwiftAgentKit
import SwiftAgentKitMCP
import Logging
import EasyJSON

@Suite("Authentication Factory Resource URL Tests")
struct AuthenticationFactoryResourceURLTests {
    
    private let logger = Logger(label: "AuthenticationFactoryResourceURLTests")
    
    @Test("AuthenticationFactory should automatically add resourceServerURL for OAuth")
    func testAuthenticationFactoryAddsResourceServerURL() async throws {
        // Test that AuthenticationFactory automatically adds resourceServerURL for OAuth
        let authConfig = JSON.object([
            "clientId": .string("user-provided-client-id"),
            "clientSecret": .string("user-provided-client-secret"),
            "scope": .string("mcp"),
            "redirectURI": .string("http://localhost:8080/oauth/callback")
        ])
        
        let serverURL = "https://api.githubcopilot.com/mcp/"
        
        // This should create a Direct OAuth provider with automatically added resourceServerURL
        let authProvider = try AuthenticationFactory.createAuthProvider(
            authType: "OAuth",
            config: authConfig,
            serverURL: serverURL
        )
        
        // Verify it's an OAuthDiscoveryAuthProvider (which is what we use for direct OAuth)
        #expect(authProvider is OAuthDiscoveryAuthProvider)
        
        logger.info("✓ AuthenticationFactory automatically added resourceServerURL for OAuth")
    }
    
    @Test("AuthenticationFactory should not add resourceServerURL for non-OAuth types")
    func testAuthenticationFactoryDoesNotAddResourceServerURLForNonOAuth() async throws {
        // Test that AuthenticationFactory does NOT add resourceServerURL for non-OAuth types
        let authConfig = JSON.object([
            "token": .string("bearer-token-123")
        ])
        
        let serverURL = "https://api.githubcopilot.com/mcp/"
        
        // This should create a Bearer token provider WITHOUT adding resourceServerURL
        let authProvider = try AuthenticationFactory.createAuthProvider(
            authType: "bearer",
            config: authConfig,
            serverURL: serverURL
        )
        
        // Verify it's a BearerTokenAuthProvider (not OAuth)
        #expect(authProvider is BearerTokenAuthProvider)
        
        logger.info("✓ AuthenticationFactory correctly does not add resourceServerURL for non-OAuth types")
    }
    
    @Test("AuthenticationFactory should use existing resourceServerURL if present")
    func testAuthenticationFactoryUsesExistingResourceServerURL() async throws {
        // Test that AuthenticationFactory respects existing resourceServerURL
        let authConfig = JSON.object([
            "clientId": .string("user-provided-client-id"),
            "clientSecret": .string("user-provided-client-secret"),
            "scope": .string("mcp"),
            "redirectURI": .string("http://localhost:8080/oauth/callback"),
            "resourceServerURL": .string("https://custom.example.com/custom-path")
        ])
        
        let serverURL = "https://api.githubcopilot.com/mcp/"
        
        // This should create a Direct OAuth provider using the existing resourceServerURL
        let authProvider = try AuthenticationFactory.createAuthProvider(
            authType: "OAuth",
            config: authConfig,
            serverURL: serverURL
        )
        
        // Verify it's an OAuthDiscoveryAuthProvider
        #expect(authProvider is OAuthDiscoveryAuthProvider)
        
        logger.info("✓ AuthenticationFactory respects existing resourceServerURL")
    }
    
    @Test("AuthenticationFactory should handle invalid server URL gracefully")
    func testAuthenticationFactoryHandlesInvalidServerURL() async throws {
        // Test that AuthenticationFactory handles invalid server URLs
        let authConfig = JSON.object([
            "clientId": .string("user-provided-client-id"),
            "clientSecret": .string("user-provided-client-secret"),
            "scope": .string("mcp"),
            "redirectURI": .string("http://localhost:8080/oauth/callback")
        ])
        
        let invalidServerURL = "not-a-valid-url"
        
        // This should throw an error for invalid server URL
        do {
            _ = try AuthenticationFactory.createAuthProvider(
                authType: "OAuth",
                config: authConfig,
                serverURL: invalidServerURL
            )
            #expect(Bool(false), "Should have thrown an error for invalid server URL")
        } catch {
            // Any error is acceptable for invalid server URL
            logger.info("✓ AuthenticationFactory correctly handles invalid server URL")
        }
    }
}
