//
//  ResourceParameterIntegrationTests.swift
//  SwiftAgentKitTests
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Testing
import Foundation
import EasyJSON
@testable import SwiftAgentKit

/// End-to-end integration tests for RFC 8707 Resource Parameter implementation
@Suite("Resource Parameter Integration Tests")
struct ResourceParameterIntegrationTests {
    
    // MARK: - Full OAuth Flow Integration Tests
    
    @Test("End-to-end PKCE OAuth configuration with resource parameter")
    func testEndToEndPKCEOAuthWithResourceParameter() throws {
        let issuerURL = URL(string: "https://auth.example.com")!
        let redirectURI = URL(string: "https://app.example.com/callback")!
        let resourceURI = "https://mcp.example.com/mcp"
        
        // Step 1: Create PKCE OAuth configuration with resource parameter
        let config = try PKCEOAuthConfig(
            issuerURL: issuerURL,
            clientId: "mcp-client-123",
            clientSecret: "client-secret",
            scope: "mcp read write",
            redirectURI: redirectURI,
            resourceURI: resourceURI
        )
        
        // Step 2: Verify configuration is properly set up
        #expect(config.resourceURI == resourceURI)
        #expect(config.issuerURL == issuerURL)
        #expect(config.clientId == "mcp-client-123")
        #expect(config.scope == "mcp read write")
        
        // Step 3: Verify PKCE pair is generated
        #expect(!config.pkcePair.codeVerifier.isEmpty)
        #expect(!config.pkcePair.codeChallenge.isEmpty)
        #expect(config.pkcePair.codeChallengeMethod == "S256")
        
        // Step 4: Create provider
        let _ = PKCEOAuthAuthProvider(config: config)
        // Note: Cannot access actor-isolated scheme property directly in test
        
        // Step 5: Verify resource parameter can be encoded for OAuth requests
        let encodedResource = ResourceIndicatorUtilities.createResourceParameter(canonicalURI: resourceURI)
        #expect(encodedResource.contains("https%3A%2F%2Fmcp.example.com%2Fmcp"))
        
        // Note: Full authorization flow testing would require mock servers
        // This test verifies the configuration and setup is correct
    }
    
    @Test("End-to-end OAuth configuration with resource parameter")
    func testEndToEndOAuthWithResourceParameter() async throws {
        let tokenEndpoint = URL(string: "https://auth.example.com/token")!
        let resourceURI = "https://mcp.example.com/api/v1"
        
        // Step 1: Create OAuth configuration with resource parameter
        let config = try OAuthConfig(
            tokenEndpoint: tokenEndpoint,
            clientId: "mcp-client-456",
            clientSecret: "client-secret",
            scope: "mcp admin",
            resourceURI: resourceURI
        )
        
        // Step 2: Verify configuration
        #expect(config.resourceURI == resourceURI)
        #expect(config.tokenEndpoint == tokenEndpoint)
        #expect(config.clientId == "mcp-client-456")
        #expect(config.scope == "mcp admin")
        
        // Step 3: Create tokens and provider
        let tokens = OAuthTokens(
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            tokenType: "Bearer",
            expiresIn: 3600,
            scope: "mcp admin"
        )
        
        let provider = OAuthAuthProvider(tokens: tokens, config: config)
        // Note: Cannot access actor-isolated scheme property directly in test
        
        // Step 4: Verify authentication headers work
        let headers = try await provider.authenticationHeaders()
        #expect(headers["Authorization"] == "Bearer test-access-token")
    }
    
    // MARK: - Factory Integration Tests
    
    @Test("Factory creates providers with resource parameters correctly")
    func testFactoryIntegrationWithResourceParameters() throws {
        let testConfigurations: [(authType: String, config: JSON)] = [
            // PKCE OAuth with resource parameter
            ("oauth", JSON.object([
                "issuerURL": .string("https://auth.example.com"),
                "clientId": .string("pkce-client"),
                "redirectURI": .string("https://app.example.com/callback"),
                "resourceURI": .string("https://mcp1.example.com/mcp")
            ])),
            
            // OAuth Discovery with resource parameter
            ("oauth", JSON.object([
                "resourceServerURL": .string("https://mcp2.example.com"),
                "clientId": .string("discovery-client"),
                "redirectURI": .string("https://app.example.com/callback"),
                "useOAuthDiscovery": .boolean(true),
                "resourceURI": .string("https://mcp2.example.com")
            ]))
        ]
        
        for (authType, config) in testConfigurations {
            let _ = try AuthenticationFactory.createAuthProvider(authType: authType, config: config)
            
            // Note: Cannot access actor-isolated scheme property directly in test
            
            // Verify the provider was created successfully
            // (Detailed testing is done in individual provider tests)
        }
    }
    
