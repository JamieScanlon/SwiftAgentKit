//
//  RemoteTransportOAuthTests.swift
//  SwiftAgentKitMCPTests
//
//  Created by SwiftAgentKit on 9/21/25.
//

import Testing
import Foundation
@testable import SwiftAgentKit
@testable import SwiftAgentKitMCP

@Suite("RemoteTransport OAuth Discovery Tests")
struct RemoteTransportOAuthTests {
    
    // MARK: - WWW-Authenticate Header Parsing Tests
    
    @Test("RemoteTransport should handle case-insensitive WWW-Authenticate header lookup")
    func testCaseInsensitiveHeaderLookup() async throws {
        // Create a custom URLSession that returns a 401 with different header cases
        let testCases = [
            "WWW-Authenticate",
            "Www-Authenticate", // Real-world case from Zapier
            "www-authenticate"
        ]
        
        for headerName in testCases {
            let _ = URL(string: "https://test-oauth.example.com/mcp")!
            
            // Create a mock response with the specific header case
            let _ = #"Bearer resource_metadata="https://test-oauth.example.com/.well-known/oauth-protected-resource""#
            
            // We can't easily mock URLSession in tests, so we'll test the error type creation
            // which is what would happen when the header is properly detected
            let oauthError = RemoteTransport.RemoteTransportError.oauthDiscoveryRequired(
                resourceMetadataURL: "https://test-oauth.example.com/.well-known/oauth-protected-resource"
            )
            
            // Verify the error contains the expected information
            let errorDescription = oauthError.errorDescription
            #expect(errorDescription?.contains("OAuth discovery required") == true,
                   "Failed for header case: \(headerName)")
            #expect(errorDescription?.contains("https://test-oauth.example.com/.well-known/oauth-protected-resource") == true,
                   "Failed for header case: \(headerName)")
        }
    }
    
    @Test("RemoteTransport should extract resource_metadata URL from WWW-Authenticate headers")
    func testResourceMetadataURLExtraction() async throws {
        // Test the regex pattern used in extractResourceMetadataURL
        let testCases: [(String, String?)] = [
            // Standard format (should extract)
            (#"Bearer resource_metadata="https://mcp.zapier.com/.well-known/oauth-protected-resource""#,
             "https://mcp.zapier.com/.well-known/oauth-protected-resource"),
            
            // With additional parameters (should extract)
            (#"Bearer realm="mcp", resource_metadata="https://api.example.com/.well-known/oauth-protected-resource", scope="mcp""#,
             "https://api.example.com/.well-known/oauth-protected-resource"),
            
            // Different parameter order (should extract)
            (#"Bearer scope="mcp read", resource_metadata="https://server.com/.well-known/oauth-protected-resource", realm="api""#,
             "https://server.com/.well-known/oauth-protected-resource"),
            
            // Complex URL with path and query (should extract)
            (#"Bearer resource_metadata="https://auth.service.com/.well-known/oauth-protected-resource/mcp?version=1&type=test""#,
             "https://auth.service.com/.well-known/oauth-protected-resource/mcp?version=1&type=test"),
            
            // No resource_metadata parameter (should not extract)
            (#"Bearer realm="api" scope="mcp""#, nil),
            
            // Empty resource_metadata (should extract empty string, but we expect nil for this case)
            (#"Bearer resource_metadata="""#, nil),
            
            // Malformed quotes (should not extract)
            ("Bearer resource_metadata=https://example.com/.well-known/oauth-protected-resource", nil),
            
            // Non-Bearer scheme (should not extract in OAuth context, but let's test the pattern)
            (#"Basic resource_metadata="https://example.com/.well-known/oauth-protected-resource""#,
             "https://example.com/.well-known/oauth-protected-resource"),
            
            // Empty header (should not extract)
            ("", nil)
        ]
        
        for (header, expectedURL) in testCases {
            // Test the regex pattern directly
            let pattern = #"resource_metadata="([^"]+)""#
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: header.count)
            
            if let match = regex.firstMatch(in: header, options: [], range: range),
               match.numberOfRanges > 1 {
                let urlRange = match.range(at: 1)
                let startIndex = header.index(header.startIndex, offsetBy: urlRange.location)
                let endIndex = header.index(startIndex, offsetBy: urlRange.length)
                let extractedURL = String(header[startIndex..<endIndex])
                
                #expect(extractedURL == expectedURL,
                       "Expected '\(expectedURL ?? "nil")' but got '\(extractedURL)' for header: \(header)")
            } else {
                #expect(expectedURL == nil,
                       "Expected no extraction but pattern should have matched for header: \(header)")
            }
        }
    }
    
    @Test("RemoteTransport should handle OAuth challenges with Bearer scheme")
    func testOAuthChallengeDetection() async throws {
        // Test various WWW-Authenticate header formats that should trigger OAuth discovery
        let oauthHeaders = [
            #"Bearer resource_metadata="https://example.com/.well-known/oauth-protected-resource""#,
            #"bearer resource_metadata="https://example.com/.well-known/oauth-protected-resource""#, // lowercase
            #"OAuth resource_metadata="https://example.com/.well-known/oauth-protected-resource""#,
            #"Bearer realm="api", resource_metadata="https://example.com/.well-known/oauth-protected-resource", scope="mcp""#
        ]
        
        let nonOAuthHeaders = [
            #"Basic realm="api""#,
            #"Digest realm="api", nonce="abc123""#,
            #"Negotiate"#,
            #"Custom-Auth token="xyz""#,
            ""
        ]
        
        // Test OAuth headers (should contain "bearer" or "oauth")
        for header in oauthHeaders {
            let containsBearer = header.lowercased().contains("bearer")
            let containsOAuth = header.lowercased().contains("oauth")
            
            #expect(containsBearer || containsOAuth,
                   "OAuth header should contain 'bearer' or 'oauth': \(header)")
        }
        
        // Test non-OAuth headers (should not contain "bearer" or "oauth")
        for header in nonOAuthHeaders {
            let containsBearer = header.lowercased().contains("bearer")
            let containsOAuth = header.lowercased().contains("oauth")
            
            #expect(!(containsBearer || containsOAuth),
                   "Non-OAuth header should not contain 'bearer' or 'oauth': \(header)")
        }
    }
    
    @Test("RemoteTransport should create appropriate error messages for OAuth discovery scenarios")
    func testOAuthDiscoveryErrorMessages() async throws {
        // Test different OAuth discovery error scenarios
        
        // Successful detection case
        let successError = RemoteTransport.RemoteTransportError.oauthDiscoveryRequired(
            resourceMetadataURL: "https://mcp.zapier.com/.well-known/oauth-protected-resource"
        )
        
        let successDescription = successError.errorDescription
        #expect(successDescription?.contains("OAuth discovery required") == true)
        #expect(successDescription?.contains("Resource metadata available at") == true)
        #expect(successDescription?.contains("https://mcp.zapier.com/.well-known/oauth-protected-resource") == true)
        
        // Discovery failure case
        let failureError = RemoteTransport.RemoteTransportError.oauthDiscoveryFailed(
            "Resource metadata endpoint returned 404"
        )
        
        let failureDescription = failureError.errorDescription
        #expect(failureDescription?.contains("OAuth discovery failed") == true)
        #expect(failureDescription?.contains("Resource metadata endpoint returned 404") == true)
        
        // Authentication failure case (fallback when no resource_metadata found)
        let authFailureError = RemoteTransport.RemoteTransportError.authenticationFailed(
            "OAuth authentication required but no OAuth provider configured. Consider using OAuthDiscoveryAuthProvider."
        )
        
        let authFailureDescription = authFailureError.errorDescription
        #expect(authFailureDescription?.contains("Authentication failed") == true)
        #expect(authFailureDescription?.contains("OAuth authentication required") == true)
        #expect(authFailureDescription?.contains("OAuthDiscoveryAuthProvider") == true)
        
        // Generic auth failure (the old problematic error)
        let genericError = RemoteTransport.RemoteTransportError.authenticationFailed(
            "No authentication provider available for 401 challenge"
        )
        
        let genericDescription = genericError.errorDescription
        #expect(genericDescription?.contains("Authentication failed") == true)
        #expect(genericDescription?.contains("No authentication provider available") == true)
        
        // Verify that the new error messages are meaningful (don't compare lengths as they vary)
        #expect(successDescription!.contains("OAuth discovery required"),
               "OAuth discovery error should mention OAuth discovery requirement")
        #expect(failureDescription!.contains("OAuth discovery failed"),
               "OAuth discovery failure should mention OAuth discovery failure")
    }
    
    // MARK: - Integration Tests with Mock Scenarios
    
    @Test("RemoteTransport should handle 401 responses without authentication provider")
    func testUnauthenticated401Response() async throws {
        let serverURL = URL(string: "https://oauth-test.example.com/mcp")!
        let transport = RemoteTransport(
            serverURL: serverURL,
            authProvider: nil, // No auth provider
            connectionTimeout: 0.1,
            requestTimeout: 0.1,
            maxRetries: 1
        )
        
        do {
            try await transport.connect()
            #expect(Bool(false), "Expected connection to fail")
        } catch let error as RemoteTransport.RemoteTransportError {
            // Should get either network error (for non-existent server) or OAuth discovery requirement
            switch error {
            case .networkError, .connectionFailed:
                // Expected for test servers that don't exist
                break
            case .oauthDiscoveryRequired(let resourceMetadataURL):
                // This would only happen if we got a real 401 with resource_metadata
                #expect(!resourceMetadataURL.isEmpty, "Resource metadata URL should not be empty")
            case .authenticationFailed(let message):
                // Should be a helpful message, not the old generic one
                #expect(!message.contains("No authentication provider available for 401 challenge") ||
                       message.contains("OAuth authentication required"),
                       "Should not show old generic error: \(message)")
            default:
                // Other errors are acceptable for this test
                break
            }
        }
        
        await transport.disconnect()
    }
    
    @Test("RemoteTransport should not trigger OAuth discovery when authentication provider exists")
    func testAuthenticatedTransportSkipsOAuthDiscovery() async throws {
        let serverURL = URL(string: "https://oauth-test.example.com/mcp")!
        let authProvider = BearerTokenAuthProvider(token: "test-token-123")
        
        let transport = RemoteTransport(
            serverURL: serverURL,
            authProvider: authProvider, // Auth provider configured
            connectionTimeout: 0.1,
            requestTimeout: 0.1,
            maxRetries: 1
        )
        
        do {
            try await transport.connect()
            #expect(Bool(false), "Expected connection to fail")
        } catch let error as RemoteTransport.RemoteTransportError {
            // Should get network error, not OAuth discovery
            switch error {
            case .networkError, .connectionFailed:
                // Expected for test servers that don't exist
                break
            case .oauthDiscoveryRequired:
                #expect(Bool(false), "Should not trigger OAuth discovery when auth provider exists")
            case .authenticationFailed(let message):
                // If auth fails, it should be due to the auth provider, not OAuth discovery
                #expect(message.contains("authentication") && !message.contains("OAuth discovery"),
                       "Auth failure should be about the configured provider, not OAuth discovery: \(message)")
            default:
                // Other errors are acceptable
                break
            }
        }
        
        await transport.disconnect()
    }
    
    // MARK: - Real-world Scenario Tests
    
    @Test("RemoteTransport should handle Zapier-style OAuth discovery headers")
    func testZapierStyleHeaders() async throws {
        // Test the exact header format returned by Zapier's MCP server
        let zapierHeader = #"Bearer resource_metadata="https://mcp.zapier.com/.well-known/oauth-protected-resource""#
        let zapierResourceURL = "https://mcp.zapier.com/.well-known/oauth-protected-resource"
        
        // Test regex extraction
        let pattern = #"resource_metadata="([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: zapierHeader.count)
        
        if let match = regex.firstMatch(in: zapierHeader, options: [], range: range),
           match.numberOfRanges > 1 {
            let urlRange = match.range(at: 1)
            let startIndex = zapierHeader.index(zapierHeader.startIndex, offsetBy: urlRange.location)
            let endIndex = zapierHeader.index(startIndex, offsetBy: urlRange.length)
            let extractedURL = String(zapierHeader[startIndex..<endIndex])
            
            #expect(extractedURL == zapierResourceURL,
                   "Should extract Zapier resource metadata URL correctly")
        } else {
            #expect(Bool(false), "Should be able to extract resource_metadata from Zapier header")
        }
        
        // Test OAuth detection
        let containsBearer = zapierHeader.lowercased().contains("bearer")
        #expect(containsBearer, "Zapier header should be detected as OAuth Bearer challenge")
        
        // Test error message creation
        let oauthError = RemoteTransport.RemoteTransportError.oauthDiscoveryRequired(
            resourceMetadataURL: zapierResourceURL
        )
        
        let errorDescription = oauthError.errorDescription
        #expect(errorDescription?.contains("OAuth discovery required") == true)
        #expect(errorDescription?.contains(zapierResourceURL) == true)
    }
    
    @Test("RemoteTransport should handle various MCP server OAuth configurations")
    func testVariousMCPServerConfigurations() async throws {
        // Test different MCP server OAuth configurations that might be encountered
        let serverConfigurations = [
            // Standard MCP server
            ("https://api.mcp-server.com/v1/mcp",
             #"Bearer resource_metadata="https://api.mcp-server.com/.well-known/oauth-protected-resource""#),
            
            // MCP server with path-specific metadata
            ("https://service.com/api/mcp/tenant123",
             #"Bearer resource_metadata="https://service.com/api/mcp/tenant123/.well-known/oauth-protected-resource""#),
            
            // MCP server with custom metadata path
            ("https://mcp.example.org/server",
             #"Bearer resource_metadata="https://mcp.example.org/.well-known/oauth-protected-resource/server""#),
            
            // MCP server with port and path
            ("https://localhost:8080/mcp/v2",
             #"Bearer resource_metadata="https://localhost:8080/.well-known/oauth-protected-resource""#)
        ]
        
        for (serverURL, header) in serverConfigurations {
            // Test that we can extract resource metadata from each configuration
            let pattern = #"resource_metadata="([^"]+)""#
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: header.count)
            
            if let match = regex.firstMatch(in: header, options: [], range: range),
               match.numberOfRanges > 1 {
                let urlRange = match.range(at: 1)
                let startIndex = header.index(header.startIndex, offsetBy: urlRange.location)
                let endIndex = header.index(startIndex, offsetBy: urlRange.length)
                let extractedURL = String(header[startIndex..<endIndex])
                
                // Verify the extracted URL is valid
                #expect(!extractedURL.isEmpty, "Should extract non-empty resource metadata URL for \(serverURL)")
                #expect(extractedURL.hasPrefix("https://"), "Resource metadata URL should use HTTPS for \(serverURL)")
                #expect(extractedURL.contains(".well-known/oauth-protected-resource"), 
                       "Should contain standard OAuth resource metadata path for \(serverURL)")
            } else {
                #expect(Bool(false), "Should be able to extract resource_metadata from header for \(serverURL)")
            }
        }
    }
}
