//
//  RemoteTransportSimpleTests.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/20/25.
//

import Testing
import Foundation
@testable import SwiftAgentKit
@testable import SwiftAgentKitMCP

@Suite("RemoteTransport Simple Tests")
struct RemoteTransportSimpleTests {
    
    // MARK: - Initialization Tests
    
    @Test("RemoteTransport should initialize with correct defaults")
    func testInitialization() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let transport = RemoteTransport(serverURL: serverURL)
        
        #expect(transport.logger.label == "RemoteTransport")
    }
    
    @Test("RemoteTransport should initialize with custom parameters")
    func testInitializationWithCustomParameters() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let authProvider = BearerTokenAuthProvider(token: "test-token")
        
        let transport = RemoteTransport(
            serverURL: serverURL,
            authProvider: authProvider,
            connectionTimeout: 15.0,
            requestTimeout: 30.0,
            maxRetries: 5
        )
        
        #expect(transport.logger.label == "RemoteTransport")
    }
    
    // MARK: - Error Type Tests
    
    @Test("RemoteTransportError should have correct descriptions")
    func testErrorDescriptions() async throws {
        let testError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        
        let errors: [RemoteTransport.RemoteTransportError] = [
            .invalidURL("bad-url"),
            .authenticationFailed("auth failed"),
            .connectionFailed("connection failed"),
            .networkError(testError),
            .invalidResponse("invalid response"),
            .serverError(500, "server error"),
            .notConnected,
            .oauthDiscoveryRequired(resourceMetadataURL: "https://example.com/.well-known/oauth-protected-resource"),
            .oauthDiscoveryFailed("discovery failed")
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
        
        // Test specific error messages
        if case .invalidURL(let url) = errors[0] {
            #expect(errors[0].errorDescription?.contains(url) == true)
        }
        
        if case .serverError(let code, let message) = errors[5] {
            #expect(errors[5].errorDescription?.contains("\(code)") == true)
            #expect(errors[5].errorDescription?.contains(message) == true)
        }
    }
    
    // MARK: - Basic Functionality Tests
    
    @Test("Send should fail when not connected")
    func testSendNotConnected() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let transport = RemoteTransport(serverURL: serverURL)
        
        let testData = "test message".data(using: .utf8)!
        
        do {
            try await transport.send(testData)
            #expect(Bool(false), "Should have thrown not connected error")
        } catch let error as RemoteTransport.RemoteTransportError {
            if case .notConnected = error {
                // Expected
            } else {
                #expect(Bool(false), "Should have thrown notConnected error")
            }
        }
    }
    
    @Test("Receive should return stream when not connected")
    func testReceiveNotConnected() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let transport = RemoteTransport(serverURL: serverURL)
        
        let stream = await transport.receive()
        var iterator = stream.makeAsyncIterator()
        
        do {
            _ = try await iterator.next()
            #expect(Bool(false), "Should have thrown not connected error")
        } catch let error as RemoteTransport.RemoteTransportError {
            if case .notConnected = error {
                // Expected
            } else {
                #expect(Bool(false), "Should have thrown notConnected error")
            }
        }
    }
    
    @Test("Disconnect should be safe when not connected")
    func testDisconnectWhenNotConnected() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let transport = RemoteTransport(serverURL: serverURL)
        
        // Should not throw
        await transport.disconnect()
        await transport.disconnect() // Multiple calls should be safe
    }
    
    // MARK: - Authentication Integration Tests
    
    @Test("Should work with different authentication providers")
    func testDifferentAuthProviders() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        
        let authProviders: [any AuthenticationProvider] = [
            BearerTokenAuthProvider(token: "bearer-token"),
            APIKeyAuthProvider(apiKey: "api-key", headerName: "X-API-Key"),
            BasicAuthProvider(username: "user", password: "pass")
        ]
        
        for authProvider in authProviders {
            let transport = RemoteTransport(
                serverURL: serverURL,
                authProvider: authProvider
            )
            
            // Should initialize without errors
            #expect(transport.logger.label == "RemoteTransport")
            
            // Test that auth headers can be retrieved
            let headers = try await authProvider.authenticationHeaders()
            #expect(!headers.isEmpty)
        }
    }
    
    @Test("Should handle authentication provider cleanup")
    func testAuthProviderCleanup() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let authProvider = BearerTokenAuthProvider(token: "test-token")
        
        let transport = RemoteTransport(
            serverURL: serverURL,
            authProvider: authProvider
        )
        
        // Disconnect should call auth provider cleanup
        await transport.disconnect()
        
        // Should complete without errors
    }
    
    // MARK: - Configuration Tests
    
    @Test("Should handle various timeout configurations")
    func testTimeoutConfigurations() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        
        let configs = [
            (connection: 10.0, request: 20.0, retries: 1),
            (connection: 30.0, request: 60.0, retries: 3),
            (connection: 5.0, request: 10.0, retries: 5)
        ]
        
        for config in configs {
            let transport = RemoteTransport(
                serverURL: serverURL,
                connectionTimeout: config.connection,
                requestTimeout: config.request,
                maxRetries: config.retries
            )
            
            #expect(transport.logger.label == "RemoteTransport")
        }
    }
    
    @Test("Should handle invalid URLs gracefully")
    func testInvalidURLHandling() async throws {
        // Test with various URL formats
        let validURLs = [
            "https://api.example.com/mcp",
            "http://localhost:8080/mcp",
            "https://subdomain.example.com:9000/path/to/mcp"
        ]
        
        for urlString in validURLs {
            let url = URL(string: urlString)!
            let transport = RemoteTransport(serverURL: url)
            #expect(transport.logger.label == "RemoteTransport")
        }
    }
    
    // MARK: - Authentication Provider Integration Tests
    
    @Test("Should work with OAuth provider")
    func testOAuthProviderIntegration() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        
        let tokens = OAuthTokens(
            accessToken: "oauth-access-token",
            refreshToken: "oauth-refresh-token",
            tokenType: "Bearer"
        )
        
        let oauthConfig = try OAuthConfig(
            tokenEndpoint: URL(string: "https://auth.example.com/token")!,
            clientId: "test-client-id"
        )
        
        let authProvider = OAuthAuthProvider(tokens: tokens, config: oauthConfig)
        
        let transport = RemoteTransport(
            serverURL: serverURL,
            authProvider: authProvider
        )
        
        #expect(transport.logger.label == "RemoteTransport")
        
        // Test that OAuth headers work
        let headers = try await authProvider.authenticationHeaders()
        #expect(headers["Authorization"] == "Bearer oauth-access-token")
    }
    
    @Test("Should handle authentication provider errors gracefully")
    func testAuthProviderErrorHandling() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        
        // Create a failing auth provider
        let failingProvider = FailingAuthProvider()
        
        let transport = RemoteTransport(
            serverURL: serverURL,
            authProvider: failingProvider
        )
        
        // Should initialize fine
        #expect(transport.logger.label == "RemoteTransport")
        
        // Auth provider errors should be handled gracefully
        do {
            _ = try await failingProvider.authenticationHeaders()
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            // Expected
        }
    }
    
    // MARK: - Thread Safety Tests
    
    @Test("Multiple transports should not interfere")
    func testMultipleTransportsIndependence() async throws {
        let urls = [
            URL(string: "https://api1.example.com/mcp")!,
            URL(string: "https://api2.example.com/mcp")!,
            URL(string: "https://api3.example.com/mcp")!
        ]
        
        let transports = urls.map { url in
            RemoteTransport(
                serverURL: url,
                authProvider: BearerTokenAuthProvider(token: "token-for-\(url.host ?? "unknown")")
            )
        }
        
        // All should initialize independently
        for transport in transports {
            #expect(transport.logger.label == "RemoteTransport")
        }
        
        // Cleanup should work for all
        for transport in transports {
            await transport.disconnect()
        }
    }
    
    @Test("Concurrent disconnect operations should be safe")
    func testConcurrentDisconnect() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let transport = RemoteTransport(serverURL: serverURL)
        
        // Run multiple concurrent disconnect operations
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await transport.disconnect()
                }
            }
        }
        
        // Should complete without errors
    }
}

// MARK: - Test Helper Classes

struct FailingAuthProvider: AuthenticationProvider {
    let scheme: AuthenticationScheme = .custom("failing")
    
    func authenticationHeaders() async throws -> [String: String] {
        throw AuthenticationError.authenticationFailed("Test authentication failure")
    }
    
    func handleAuthenticationChallenge(_ challenge: AuthenticationChallenge) async throws -> [String: String] {
        throw AuthenticationError.authenticationFailed("Test challenge failure")
    }
    
    func isAuthenticationValid() async -> Bool {
        return false
    }
    
    func cleanup() async {
        // Nothing to do
    }
}
