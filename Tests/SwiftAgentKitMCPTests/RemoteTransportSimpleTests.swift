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
        
        #expect(transport.logger[metadataKey: "component"] == .string("RemoteTransport"))
        #expect(transport.logger[metadataKey: "serverURL"] == .string(serverURL.absoluteString))
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
        
        #expect(transport.logger[metadataKey: "component"] == .string("RemoteTransport"))
        #expect(transport.logger[metadataKey: "serverURL"] == .string(serverURL.absoluteString))
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
            #expect(transport.logger[metadataKey: "component"] == .string("RemoteTransport"))
            #expect(transport.logger[metadataKey: "serverURL"] == .string(serverURL.absoluteString))
            
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
            
            #expect(transport.logger[metadataKey: "component"] == .string("RemoteTransport"))
            #expect(transport.logger[metadataKey: "serverURL"] == .string(serverURL.absoluteString))
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
            #expect(transport.logger[metadataKey: "component"] == .string("RemoteTransport"))
            #expect(transport.logger[metadataKey: "serverURL"] == .string(url.absoluteString))
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
        
        #expect(transport.logger[metadataKey: "component"] == .string("RemoteTransport"))
        #expect(transport.logger[metadataKey: "serverURL"] == .string(serverURL.absoluteString))
        
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
        #expect(transport.logger[metadataKey: "component"] == .string("RemoteTransport"))
        #expect(transport.logger[metadataKey: "serverURL"] == .string(serverURL.absoluteString))
        
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
        for (transport, url) in zip(transports, urls) {
            #expect(transport.logger[metadataKey: "component"] == .string("RemoteTransport"))
            #expect(transport.logger[metadataKey: "serverURL"] == .string(url.absoluteString))
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
    
    // MARK: - SSE Response Handling Tests
    
    @Test("Should extract JSON from SSE data field")
    func testSSEJSONExtraction() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let transport = RemoteTransport(serverURL: serverURL)
        
        // Test basic SSE format
        let sseMessage = """
        event: message
        data: {"jsonrpc": "2.0", "result": "test", "id": 1}
        
        """
        
        let extractedData = transport.extractJSONFromSSE(sseMessage)
        #expect(extractedData != nil)
        
        let jsonString = String(data: extractedData!, encoding: .utf8)!
        #expect(jsonString.contains("\"jsonrpc\": \"2.0\""))
        #expect(jsonString.contains("\"result\": \"test\""))
    }
    
    @Test("Should handle SSE without event field")
    func testSSEWithoutEvent() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let transport = RemoteTransport(serverURL: serverURL)
        
        // Test SSE with only data field
        let sseMessage = """
        data: {"jsonrpc": "2.0", "method": "test", "id": 2}
        
        """
        
        let extractedData = transport.extractJSONFromSSE(sseMessage)
        #expect(extractedData != nil)
        
        let jsonString = String(data: extractedData!, encoding: .utf8)!
        #expect(jsonString.contains("\"method\": \"test\""))
    }
    
    @Test("Should handle multiple data fields in SSE")
    func testSSEMultipleDataFields() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let transport = RemoteTransport(serverURL: serverURL)
        
        // Test SSE with multiple data fields
        let sseMessage = """
        data: {"jsonrpc": "2.0"
        data: , "error": {"code": -1, "message": "test error"}
        data: , "id": 3}
        
        """
        
        let extractedData = transport.extractJSONFromSSE(sseMessage)
        #expect(extractedData != nil)
        
        let jsonString = String(data: extractedData!, encoding: .utf8)!
        #expect(jsonString.contains("\"jsonrpc\": \"2.0\""))
        #expect(jsonString.contains("\"error\""))
    }
    
    @Test("Should handle SSE with no space after data colon")
    func testSSENoSpaceAfterColon() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let transport = RemoteTransport(serverURL: serverURL)
        
        // Test SSE without space after colon
        let sseMessage = """
        data:{"jsonrpc": "2.0", "result": "no-space", "id": 4}
        
        """
        
        let extractedData = transport.extractJSONFromSSE(sseMessage)
        #expect(extractedData != nil)
        
        let jsonString = String(data: extractedData!, encoding: .utf8)!
        #expect(jsonString.contains("\"result\": \"no-space\""))
    }
    
    @Test("Should handle empty data fields in SSE")
    func testSSEEmptyDataFields() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let transport = RemoteTransport(serverURL: serverURL)
        
        // Test SSE with empty data field (used as separator)
        let sseMessage = """
        data: {"jsonrpc": "2.0", "result": "test", "id": 5}
        data:
        data: {"jsonrpc": "2.0", "result": "another", "id": 6}
        
        """
        
        let extractedData = transport.extractJSONFromSSE(sseMessage)
        #expect(extractedData != nil)
        
        let jsonString = String(data: extractedData!, encoding: .utf8)!
        #expect(jsonString.contains("\"result\": \"test\""))
        #expect(jsonString.contains("\"result\": \"another\""))
    }
    
    @Test("Should handle fallback for plain JSON")
    func testSSEFallbackToPlainJSON() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let transport = RemoteTransport(serverURL: serverURL)
        
        // Test fallback for plain JSON without SSE format
        let plainJSON = """
        {"jsonrpc": "2.0", "result": "plain-json", "id": 7}
        """
        
        let extractedData = transport.extractJSONFromSSE(plainJSON)
        #expect(extractedData != nil)
        
        let jsonString = String(data: extractedData!, encoding: .utf8)!
        #expect(jsonString.contains("\"result\": \"plain-json\""))
    }
    
    @Test("Should return nil for invalid SSE")
    func testInvalidSSE() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let transport = RemoteTransport(serverURL: serverURL)
        
        // Test invalid SSE format
        let invalidSSE = """
        event: test
        some-other-field: value
        
        """
        
        let extractedData = transport.extractJSONFromSSE(invalidSSE)
        #expect(extractedData == nil)
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
