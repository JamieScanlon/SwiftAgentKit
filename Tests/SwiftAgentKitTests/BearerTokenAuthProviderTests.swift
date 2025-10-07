//
//  BearerTokenAuthProviderTests.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/20/25.
//

import Testing
import Foundation
@testable import SwiftAgentKit

@Suite("BearerTokenAuthProvider Tests")
struct BearerTokenAuthProviderTests {
    
    @Test("Bearer token provider should have correct scheme")
    func testScheme() async throws {
        let provider = BearerTokenAuthProvider(token: "test-token")
        let scheme = await provider.scheme
        #expect(scheme == .bearer)
        #expect(scheme.rawValue == "Bearer")
    }
    
    @Test("Authentication headers should contain bearer token")
    func testAuthenticationHeaders() async throws {
        let provider = BearerTokenAuthProvider(token: "abc123xyz")
        
        let headers = try await provider.authenticationHeaders()
        
        #expect(headers.count == 1)
        #expect(headers["Authorization"] == "Bearer abc123xyz")
    }
    
    @Test("Authentication headers should handle empty token")
    func testAuthenticationHeadersWithEmptyToken() async throws {
        let provider = BearerTokenAuthProvider(token: "")
        
        let headers = try await provider.authenticationHeaders()
        
        #expect(headers["Authorization"] == "Bearer ")
    }
    
    @Test("Authentication should be valid when no expiration is set")
    func testIsAuthenticationValidNoExpiration() async throws {
        let provider = BearerTokenAuthProvider(token: "test-token")
        
        let isValid = await provider.isAuthenticationValid()
        #expect(isValid == true)
    }
    
    @Test("Authentication should be valid when token is not expired")
    func testIsAuthenticationValidNotExpired() async throws {
        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        let provider = BearerTokenAuthProvider(
            token: "test-token",
            expiresAt: futureDate,
            refreshHandler: nil
        )
        
        let isValid = await provider.isAuthenticationValid()
        #expect(isValid == true)
    }
    
    @Test("Authentication should be invalid when token is expired")
    func testIsAuthenticationValidExpired() async throws {
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let provider = BearerTokenAuthProvider(
            token: "test-token",
            expiresAt: pastDate,
            refreshHandler: nil
        )
        
        let isValid = await provider.isAuthenticationValid()
        #expect(isValid == false)
    }
    
    @Test("Authentication should be invalid when token expires soon")
    func testIsAuthenticationValidExpiresSoon() async throws {
        let soonDate = Date().addingTimeInterval(60) // 1 minute from now (within 5-minute threshold)
        let provider = BearerTokenAuthProvider(
            token: "test-token",
            expiresAt: soonDate,
            refreshHandler: nil
        )
        
        let isValid = await provider.isAuthenticationValid()
        #expect(isValid == false)
    }
    
    @Test("Token refresh should be called when token is expired")
    func testTokenRefreshOnExpiredToken() async throws {
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let newToken = "refreshed-token"
        
        // Use an actor to safely track state
        actor RefreshTracker {
            var called = false
            func markCalled() { called = true }
        }
        let tracker = RefreshTracker()
        
        let provider = BearerTokenAuthProvider(
            token: "old-token",
            expiresAt: pastDate,
            refreshHandler: { @Sendable in
                await tracker.markCalled()
                return newToken
            }
        )
        
        let headers = try await provider.authenticationHeaders()
        
        let refreshCalled = await tracker.called
        #expect(refreshCalled == true)
        #expect(headers["Authorization"] == "Bearer \(newToken)")
    }
    