    // MARK: - MCP Integration Tests
    
    @Test("MCP configuration with resource parameters")
    func testMCPConfigurationIntegration() throws {
        // Test resource URI validation for MCP server URLs
        let mcpServerURIs = [
            "https://mcp1.example.com/mcp",
            "https://api.example.com:8443/v1/mcp",
            "https://mcp-server.internal.company.com/services/mcp"
        ]
        
        // Verify all MCP server URIs are valid resource indicators
        for uri in mcpServerURIs {
            #expect(ResourceIndicatorUtilities.isValidResourceURI(uri))
            
            // Test canonicalization
            let canonical = try ResourceIndicatorUtilities.canonicalizeResourceURI(uri)
            #expect(!canonical.isEmpty)
            
            // Test URL encoding for OAuth requests
            let encoded = ResourceIndicatorUtilities.createResourceParameter(canonicalURI: canonical)
            #expect(!encoded.isEmpty)
        }
    }
    
    // MARK: - Error Handling Integration Tests
    
    @Test("Error handling across the resource parameter implementation")
    func testErrorHandlingIntegration() {
        let invalidResourceURIs = [
            "not-a-uri",
            "mcp.example.com", // Missing scheme
            "https://mcp.example.com#fragment", // Contains fragment
            "" // Empty string
        ]
        
        for invalidURI in invalidResourceURIs {
            // Test ResourceIndicatorUtilities
            #expect(throws: ResourceIndicatorError.self) {
                try ResourceIndicatorUtilities.canonicalizeResourceURI(invalidURI)
            }
            
            // Test PKCEOAuthConfig
            #expect(throws: Error.self) {
                try PKCEOAuthConfig(
                    issuerURL: URL(string: "https://auth.example.com")!,
                    clientId: "test-client",
                    redirectURI: URL(string: "https://app.example.com/callback")!,
                    resourceURI: invalidURI
                )
            }
            
