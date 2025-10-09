import Foundation
import SwiftAgentKit

/// Example demonstrating dynamic client registration with OAuth Discovery
/// This shows how SwiftAgentKit now automatically performs dynamic client registration
/// when the authorization server supports it (like Zapier)
struct DynamicClientRegistrationExample {
    static func main() async {
        print("🔐 Dynamic Client Registration Example")
        print("=====================================")
        print()
        
        // Example configuration for connecting to a server that supports dynamic client registration
        // (like Zapier MCP servers)
        let resourceServerURL = URL(string: "https://mcp.zapier.com/api/mcp/a/12345/mcp")!
        let redirectURI = URL(string: "http://localhost:8080/oauth/callback")!
        
        do {
            // Create OAuth Discovery provider with a fallback client ID
            // The system will automatically detect if dynamic client registration is supported
            // and perform it if the server has a registration_endpoint
            let authProvider = try OAuthDiscoveryAuthProvider(
                resourceServerURL: resourceServerURL,
                clientId: "swiftagentkit-mcp-client", // Fallback client ID
                scope: "mcp",
                redirectURI: redirectURI
            )
            
            print("✅ Created OAuth Discovery Auth Provider")
            print("   - Resource Server: \(resourceServerURL)")
            print("   - Fallback Client ID: swiftagentkit-mcp-client")
            print("   - Redirect URI: \(redirectURI)")
            print()
            
            print("🔄 Authentication Flow:")
            print("   1. OAuth Discovery will detect server metadata")
            print("   2. If registration_endpoint is found, dynamic client registration will be performed")
            print("   3. Registered client_id will be used for OAuth flow")
            print("   4. If no registration_endpoint, fallback client_id will be used")
            print()
            
            // Attempt to get authentication headers
            // This will trigger the full flow: discovery -> registration (if supported) -> OAuth
            print("🚀 Attempting authentication...")
            let headers = try await authProvider.authenticationHeaders()
            
            print("✅ Authentication successful!")
            print("   - Received headers: \(headers)")
            
        } catch let error as OAuthManualFlowRequired {
            // This is expected - the OAuth flow requires manual user intervention
            print("🔐 Manual OAuth flow required:")
            print("   - Authorization URL: \(error.authorizationURL)")
            print("   - Client ID: \(error.clientId)")
            print("   - Scope: \(error.scope ?? "none")")
            print()
            
            if let resourceURI = error.resourceURI {
                print("   - Resource URI: \(resourceURI)")
            }
            
            print("📝 Next steps:")
            print("   1. Open the authorization URL in a browser")
            print("   2. Complete the OAuth authorization")
            print("   3. Capture the authorization code from the redirect")
            print("   4. Use exchangeCodeForToken() to complete the flow")
            
            // Check if dynamic client registration was performed
            if error.clientId != "swiftagentkit-mcp-client" {
                print("🎉 Dynamic client registration was performed!")
                print("   - Using registered client ID: \(error.clientId)")
            } else {
                print("ℹ️  Using fallback client ID (no registration endpoint found)")
            }
            
        } catch {
            print("❌ Authentication failed: \(error)")
        }
    }
}
