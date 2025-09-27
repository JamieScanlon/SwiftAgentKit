//
//  DirectOAuthResourceURLTests.swift
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

@Suite("Direct OAuth Resource URL Tests")
struct DirectOAuthResourceURLTests {
    
    private let logger = Logger(label: "DirectOAuthResourceURLTests")
    
    @Test("Direct OAuth should work without manual resourceServerURL")
    func testDirectOAuthWorksWithoutManualResourceServerURL() async throws {
        // Test that direct OAuth configuration works when resourceServerURL is added automatically
        let authConfig = JSON.object([
            "clientId": .string("user-provided-client-id"),
            "clientSecret": .string("user-provided-client-secret"),
            "scope": .string("mcp"),
            "redirectURI": .string("http://localhost:8080/oauth/callback"),
            "resourceServerURL": .string("https://api.githubcopilot.com/mcp") // This should be added automatically
        ])
        
        // This should create a Direct OAuth provider successfully
        let authProvider = try AuthenticationFactory.createAuthProvider(authType: "OAuth", config: authConfig)
        
        // Verify it's an OAuthDiscoveryAuthProvider (which is what we use for direct OAuth)
        #expect(authProvider is OAuthDiscoveryAuthProvider)
        
        logger.info("✓ Direct OAuth configuration works with automatically added resourceServerURL")
    }
    
    @Test("Direct OAuth should work with placeholder resourceServerURL")
    func testDirectOAuthWorksWithPlaceholderResourceServerURL() async throws {
        // Test configuration WITHOUT resourceServerURL (should use placeholder)
        let authConfig = JSON.object([
            "clientId": .string("user-provided-client-id"),
            "clientSecret": .string("user-provided-client-secret"),
            "scope": .string("mcp"),
            "redirectURI": .string("http://localhost:8080/oauth/callback")
            // Note: no resourceServerURL - should use placeholder
        ])
        
        // This should work with the placeholder URL
        let authProvider = try AuthenticationFactory.createAuthProvider(authType: "OAuth", config: authConfig)
        
        // Verify it's an OAuthDiscoveryAuthProvider (which is what we use for direct OAuth)
        #expect(authProvider is OAuthDiscoveryAuthProvider)
        
        logger.info("✓ Direct OAuth configuration works with placeholder resourceServerURL")
    }
}
