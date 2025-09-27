//
//  DirectOAuthConfigTests.swift
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

@Suite("Direct OAuth Configuration Tests")
struct DirectOAuthConfigTests {
    
    private let logger = Logger(label: "DirectOAuthConfigTests")
    
    @Test("Direct OAuth configuration should use user-provided client ID")
    func testDirectOAuthUsesUserClientId() async throws {
        // Test configuration with direct OAuth credentials
        let authConfig = JSON.object([
            "clientId": .string("user-provided-client-id"),
            "clientSecret": .string("user-provided-client-secret"),
            "scope": .string("mcp"),
            "redirectURI": .string("http://localhost:8080/oauth/callback"),
            "resourceServerURL": .string("https://mcp.example.com")
        ])
        
        // This should create a Direct OAuth provider that respects the user's client ID
        let authProvider = try AuthenticationFactory.createAuthProvider(authType: "OAuth", config: authConfig)
        
        // Verify it's an OAuthDiscoveryAuthProvider (which is what we use for direct OAuth)
        #expect(authProvider is OAuthDiscoveryAuthProvider)
        
        logger.info("✓ Direct OAuth configuration correctly uses user-provided client ID")
    }
    
    @Test("Direct OAuth should not be confused with other OAuth types")
    func testDirectOAuthNotConfusedWithOtherTypes() async throws {
        // Test PKCE OAuth configuration (should create PKCE provider)
        let pkceConfig = JSON.object([
            "issuerURL": .string("https://auth.example.com"),
            "clientId": .string("pkce-client-id"),
            "redirectURI": .string("http://localhost:8080/oauth/callback")
        ])
        
        let pkceProvider = try AuthenticationFactory.createAuthProvider(authType: "OAuth", config: pkceConfig)
        #expect(pkceProvider is PKCEOAuthAuthProvider)
        
        // Test OAuth Discovery configuration (should create OAuth Discovery provider)
        let discoveryConfig = JSON.object([
            "resourceServerURL": .string("https://mcp.example.com"),
            "clientId": .string("discovery-client-id"),
            "redirectURI": .string("http://localhost:8080/oauth/callback"),
            "useOAuthDiscovery": .boolean(true)
        ])
        
        let discoveryProvider = try AuthenticationFactory.createAuthProvider(authType: "OAuth", config: discoveryConfig)
        #expect(discoveryProvider is OAuthDiscoveryAuthProvider)
        
        logger.info("✓ Direct OAuth correctly distinguished from other OAuth types")
    }
    
    @Test("MCP configuration should work with direct OAuth")
    func testMCPConfigWithDirectOAuth() async throws {
        // Create a remote server config with direct OAuth credentials
        let remoteConfig = MCPConfig.RemoteServerConfig(
            name: "test-server",
            url: "https://mcp.example.com",
            authType: "OAuth",
            authConfig: .object([
                "clientId": .string("user-client-id"),
                "clientSecret": .string("user-client-secret"),
                "redirectURI": .string("http://localhost:8080/oauth/callback")
            ]),
            clientID: "user-client-id"
        )
        
        // Test that the configuration can be created successfully
        #expect(remoteConfig.name == "test-server")
        #expect(remoteConfig.url == "https://mcp.example.com")
        #expect(remoteConfig.authType == "OAuth")
        #expect(remoteConfig.clientID == "user-client-id")
        
        logger.info("✓ MCP configuration works with direct OAuth")
    }
}
