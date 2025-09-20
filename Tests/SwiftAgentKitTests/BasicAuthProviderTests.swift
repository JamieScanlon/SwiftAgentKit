//
//  BasicAuthProviderTests.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/20/25.
//

import Testing
import Foundation
@testable import SwiftAgentKit

@Suite("BasicAuthProvider Tests")
struct BasicAuthProviderTests {
    
    @Test("Basic auth provider should have correct scheme")
    func testScheme() async throws {
        let provider = BasicAuthProvider(username: "testuser", password: "testpass")
        #expect(provider.scheme == .basic)
        #expect(provider.scheme.rawValue == "Basic")
    }
    
    @Test("Authentication headers should contain properly encoded credentials")
    func testAuthenticationHeaders() async throws {
        let provider = BasicAuthProvider(username: "testuser", password: "testpass")
        
        let headers = try await provider.authenticationHeaders()
        
        // Should have Authorization header
        #expect(headers.count == 1)
        #expect(headers["Authorization"] != nil)
        
        // Should be properly base64 encoded
        let authHeader = headers["Authorization"]!
        #expect(authHeader.hasPrefix("Basic "))
        
        // Extract and verify the base64 encoded credentials
        let base64Part = String(authHeader.dropFirst(6)) // Remove "Basic "
        let decodedData = Data(base64Encoded: base64Part)
        #expect(decodedData != nil)
        
        let decodedString = String(data: decodedData!, encoding: .utf8)
        #expect(decodedString == "testuser:testpass")
    }
    
    @Test("Authentication headers should handle special characters")
    func testAuthenticationHeadersWithSpecialCharacters() async throws {
        let provider = BasicAuthProvider(username: "user@example.com", password: "p@ssw0rd!")
        
        let headers = try await provider.authenticationHeaders()
        let authHeader = headers["Authorization"]!
        let base64Part = String(authHeader.dropFirst(6))
        let decodedData = Data(base64Encoded: base64Part)!
        let decodedString = String(data: decodedData, encoding: .utf8)
        
        #expect(decodedString == "user@example.com:p@ssw0rd!")
    }
    
    @Test("Authentication headers should handle empty credentials")
    func testAuthenticationHeadersWithEmptyCredentials() async throws {
        let provider = BasicAuthProvider(username: "", password: "")
        
        let headers = try await provider.authenticationHeaders()
        let authHeader = headers["Authorization"]!
        let base64Part = String(authHeader.dropFirst(6))
        let decodedData = Data(base64Encoded: base64Part)!
        let decodedString = String(data: decodedData, encoding: .utf8)
        
        #expect(decodedString == ":")
    }
    
    @Test("Authentication headers should handle Unicode characters")
    func testAuthenticationHeadersWithUnicodeCharacters() async throws {
        let provider = BasicAuthProvider(username: "用户", password: "密码")
        
        let headers = try await provider.authenticationHeaders()
        let authHeader = headers["Authorization"]!
        let base64Part = String(authHeader.dropFirst(6))
        let decodedData = Data(base64Encoded: base64Part)!
        let decodedString = String(data: decodedData, encoding: .utf8)
        
        #expect(decodedString == "用户:密码")
    }
    
    @Test("Handle authentication challenge should return same credentials for 401")
    func testHandleAuthenticationChallenge401() async throws {
        let provider = BasicAuthProvider(username: "testuser", password: "testpass")
        
        let challenge = AuthenticationChallenge(
            statusCode: 401,
            headers: ["WWW-Authenticate": "Basic realm=\"Test\""],
            body: nil,
            serverInfo: "test-server"
        )
        
        let headers = try await provider.handleAuthenticationChallenge(challenge)
        
        // Should return the same credentials as authenticationHeaders()
        let expectedHeaders = try await provider.authenticationHeaders()
        #expect(headers == expectedHeaders)
    }
    
    @Test("Handle authentication challenge should throw for non-401 status codes")
    func testHandleAuthenticationChallengeNon401() async throws {
        let provider = BasicAuthProvider(username: "testuser", password: "testpass")
        
        let challenge = AuthenticationChallenge(
            statusCode: 403,
            headers: [:],
            body: nil,
            serverInfo: "test-server"
        )
        
        await #expect(throws: AuthenticationError.self) {
            try await provider.handleAuthenticationChallenge(challenge)
        }
    }
    
    @Test("Handle authentication challenge should throw specific error for unexpected status")
    func testHandleAuthenticationChallengeUnexpectedStatus() async throws {
        let provider = BasicAuthProvider(username: "testuser", password: "testpass")
        
        let challenge = AuthenticationChallenge(
            statusCode: 500,
            headers: [:],
            body: nil,
            serverInfo: "test-server"
        )
        
        do {
            _ = try await provider.handleAuthenticationChallenge(challenge)
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as AuthenticationError {
            if case .authenticationFailed(let message) = error {
                #expect(message.contains("Unexpected status code: 500"))
            } else {
                #expect(Bool(false), "Should have thrown authenticationFailed error")
            }
        }
    }
    
    @Test("Authentication should always be valid")
    func testIsAuthenticationValid() async throws {
        let provider = BasicAuthProvider(username: "testuser", password: "testpass")
        
        let isValid = await provider.isAuthenticationValid()
        #expect(isValid == true)
    }
    
    @Test("Cleanup should complete without errors")
    func testCleanup() async throws {
        let provider = BasicAuthProvider(username: "testuser", password: "testpass")
        
        // Should not throw
        await provider.cleanup()
    }
    
    @Test("Provider should be Sendable")
    func testSendable() async throws {
        let provider = BasicAuthProvider(username: "testuser", password: "testpass")
        
        // Test that we can pass it across actor boundaries
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let headers = try? await provider.authenticationHeaders()
                #expect(headers != nil)
            }
        }
    }
    
    @Test("Multiple concurrent calls should work correctly")
    func testConcurrentCalls() async throws {
        let provider = BasicAuthProvider(username: "testuser", password: "testpass")
        
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
        }
    }
}
