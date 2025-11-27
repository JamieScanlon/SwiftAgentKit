//
//  main.swift
//  OAuthDiscoveryExample
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Foundation
import SwiftAgentKit
import SwiftAgentKitMCP
import Logging

private var didConfigureLogging = false
private func configureLogging() {
    guard !didConfigureLogging else { return }
    didConfigureLogging = true
    SwiftAgentKitLogging.bootstrap(
        logger: Logger(label: "com.example.swiftagentkit.oauthdiscovery"),
        level: .info,
        metadata: SwiftAgentKitLogging.metadata(("example", .string("OAuthDiscovery")))
    )
}

@main
struct OAuthDiscoveryExample {
    private static let logger: Logger = {
        configureLogging()
        return SwiftAgentKitLogging.logger(for: .examples("OAuthDiscoveryExample"))
    }()
    
    static func main() async {
        logger.info("Starting OAuth Discovery Example")
        
        do {
            try await demonstrateOAuthDiscovery()
        } catch {
            logger.error("OAuth Discovery Example failed: \(error)")
        }
        
        logger.info("OAuth Discovery Example completed")
    }
    
    static func demonstrateOAuthDiscovery() async throws {
        logger.info("=== OAuth Discovery Demonstration ===")
        
        // Example 1: Manual OAuth Discovery Process
        try await demonstrateManualDiscovery()
        
        // Example 2: Using OAuth Discovery Authentication Provider
        try await demonstrateOAuthDiscoveryAuthProvider()
        
        // Example 3: Using OAuth Discovery with MCP Client
        try await demonstrateMCPWithOAuthDiscovery()
    }
    
    static func demonstrateManualDiscovery() async throws {
        logger.info("\n--- Manual OAuth Discovery Process ---")
        
        let resourceServerURL = URL(string: "https://mcp.example.com")!
        let discoveryManager = OAuthDiscoveryManager()
        
        logger.info("Step 1: Making unauthenticated request to trigger discovery")
        logger.info("Resource Server URL: \(resourceServerURL)")
        
        // In a real scenario, this would make an actual HTTP request
        // and receive a 401 response with WWW-Authenticate header
        logger.info("Step 2: Received 401 response with WWW-Authenticate header")
        logger.info("Step 3: Parsing WWW-Authenticate header for resource metadata")
        
        // Simulate parsing a WWW-Authenticate header
        let sampleHeader = "Bearer realm=\"mcp-server\", resource_metadata=\"https://mcp.example.com/.well-known/oauth-protected-resource/mcp\""
        let parameters = WWWAuthenticateParser.parseWWWAuthenticateHeader(sampleHeader)
        
        logger.info("Parsed parameters: \(parameters)")
        
        if let resourceMetadataURL = parameters["resource_metadata"] {
            logger.info("Found resource metadata URL: \(resourceMetadataURL)")
            logger.info("Step 4: Fetching protected resource metadata")
            logger.info("Step 5: Extracting authorization server URL from metadata")
            logger.info("Step 6: Discovering authorization server metadata")
            logger.info("Step 7: Validating PKCE support")
            logger.info("Step 8: Ready for OAuth 2.1 authorization flow")
        } else {
            logger.info("No resource metadata found in header, would try well-known URIs")
            logger.info("Would try: /.well-known/oauth-protected-resource/mcp")
            logger.info("Would try: /.well-known/oauth-protected-resource")
        }
    }
    
    static func demonstrateOAuthDiscoveryAuthProvider() async throws {
        logger.info("\n--- OAuth Discovery Authentication Provider ---")
        
        let resourceServerURL = URL(string: "https://mcp.example.com")!
        let redirectURI = URL(string: "https://client.example.com/callback")!
        
        // Create OAuth Discovery authentication provider
        let authProvider = OAuthDiscoveryAuthProvider(
            resourceServerURL: resourceServerURL,
            clientId: "example-client-id",
            clientSecret: "example-client-secret",
            scope: "openid profile email",
            redirectURI: redirectURI,
            resourceType: "mcp",
            preConfiguredAuthServerURL: nil
        )
        
        logger.info("Created OAuth Discovery authentication provider")
        logger.info("Resource Server: \(resourceServerURL)")
        logger.info("Client ID: example-client-id")
        logger.info("Redirect URI: \(redirectURI)")
        logger.info("Scope: openid profile email")
        
        // Check authentication status
        let isValid = await authProvider.isAuthenticationValid()
        logger.info("Authentication valid: \(isValid)")
        
        if !isValid {
            logger.info("Authentication not valid - would trigger discovery and OAuth flow")
            logger.info("This would:")
            logger.info("  1. Make unauthenticated request to resource server")
            logger.info("  2. Parse 401 response and WWW-Authenticate header")
            logger.info("  3. Discover protected resource metadata")
            logger.info("  4. Discover authorization server metadata")
            logger.info("  5. Validate PKCE support")
            logger.info("  6. Initiate OAuth 2.1 authorization flow")
            logger.info("  7. Exchange authorization code for access token")
            logger.info("  8. Use access token for authenticated requests")
        }
        
        // Cleanup
        await authProvider.cleanup()
        logger.info("Authentication provider cleaned up")
    }
    
