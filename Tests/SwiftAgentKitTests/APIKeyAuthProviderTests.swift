//
//  APIKeyAuthProviderTests.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/20/25.
//

import Testing
import Foundation
@testable import SwiftAgentKit

@Suite("APIKeyAuthProvider Tests")
struct APIKeyAuthProviderTests {
    
    @Test("API key provider should have correct scheme")
    func testScheme() async throws {
        let provider = APIKeyAuthProvider(apiKey: "test-key")
        #expect(provider.scheme == .apiKey)
        #expect(provider.scheme.rawValue == "ApiKey")
    }
    
    @Test("Authentication headers should contain API key with default header name")
    func testAuthenticationHeadersDefault() async throws {
        let provider = APIKeyAuthProvider(apiKey: "test-api-key-123")
        
        let headers = try await provider.authenticationHeaders()
        
        #expect(headers.count == 1)
        #expect(headers["X-API-Key"] == "test-api-key-123")
    }
    
    @Test("Authentication headers should use custom header name")
    func testAuthenticationHeadersCustomHeader() async throws {
        let provider = APIKeyAuthProvider(
            apiKey: "custom-key-456",
            headerName: "Authorization",
            prefix: nil
        )
        
        let headers = try await provider.authenticationHeaders()
        
        #expect(headers.count == 1)
        #expect(headers["Authorization"] == "custom-key-456")
    }
    
    @Test("Authentication headers should include prefix when specified")
    func testAuthenticationHeadersWithPrefix() async throws {
        let provider = APIKeyAuthProvider(
            apiKey: "prefixed-key",
            headerName: "X-Custom-Auth",
            prefix: "Bearer "
        )
        
        let headers = try await provider.authenticationHeaders()
        
        #expect(headers.count == 1)
        #expect(headers["X-Custom-Auth"] == "Bearer prefixed-key")
    }
    
    @Test("Authentication headers should handle empty API key")
    func testAuthenticationHeadersEmptyKey() async throws {
        let provider = APIKeyAuthProvider(apiKey: "")
        
        let headers = try await provider.authenticationHeaders()
        
        #expect(headers["X-API-Key"] == "")
    }
    
    @Test("Authentication headers should handle special characters in API key")
    func testAuthenticationHeadersSpecialCharacters() async throws {
        let specialKey = "key-with-!@#$%^&*()_+{}|:<>?[]\\;'\",./"
        let provider = APIKeyAuthProvider(apiKey: specialKey)
        
        let headers = try await provider.authenticationHeaders()
        
        #expect(headers["X-API-Key"] == specialKey)
    }
    
    @Test("Authentication headers should handle Unicode in API key")
    func testAuthenticationHeadersUnicode() async throws {
        let unicodeKey = "密钥-🔑-ключ"
        let provider = APIKeyAuthProvider(apiKey: unicodeKey)
        
        let headers = try await provider.authenticationHeaders()
        
        #expect(headers["X-API-Key"] == unicodeKey)
    }
    
    @Test("Authentication headers should handle multiple custom configurations")
    func testAuthenticationHeadersMultipleConfigs() async throws {
        let configs = [
            (key: "key1", header: "X-Auth-1", prefix: "Key1 "),
            (key: "key2", header: "X-Auth-2", prefix: "Key2 "),
            (key: "key3", header: "X-Auth-3", prefix: nil as String?)
        ]
        
        for config in configs {
            let provider = APIKeyAuthProvider(
                apiKey: config.key,
                headerName: config.header,
                prefix: config.prefix
            )
            
            let headers = try await provider.authenticationHeaders()
            
            let expectedValue = config.prefix != nil ? "\(config.prefix!)\(config.key)" : config.key
            #expect(headers[config.header] == expectedValue)
        }
    }
    
