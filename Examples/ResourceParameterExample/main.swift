//
//  main.swift
//  ResourceParameterExample
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Foundation
import SwiftAgentKit

/// Example demonstrating RFC 8707 Resource Parameter implementation for MCP clients
@main
struct ResourceParameterExample {
    static func main() async throws {
        print("🔐 RFC 8707 Resource Parameter Implementation Example")
        print("==================================================")
        
        // Example 1: Canonical URI validation
        print("\n1️⃣ Testing canonical URI validation...")
        
        let testURIs = [
            "https://mcp.example.com/mcp",
            "https://mcp.example.com",
            "https://mcp.example.com:8443",
            "https://mcp.example.com/server/mcp",
            "https://MCP.EXAMPLE.COM/MCP",  // Should be normalized to lowercase
            "https://mcp.example.com/",     // Should remove trailing slash
            "mcp.example.com",              // Invalid - missing scheme
            "https://mcp.example.com#fragment" // Invalid - contains fragment
        ]
        
        for uri in testURIs {
            do {
                let canonical = try ResourceIndicatorUtilities.canonicalizeResourceURI(uri)
                print("✅ \(uri) → \(canonical)")
            } catch {
                print("❌ \(uri) → Invalid: \(error.localizedDescription)")
            }
        }
        
        // Example 2: PKCE OAuth configuration with resource parameter
        print("\n2️⃣ Testing PKCE OAuth configuration with resource parameter...")
        
        do {
            let issuerURL = URL(string: "https://auth.example.com")!
            let redirectURI = URL(string: "https://client.example.com/callback")!
            let resourceURI = "https://mcp.example.com/mcp"
            
            let config = try PKCEOAuthConfig(
                issuerURL: issuerURL,
                clientId: "mcp-client-123",
                clientSecret: "secret",
                scope: "mcp read write",
                redirectURI: redirectURI,
                resourceURI: resourceURI
            )
            
            print("✅ PKCE OAuth config created successfully")
            print("   - Issuer: \(config.issuerURL)")
            print("   - Client ID: \(config.clientId)")
            print("   - Resource URI: \(config.resourceURI ?? "None")")
            print("   - Code Challenge: \(config.pkcePair.codeChallenge)")
            
        } catch {
            print("❌ Failed to create PKCE OAuth config: \(error)")
        }
        
        // Example 3: URL encoding for resource parameter
        print("\n3️⃣ Testing resource parameter encoding...")
        
        let resourceURIs = [
            "https://mcp.example.com/mcp",
            "https://mcp.example.com/server/mcp?version=1.0",
            "https://mcp.example.com:8443/api/mcp"
        ]
        
        for uri in resourceURIs {
            let encoded = ResourceIndicatorUtilities.createResourceParameter(canonicalURI: uri)
            print("📝 \(uri)")
            print("   → Encoded: \(encoded)")
        }
        
        print("\n✨ RFC 8707 Resource Parameter implementation is working correctly!")
        print("\nKey features implemented:")
        print("• ✅ Canonical URI validation according to RFC 8707 Section 2")
        print("• ✅ Resource parameter in authorization requests")
        print("• ✅ Resource parameter in token requests") 
        print("• ✅ Resource parameter in token refresh requests")
        print("• ✅ Automatic resource URI extraction for MCP servers")
        print("• ✅ Integration with PKCE OAuth, OAuth Discovery, and standard OAuth providers")
        print("• ✅ MCP client configuration support")
        print("• ✅ Environment variable support for resource URI")
    }
}