    static func demonstrateMCPWithOAuthDiscovery() async throws {
        logger.info("\n--- MCP Client with OAuth Discovery ---")
        
        let resourceServerURL = URL(string: "https://mcp.example.com")!
        let redirectURI = URL(string: "https://client.example.com/callback")!
        
        // Create OAuth Discovery authentication provider
        let authProvider = OAuthDiscoveryAuthProvider(
            resourceServerURL: resourceServerURL,
            clientId: "mcp-client-id",
            clientSecret: "mcp-client-secret",
            scope: "mcp:read mcp:write",
            redirectURI: redirectURI,
            resourceType: "mcp"
        )
        
        // Create MCP client
        let mcpClient = MCPClient(
            name: "OAuthDiscoveryExample",
            version: "1.0",
            connectionTimeout: 30.0
        )
        
        logger.info("Created MCP client with OAuth Discovery authentication")
        logger.info("This setup would:")
        logger.info("  1. Automatically discover authorization server when connecting")
        logger.info("  2. Handle OAuth 2.1 flow transparently")
        logger.info("  3. Provide authenticated access to MCP server")
        logger.info("  4. Handle token refresh automatically")
        logger.info("  5. Support all MCP operations with proper authentication")
        
        // In a real scenario, you would connect like this:
        // try await mcpClient.connectToRemoteServer(
        //     serverURL: resourceServerURL,
        //     authProvider: authProvider
        // )
        
        logger.info("MCP client configured for OAuth Discovery authentication")
    }
}

// Additional demonstration functions

extension OAuthDiscoveryExample {
    
    static func demonstrateConfigurationOptions() {
        logger.info("\n--- Configuration Options ---")
        
        logger.info("OAuth Discovery supports multiple configuration options:")
        logger.info("")
        logger.info("1. Basic Configuration (minimal):")
        logger.info("   - resourceServerURL: URL of the MCP server")
        logger.info("   - clientId: OAuth client identifier")
        logger.info("   - redirectURI: OAuth redirect URI")
        logger.info("")
        logger.info("2. Advanced Configuration:")
        logger.info("   - clientSecret: OAuth client secret (for confidential clients)")
        logger.info("   - scope: OAuth scope string")
        logger.info("   - resourceType: Type of resource (default: 'mcp')")
        logger.info("   - preConfiguredAuthServerURL: Pre-known authorization server")
        logger.info("")
        logger.info("3. Discovery Strategies:")
        logger.info("   - WWW-Authenticate header parsing (RFC 9728)")
        logger.info("   - Well-known URI probing")
        logger.info("   - OpenID Connect Discovery fallback")
        logger.info("   - OAuth 2.0 Authorization Server Metadata fallback")
    }
    
    static func demonstrateErrorHandling() {
        logger.info("\n--- Error Handling ---")
        
        logger.info("The OAuth Discovery system provides comprehensive error handling:")
        logger.info("")
        logger.info("1. Discovery Errors:")
        logger.info("   - OAuthDiscoveryError.networkError")
        logger.info("   - OAuthDiscoveryError.invalidResponse")
        logger.info("   - OAuthDiscoveryError.httpError")
        logger.info("   - OAuthDiscoveryError.noAuthenticationRequired")
        logger.info("   - OAuthDiscoveryError.protectedResourceMetadataNotFound")
        logger.info("   - OAuthDiscoveryError.authorizationServerDiscoveryFailed")
        logger.info("")
        logger.info("2. Protected Resource Metadata Errors:")
        logger.info("   - ProtectedResourceMetadataError.discoveryFailed")
        logger.info("   - ProtectedResourceMetadataError.invalidResponse")
        logger.info("   - ProtectedResourceMetadataError.httpError")
        logger.info("   - ProtectedResourceMetadataError.pkceNotSupported")
        logger.info("   - ProtectedResourceMetadataError.invalidURL")
        logger.info("   - ProtectedResourceMetadataError.noAuthorizationServerURL")
        logger.info("")
        logger.info("3. OAuth Server Metadata Errors:")
        logger.info("   - OAuthMetadataError.discoveryFailed")
        logger.info("   - OAuthMetadataError.invalidResponse")
        logger.info("   - OAuthMetadataError.httpError")
        logger.info("   - OAuthMetadataError.pkceNotSupported")
        logger.info("   - OAuthMetadataError.invalidIssuerURL")
    }
    
    static func demonstrateSecurityFeatures() {
        logger.info("\n--- Security Features ---")
        
        logger.info("OAuth Discovery implements several security features:")
        logger.info("")
        logger.info("1. PKCE (Proof Key for Code Exchange):")
        logger.info("   - Mandatory S256 code challenge method")
        logger.info("   - Automatic PKCE pair generation")
        logger.info("   - Validation of server PKCE support")
        logger.info("")
        logger.info("2. Secure Token Handling:")
        logger.info("   - Automatic token refresh")
        logger.info("   - Secure token storage")
        logger.info("   - Token expiration validation")
        logger.info("")
        logger.info("3. Discovery Security:")
        logger.info("   - HTTPS-only discovery endpoints")
        logger.info("   - Validation of server metadata")
        logger.info("   - Fallback strategies for reliability")
        logger.info("")
        logger.info("4. OAuth 2.1 Compliance:")
        logger.info("   - Authorization code flow only")
        logger.info("   - PKCE mandatory for public clients")
        logger.info("   - Secure redirect URI validation")
    }
}