    @Test("Handle authentication challenge should throw for any status code")
    func testHandleAuthenticationChallengeAlwaysThrows() async throws {
        let provider = APIKeyAuthProvider(apiKey: "test-key")
        
        let statusCodes = [401, 403, 404, 500, 200]
        
        for statusCode in statusCodes {
            let challenge = AuthenticationChallenge(
                statusCode: statusCode,
                headers: [:],
                body: nil,
                serverInfo: "test-server"
            )
            
            await #expect(throws: AuthenticationError.self) {
                try await provider.handleAuthenticationChallenge(challenge)
            }
        }
    }
    
    @Test("Handle authentication challenge should throw invalid credentials error")
    func testHandleAuthenticationChallengeErrorType() async throws {
        let provider = APIKeyAuthProvider(apiKey: "test-key")
        
        let challenge = AuthenticationChallenge(
            statusCode: 401,
            headers: [:],
            body: nil,
            serverInfo: "test-server"
        )
        
        do {
            _ = try await provider.handleAuthenticationChallenge(challenge)
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as AuthenticationError {
            if case .invalidCredentials = error {
                // Expected error type
            } else {
                #expect(Bool(false), "Should have thrown invalidCredentials error")
            }
        }
    }
    
    @Test("Authentication should always be valid")
    func testIsAuthenticationValid() async throws {
        let providers = [
            APIKeyAuthProvider(apiKey: "key1"),
            APIKeyAuthProvider(apiKey: "", headerName: "Custom-Header"),
            APIKeyAuthProvider(apiKey: "key2", headerName: "X-Auth", prefix: "Bearer "),
            APIKeyAuthProvider(apiKey: "🔑", headerName: "Unicode-Header", prefix: nil)
        ]
        
        for provider in providers {
            let isValid = await provider.isAuthenticationValid()
            #expect(isValid == true)
        }
    }
    
    @Test("Cleanup should complete without errors")
    func testCleanup() async throws {
        let provider = APIKeyAuthProvider(apiKey: "test-key")
        
        // Should not throw
        await provider.cleanup()
    }
    
    @Test("Provider should be Sendable")
    func testSendable() async throws {
        let provider = APIKeyAuthProvider(apiKey: "sendable-test-key")
        
        // Test that we can pass it across task boundaries
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    let headers = try? await provider.authenticationHeaders()
                    #expect(headers?["X-API-Key"] == "sendable-test-key")
                }
            }
        }
    }
    
    @Test("Multiple concurrent calls should work correctly")
    func testConcurrentCalls() async throws {
        let provider = APIKeyAuthProvider(
            apiKey: "concurrent-key",
            headerName: "X-Concurrent-Auth",
            prefix: "Concurrent "
        )
        
        // Run multiple concurrent authentication header requests
        await withTaskGroup(of: [String: String].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    return (try? await provider.authenticationHeaders()) ?? [:]
                }
            }
            
            var results: [[String: String]] = []
            for await result in group {
                results.append(result)
            }
            
            // All results should be identical
            #expect(results.count == 10)
            let firstResult = results[0]
            for result in results {
                #expect(result == firstResult)
            }
            #expect(firstResult["X-Concurrent-Auth"] == "Concurrent concurrent-key")
        }
    }
    
    @Test("Provider should handle very long API keys")
    func testVeryLongAPIKey() async throws {
        let longKey = String(repeating: "a", count: 10000)
        let provider = APIKeyAuthProvider(apiKey: longKey)
        
        let headers = try await provider.authenticationHeaders()
        
        #expect(headers["X-API-Key"] == longKey)
        #expect(headers["X-API-Key"]?.count == 10000)
    }
    
    @Test("Provider should handle whitespace in API keys")
    func testWhitespaceInAPIKey() async throws {
        let keyWithWhitespace = "  key with spaces  "
        let provider = APIKeyAuthProvider(apiKey: keyWithWhitespace)
        
        let headers = try await provider.authenticationHeaders()
        
        // Should preserve whitespace exactly as provided
        #expect(headers["X-API-Key"] == keyWithWhitespace)
    }
    
    @Test("Provider should handle newlines and tabs in API keys")
    func testControlCharactersInAPIKey() async throws {
        let keyWithControlChars = "key\nwith\ttabs\rand\nnewlines"
        let provider = APIKeyAuthProvider(apiKey: keyWithControlChars)
        
        let headers = try await provider.authenticationHeaders()
        
        #expect(headers["X-API-Key"] == keyWithControlChars)
    }
    
    @Test("Multiple providers should not interfere with each other")
    func testMultipleProvidersIndependence() async throws {
        let provider1 = APIKeyAuthProvider(apiKey: "key1", headerName: "X-Auth-1")
        let provider2 = APIKeyAuthProvider(apiKey: "key2", headerName: "X-Auth-2", prefix: "Bearer ")
        let provider3 = APIKeyAuthProvider(apiKey: "key3")
        
        let headers1 = try await provider1.authenticationHeaders()
        let headers2 = try await provider2.authenticationHeaders()
        let headers3 = try await provider3.authenticationHeaders()
        
        #expect(headers1["X-Auth-1"] == "key1")
        #expect(headers2["X-Auth-2"] == "Bearer key2")
        #expect(headers3["X-API-Key"] == "key3")
        
        // Each should only have their own header
        #expect(headers1.count == 1)
        #expect(headers2.count == 1)
        #expect(headers3.count == 1)
    }
}