    @Test("Token refresh should handle refresh failure")
    func testTokenRefreshFailure() async throws {
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        
        let provider = BearerTokenAuthProvider(
            token: "old-token",
            expiresAt: pastDate,
            refreshHandler: {
                throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Refresh failed"])
            }
        )
        
        await #expect(throws: AuthenticationError.self) {
            try await provider.authenticationHeaders()
        }
    }
    
    @Test("Handle authentication challenge should throw when no refresh handler")
    func testHandleAuthenticationChallengeNoRefreshHandler() async throws {
        let provider = BearerTokenAuthProvider(token: "test-token")
        
        let challenge = AuthenticationChallenge(
            statusCode: 401,
            headers: [:],
            body: nil,
            serverInfo: "test-server"
        )
        
        await #expect(throws: AuthenticationError.self) {
            try await provider.handleAuthenticationChallenge(challenge)
        }
    }
    
    @Test("Handle authentication challenge should refresh token")
    func testHandleAuthenticationChallengeRefreshToken() async throws {
        let newToken = "challenge-refreshed-token"
        
        // Use an actor to safely track state
        actor RefreshTracker {
            var called = false
            func markCalled() { called = true }
        }
        let tracker = RefreshTracker()
        
        let provider = BearerTokenAuthProvider(
            token: "old-token",
            refreshHandler: { @Sendable in
                await tracker.markCalled()
                return newToken
            }
        )
        
        let challenge = AuthenticationChallenge(
            statusCode: 401,
            headers: [:],
            body: nil,
            serverInfo: "test-server"
        )
        
        let headers = try await provider.handleAuthenticationChallenge(challenge)
        
        let refreshCalled = await tracker.called
        #expect(refreshCalled == true)
        #expect(headers["Authorization"] == "Bearer \(newToken)")
    }
    
    @Test("Handle authentication challenge should throw for non-401 status")
    func testHandleAuthenticationChallengeNon401() async throws {
        let provider = BearerTokenAuthProvider(
            token: "test-token",
            refreshHandler: { return "new-token" }
        )
        
        let challenge = AuthenticationChallenge(
            statusCode: 403,
            headers: [:],
            body: nil,
            serverInfo: "test-server"
        )
        
        do {
            _ = try await provider.handleAuthenticationChallenge(challenge)
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as AuthenticationError {
            if case .authenticationFailed(let message) = error {
                #expect(message.contains("Unexpected status code: 403"))
            } else {
                #expect(Bool(false), "Should have thrown authenticationFailed error")
            }
        }
    }
    
    @Test("Cleanup should complete without errors")
    func testCleanup() async throws {
        let provider = BearerTokenAuthProvider(token: "test-token")
        
        // Should not throw
        await provider.cleanup()
    }
    
    @Test("Multiple concurrent calls should work correctly")
    func testConcurrentCalls() async throws {
        let provider = BearerTokenAuthProvider(token: "concurrent-test-token")
        
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
            #expect(firstResult["Authorization"] == "Bearer concurrent-test-token")
        }
    }
    
    @Test("Concurrent refresh calls should work correctly")
    func testConcurrentRefreshCalls() async throws {
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        
        // Use an actor to safely track state
        actor RefreshCounter {
            var count = 0
            func increment() -> Int {
                count += 1
                return count
            }
        }
        let counter = RefreshCounter()
        
        let provider = BearerTokenAuthProvider(
            token: "old-token",
            expiresAt: pastDate,
            refreshHandler: { @Sendable in
                let callNumber = await counter.increment()
                // Simulate some async work
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                return "refreshed-token-\(callNumber)"
            }
        )
        
        // Run multiple concurrent requests that should trigger refresh
        await withTaskGroup(of: [String: String].self) { group in
            for _ in 0..<5 {
                group.addTask {
                    return (try? await provider.authenticationHeaders()) ?? [:]
                }
            }
            
            var results: [[String: String]] = []
            for await result in group {
                results.append(result)
            }
            
            // All results should contain valid tokens
            #expect(results.count == 5)
            for result in results {
                #expect(result["Authorization"]?.hasPrefix("Bearer ") == true)
                let token = result["Authorization"]?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
                #expect(token.contains("token"))
            }
            
            // Refresh should have been called (due to expired token)
            let refreshCallCount = await counter.count
            #expect(refreshCallCount > 0)
        }
    }
}