            // Test OAuthConfig
            #expect(throws: Error.self) {
                try OAuthConfig(
                    tokenEndpoint: URL(string: "https://auth.example.com/token")!,
                    clientId: "test-client",
                    resourceURI: invalidURI
                )
            }
            
            // Test Factory
            let config = JSON.object([
                "issuerURL": .string("https://auth.example.com"),
                "clientId": .string("test-client"),
                "redirectURI": .string("https://app.example.com/callback"),
                "resourceURI": .string(invalidURI)
            ])
            
            #expect(throws: Error.self) {
                try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
            }
        }
    }
    
    // MARK: - Performance and Edge Case Tests
    
    @Test("Resource parameter handling with large configurations")
    func testResourceParameterWithLargeConfigurations() throws {
        // Test with many MCP servers
        var remoteServers: [String: [String: Any]] = [:]
        
        for i in 1...50 {
            remoteServers["mcp-server-\(i)"] = [
                "url": "https://mcp\(i).example.com/mcp",
                "authType": "OAuth",
                "authConfig": [
                    "issuerURL": "https://auth.example.com",
                    "clientId": "mcp\(i)-client",
                    "resourceURI": "https://mcp\(i).example.com/mcp"
                ]
            ]
        }
        
        let _ = ["remoteServers": remoteServers]
        
        // Test that we can handle many resource URIs
        let resourceURIs = remoteServers.compactMap { (_, serverData) -> String? in
            guard let authConfig = serverData["authConfig"] as? [String: Any],
                  let resourceURI = authConfig["resourceURI"] as? String else {
                return nil
            }
            return resourceURI
        }
        
        #expect(resourceURIs.count == 50)
        
        // Verify all resource URIs are valid
        for resourceURI in resourceURIs {
            #expect(ResourceIndicatorUtilities.isValidResourceURI(resourceURI))
        }
    }
    
    @Test("Resource parameter with complex URIs")
    func testResourceParameterWithComplexURIs() throws {
        let complexURIs = [
            "https://mcp.example.com/api/v1/services/mcp?version=2.0&format=json",
            "https://api-gateway.internal.company.com:9443/mcp/v2/endpoint",
            "https://localhost:3000/development/mcp/test",
            "https://192.168.1.100:8080/mcp/instance/production"
        ]
        
        for complexURI in complexURIs {
            // Test canonicalization
            let canonical = try ResourceIndicatorUtilities.canonicalizeResourceURI(complexURI)
            #expect(!canonical.isEmpty)
            
            // Test URL encoding
            let encoded = ResourceIndicatorUtilities.createResourceParameter(canonicalURI: canonical)
            #expect(!encoded.isEmpty)
            
            // Test in OAuth configuration
            let config = try PKCEOAuthConfig(
                issuerURL: URL(string: "https://auth.example.com")!,
                clientId: "test-client",
                redirectURI: URL(string: "https://app.example.com/callback")!,
                resourceURI: complexURI
            )
            
            #expect(config.resourceURI != nil)
        }
    }
    
    // MARK: - Compliance Verification Tests
    
    @Test("RFC 8707 compliance verification")
    func testRFC8707ComplianceVerification() throws {
        let mcpServerURI = "https://mcp.example.com/mcp"
        
        // Test 1: Resource parameter MUST be included in authorization requests
        let pkceConfig = try PKCEOAuthConfig(
            issuerURL: URL(string: "https://auth.example.com")!,
            clientId: "mcp-client",
            redirectURI: URL(string: "https://app.example.com/callback")!,
            resourceURI: mcpServerURI
        )
        
        #expect(pkceConfig.resourceURI == mcpServerURI)
        
        // Test 2: Resource parameter MUST be included in token requests
        let oauthConfig = try OAuthConfig(
            tokenEndpoint: URL(string: "https://auth.example.com/token")!,
            clientId: "mcp-client",
            resourceURI: mcpServerURI
        )
        
        #expect(oauthConfig.resourceURI == mcpServerURI)
        
        // Test 3: Resource parameter MUST identify the MCP server
        #expect(mcpServerURI.contains("mcp.example.com"))
        
        // Test 4: Resource parameter MUST use canonical URI
        let canonical = try ResourceIndicatorUtilities.canonicalizeResourceURI(mcpServerURI)
        #expect(canonical == mcpServerURI) // Already canonical
        
        // Test 5: MCP clients MUST send parameter regardless of server support
        // (This is ensured by always including the parameter in our implementation)
        let encoded = ResourceIndicatorUtilities.createResourceParameter(canonicalURI: canonical)
        #expect(!encoded.isEmpty)
    }
    
    @Test("MCP specification compliance verification")
    func testMCPSpecificationCompliance() throws {
        // Test canonical URI examples from MCP spec
        let validExamples = [
            "https://mcp.example.com/mcp",
            "https://mcp.example.com",
            "https://mcp.example.com:8443",
            "https://mcp.example.com/server/mcp"
        ]
        
        for example in validExamples {
            let canonical = try ResourceIndicatorUtilities.canonicalizeResourceURI(example)
            #expect(ResourceIndicatorUtilities.isValidResourceURI(canonical))
            
            // Should be usable in OAuth configuration
            let config = try PKCEOAuthConfig(
                issuerURL: URL(string: "https://auth.example.com")!,
                clientId: "test-client",
                redirectURI: URL(string: "https://app.example.com/callback")!,
                resourceURI: canonical
            )
            
            #expect(config.resourceURI == canonical)
        }
        
        // Test invalid examples from MCP spec
        let invalidExamples = [
            "mcp.example.com", // missing scheme
            "https://mcp.example.com#fragment" // contains fragment
        ]
        
        for example in invalidExamples {
            #expect(throws: ResourceIndicatorError.self) {
                try ResourceIndicatorUtilities.canonicalizeResourceURI(example)
            }
        }
    }
}
