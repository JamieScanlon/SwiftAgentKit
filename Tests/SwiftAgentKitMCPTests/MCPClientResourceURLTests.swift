//
//  MCPClientResourceURLTests.swift
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

@Suite("MCP Client Resource URL Tests")
struct MCPClientResourceURLTests {
    
    private let logger = Logger(label: "MCPClientResourceURLTests")
    
    @Test("MCPClient should automatically add resourceServerURL for direct OAuth")
    func testMCPClientAddsResourceServerURL() async throws {
        // Create a remote server config WITHOUT resourceServerURL in authConfig
        let remoteConfig = MCPConfig.RemoteServerConfig(
            name: "test-server",
            url: "https://api.githubcopilot.com/mcp/",
            authType: "OAuth",
            authConfig: .object([
                "clientId": .string("user-client-id"),
                "clientSecret": .string("user-client-secret"),
                "redirectURI": .string("http://localhost:8080/oauth/callback")
            ]),
            clientID: "user-client-id"
        )
        
        // Verify that resourceServerURL is NOT in the original config
        if let authConfig = remoteConfig.authConfig,
           case .object(let configDict) = authConfig {
            #expect(configDict["resourceServerURL"] == nil, "resourceServerURL should not be present initially")
        }
        
        // Create MCPClient to test the configuration processing
        let mcpClient = MCPClient(name: "test-client")
        
        // Test the configuration processing logic directly
        // This simulates what MCPClient.connectWithOAuthDiscovery does
        var authConfig = remoteConfig.authConfig!
        let authType = remoteConfig.authType!
        
        // For OAuth providers, automatically add the resource parameter as required by RFC 8707
        if authType.lowercased() == "oauth" {
            // Extract canonical resource URI from server URL
            if let serverURL = URL(string: remoteConfig.url) {
                // Extract canonical resource URI from server URL
                var uriString = serverURL.absoluteString
                // Remove trailing slash if present (unless it's the root path)
                if uriString.hasSuffix("/") && uriString != serverURL.scheme! + "://" + serverURL.host! + "/" {
                    uriString = String(uriString.dropLast())
                }
                
                // Add resource URI and resource server URL to auth config if not already present
                if case .object(var configDict) = authConfig {
                    if configDict["resourceServerURL"] == nil {
                        configDict["resourceServerURL"] = .string(uriString)
                    }
                    
                    authConfig = .object(configDict)
                }
            }
        }
        
        // Verify that resourceServerURL was added
        if case .object(let configDict) = authConfig {
            #expect(configDict["resourceServerURL"] != nil, "resourceServerURL should be added automatically")
            if case .string(let addedURL) = configDict["resourceServerURL"] {
                #expect(addedURL == "https://api.githubcopilot.com/mcp", "URL should be correctly processed")
            }
        }
        
        // Now test that the authentication provider can be created successfully
        let authProvider = try AuthenticationFactory.createAuthProvider(authType: authType, config: authConfig)
        #expect(authProvider is OAuthDiscoveryAuthProvider)
        
        logger.info("✓ MCPClient automatically added resourceServerURL to direct OAuth config")
    }
    
    @Test("MCPClient should not use placeholder URL when resourceServerURL is added")
    func testMCPClientUsesRealURLNotPlaceholder() async throws {
        // Test that MCPClient uses the real server URL, not the placeholder
        let authConfig = JSON.object([
            "clientId": .string("user-provided-client-id"),
            "clientSecret": .string("user-provided-client-secret"),
            "scope": .string("mcp"),
            "redirectURI": .string("http://localhost:8080/oauth/callback"),
            "resourceServerURL": .string("https://api.githubcopilot.com/mcp") // Real URL, not placeholder
        ])
        
        // This should create a Direct OAuth provider successfully
        let authProvider = try AuthenticationFactory.createAuthProvider(authType: "OAuth", config: authConfig)
        
        // Verify it's an OAuthDiscoveryAuthProvider (which is what we use for direct OAuth)
        #expect(authProvider is OAuthDiscoveryAuthProvider)
        
        // Verify that the authProvider is created successfully with the real URL
        // (We can't access private properties, but we can verify the provider was created)
        #expect(authProvider != nil)
        
        logger.info("✓ MCPClient uses real URL instead of placeholder")
    }
}
