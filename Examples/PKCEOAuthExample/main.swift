//
//  main.swift
//  PKCEOAuthExample
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Foundation
import SwiftAgentKit

/// Example demonstrating PKCE OAuth authentication for MCP clients
/// This example shows how to implement PKCE OAuth as required by the MCP specification
struct PKCEOAuthExample {
    static func main() async {
        print("PKCE OAuth Example for MCP Clients")
        print("==================================")
        
        do {
            // Example 1: Generate PKCE code verifier and challenge
            print("\n1. Generating PKCE Code Verifier and Challenge")
            print("-----------------------------------------------")
            
            let pkcePair = try PKCEUtilities.generatePKCEPair()
            print("Code Verifier: \(pkcePair.codeVerifier)")
            print("Code Challenge: \(pkcePair.codeChallenge)")
            print("Code Challenge Method: \(pkcePair.codeChallengeMethod)")
            
            // Validate the PKCE pair
            let isValid = PKCEUtilities.validateCodeVerifier(pkcePair.codeVerifier, against: pkcePair.codeChallenge)
            print("PKCE Pair Validation: \(isValid ? "Valid" : "Invalid")")
            
            // Example 2: Create PKCE OAuth configuration
            print("\n2. Creating PKCE OAuth Configuration")
            print("------------------------------------")
            
            let issuerURL = URL(string: "https://auth.example.com")!
            let redirectURI = URL(string: "https://app.example.com/callback")!
            
            let pkceConfig = try PKCEOAuthConfig(
                issuerURL: issuerURL,
                clientId: "example_client_id",
                clientSecret: nil, // Public client
                scope: "openid profile email",
                redirectURI: redirectURI,
                useOpenIDConnectDiscovery: true
            )
            
            print("Issuer URL: \(pkceConfig.issuerURL)")
            print("Client ID: \(pkceConfig.clientId)")
            print("Redirect URI: \(pkceConfig.redirectURI)")
            print("Scope: \(pkceConfig.scope ?? "None")")
            print("Use OpenID Connect Discovery: \(pkceConfig.useOpenIDConnectDiscovery)")
            
            // Example 3: Create PKCE OAuth authentication provider
            print("\n3. Creating PKCE OAuth Authentication Provider")
            print("---------------------------------------------")
            
            let _ = PKCEOAuthAuthProvider(config: pkceConfig)
            print("Authentication Provider Created Successfully")
            print("Scheme: OAuth")
            
            // Example 4: Environment Variables for PKCE OAuth
            print("\n4. Environment Variables for PKCE OAuth")
            print("--------------------------------------")
            
            print("Required Environment Variables:")
            print("  SERVERNAME_PKCE_OAUTH_ISSUER_URL=https://auth.example.com")
            print("  SERVERNAME_PKCE_OAUTH_CLIENT_ID=your_client_id")
            print("  SERVERNAME_PKCE_OAUTH_REDIRECT_URI=https://app.example.com/callback")
            print("\nOptional Environment Variables:")
            print("  SERVERNAME_PKCE_OAUTH_CLIENT_SECRET=your_client_secret")
            print("  SERVERNAME_PKCE_OAUTH_SCOPE=openid profile")
            print("  SERVERNAME_PKCE_OAUTH_AUTHORIZATION_ENDPOINT=https://custom.example.com/oauth/authorize")
            print("  SERVERNAME_PKCE_OAUTH_TOKEN_ENDPOINT=https://custom.example.com/oauth/token")
            print("  SERVERNAME_PKCE_OAUTH_USE_OIDC_DISCOVERY=true")
            
            print("\n✅ PKCE OAuth implementation completed successfully!")
            print("\nKey Features Implemented:")
            print("• PKCE code verifier and challenge generation (RFC 7636)")
            print("• OAuth 2.1 compliance with S256 code challenge method")
            print("• Authorization server metadata discovery")
            print("• PKCE support validation as required by MCP spec")
            print("• Support for both public and confidential clients")
            print("• OpenID Connect Discovery support")
            print("• Environment variable configuration")
            print("• MCP configuration integration")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
}
