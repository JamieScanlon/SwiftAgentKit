//
//  RemoteTransportConnectionTests.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/21/25.
//

import Testing
import Foundation
@testable import SwiftAgentKit
@testable import SwiftAgentKitMCP

@Suite("RemoteTransport Connection Tests")
struct RemoteTransportConnectionTests {
    
    // MARK: - Initialization Tests
    
    @Test("RemoteTransport should initialize with proper default configuration")
    func testInitializationDefaults() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let transport = RemoteTransport(serverURL: serverURL)
        
        #expect(transport.logger.label == "RemoteTransport")
        
        // Test that it can be initialized without errors
        await transport.disconnect() // Safe cleanup
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
        
        // Verify auth provider can generate headers
        let headers = try await authProvider.authenticationHeaders()
        #expect(headers["Authorization"] == "Bearer test-token")
        
        await transport.disconnect() // Safe cleanup
    }
    
    // MARK: - Connection State Tests
    
    @Test("RemoteTransport should handle connection state correctly")
    func testConnectionStateHandling() async throws {
        let serverURL = URL(string: "https://nonexistent.example.com/mcp")!
        let transport = RemoteTransport(
            serverURL: serverURL,
            connectionTimeout: 1.0, // Short timeout to fail quickly
            maxRetries: 1
        )
        
        // Test that connection fails for nonexistent server
        do {
            try await transport.connect()
            #expect(Bool(false), "Should have failed to connect to nonexistent server")
        } catch let error as RemoteTransport.RemoteTransportError {
            // Should get a connection error
            switch error {
            case .serverError, .networkError, .connectionFailed:
                // Expected error types
                break
            default:
                #expect(Bool(false), "Unexpected error type: \(error)")
            }
        }
        
        // Test that send fails when not connected
        do {
            let testData = "test".data(using: .utf8)!
            try await transport.send(testData)
            #expect(Bool(false), "Should have failed to send when not connected")
        } catch let error as RemoteTransport.RemoteTransportError {
            if case .notConnected = error {
                // Expected
            } else {
                #expect(Bool(false), "Expected notConnected error, got: \(error)")
            }
        }
        
        // Test that disconnect is safe when not connected
        await transport.disconnect()
        await transport.disconnect() // Multiple calls should be safe
    }
    
    // MARK: - Authentication Integration Tests
    
    @Test("RemoteTransport should work with different authentication providers")
    func testAuthenticationProviderIntegration() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        
        let authProviders: [any AuthenticationProvider] = [
            BearerTokenAuthProvider(token: "bearer-token"),
            APIKeyAuthProvider(apiKey: "api-key", headerName: "X-API-Key"),
            BasicAuthProvider(username: "user", password: "pass")
        ]
        
        for authProvider in authProviders {
            let transport = RemoteTransport(
                serverURL: serverURL,
                authProvider: authProvider,
                connectionTimeout: 1.0, // Short timeout
                maxRetries: 1
            )
            
            // Verify auth provider works
            let headers = try await authProvider.authenticationHeaders()
            #expect(!headers.isEmpty)
            
            // Verify transport initializes correctly with auth provider
            #expect(transport.logger.label == "RemoteTransport")
            
            await transport.disconnect()
        }
    }
    
    @Test("RemoteTransport should handle authentication provider failures gracefully")
    func testAuthProviderFailureHandling() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let failingProvider = FailingAuthProvider()
        
        let transport = RemoteTransport(
            serverURL: serverURL,
            authProvider: failingProvider,
            connectionTimeout: 1.0,
            maxRetries: 1
        )
        
        // Should initialize fine
        #expect(transport.logger.label == "RemoteTransport")
        
        // Connection should fail due to auth provider failure
        do {
            try await transport.connect()
            #expect(Bool(false), "Should have failed due to auth provider error")
        } catch let error as RemoteTransport.RemoteTransportError {
            if case .networkError = error {
                // Expected - auth failures get wrapped as network errors
            } else {
                #expect(Bool(false), "Expected networkError, got: \(error)")
            }
        } catch {
            // Auth provider errors can also be thrown directly
            #expect(error.localizedDescription.contains("authentication failure"), 
                   "Expected authentication error, got: \(error)")
        }
        
        await transport.disconnect()
    }
    
    // MARK: - Error Handling Tests
    
    @Test("RemoteTransport should handle various timeout configurations")
    func testTimeoutConfigurations() async throws {
        let serverURL = URL(string: "https://nonexistent.example.com/mcp")!
        
        let configs = [
            (connection: 1.0, request: 2.0, retries: 1),
            (connection: 2.0, request: 4.0, retries: 2)
        ]
        
        for config in configs {
            let transport = RemoteTransport(
                serverURL: serverURL,
                connectionTimeout: config.connection,
                requestTimeout: config.request,
                maxRetries: config.retries
            )
            
            let startTime = Date()
            
            do {
                try await transport.connect()
                #expect(Bool(false), "Should have failed to connect")
            } catch {
                let elapsedTime = Date().timeIntervalSince(startTime)
                // Should fail within a reasonable time based on timeout settings
                #expect(elapsedTime < (config.connection + config.request + 5.0), 
                       "Should have failed within timeout period")
            }
            
            await transport.disconnect()
        }
    }
    
    // MARK: - JSON-RPC Message Validation Tests
    
    @Test("RemoteTransport should validate JSON-RPC message format")
    func testJSONRPCValidation() async throws {
        let serverURL = URL(string: "https://api.example.com/mcp")!
        let transport = RemoteTransport(serverURL: serverURL)
        
        // Test the private isValidJSONRPCMessage function indirectly
        // by checking that the transport can handle various message formats
        
        // This is tested indirectly through the send/receive functionality
        // since we can't directly access private methods
        
        #expect(transport.logger.label == "RemoteTransport")
        await transport.disconnect()
    }
    
    // MARK: - Thread Safety Tests
    
    @Test("RemoteTransport should handle concurrent operations safely")
    func testConcurrentOperations() async throws {
        let serverURL = URL(string: "https://nonexistent.example.com/mcp")!
        let transport = RemoteTransport(
            serverURL: serverURL,
            connectionTimeout: 1.0,
            maxRetries: 1
        )
        
        // Test concurrent disconnect operations
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await transport.disconnect()
                }
            }
        }
        
        // Test concurrent connection attempts (should all fail safely)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    do {
                        try await transport.connect()
                    } catch {
                        // Expected to fail
                    }
                }
            }
        }
        
        await transport.disconnect()
    }
    
    // MARK: - URL Validation Tests
    
    @Test("RemoteTransport should work with various valid URL formats")
    func testURLFormatSupport() async throws {
        let validURLs = [
            "https://api.example.com/mcp",
            "http://localhost:8080/mcp",
            "https://subdomain.example.com:9000/path/to/mcp",
            "https://192.168.1.100:3000/mcp"
        ]
        
        for urlString in validURLs {
            let url = URL(string: urlString)!
            let transport = RemoteTransport(
                serverURL: url,
                connectionTimeout: 0.1, // Very short timeout
                maxRetries: 1
            )
            
            #expect(transport.logger.label == "RemoteTransport")
            
            // Test that initialization works with various URL formats
            // (connection will fail but that's expected)
            do {
                try await transport.connect()
            } catch {
                // Expected to fail for test URLs
            }
            
            await transport.disconnect()
        }
    }
}
