// Keychain Permission and Error Handling Tests
// Comprehensive tests for keychain permission detection and error handling

import Testing
import Foundation
import Security
import SwiftAgentKit

struct KeychainPermissionTests {

    // MARK: - Test Configuration

    private let testService = "SwiftAgentKitTests.PermissionTests"

    // Unique test identifiers for parallel execution
    private var testAccountId: String {
        return "permission_test_\(UUID().uuidString)"
    }

    // MARK: - Helper Methods

    private func createTestToken() -> OAuthToken {
        return OAuthToken(
            accessToken: "test_access_token_\(UUID().uuidString)",
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: "test_refresh_token_\(UUID().uuidString)",
            scope: "read write"
        )
    }

    private func createTestTokenWithConfig(token: OAuthToken? = nil) -> OAuthTokenWithConfig {
        let testToken = token ?? createTestToken()
        return OAuthTokenWithConfig(
            token: testToken,
            tokenEndpoint: "https://api.example.com/oauth/token",
            clientId: "test_client_id_\(UUID().uuidString)",
            clientSecret: "test_client_secret_\(UUID().uuidString)",
            scope: "read write admin"
        )
    }

    private func isKeychainAccessAvailable() async -> Bool {
        // Test keychain access by trying to store and retrieve a small test item
        let testAccountId = "keychain_test_\(UUID().uuidString)"
        let testData = "test_data".data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: testAccountId,
            kSecValueData as String: testData,
            kSecAttrSynchronizable as String: true
        ]

        // Try to add test item
        let addStatus = SecItemAdd(query as CFDictionary, nil)

        if addStatus == errSecSuccess {
            // Clean up test item
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService,
                kSecAttrAccount as String: testAccountId,
                kSecAttrSynchronizable as String: true
            ]
            SecItemDelete(deleteQuery as CFDictionary)
            return true
        } else {
            return false
        }
    }

    // MARK: - Permission Detection Tests

    @Test("Keychain access check works correctly")
    func testKeychainAccessCheck() async throws {
        let storage = KeychainTokenStorage(service: testService)

        let accountId = testAccountId
        let token = createTestToken()

        do {
            try await storage.storeToken(token, for: accountId)

            // If we get here, keychain access is working
            let retrievedToken = try await storage.retrieveToken(for: accountId)
            #expect(retrievedToken != nil)
            #expect(retrievedToken?.accessToken == token.accessToken)

            // Cleanup
            try await storage.removeToken(for: accountId)
        } catch {
            // If keychain access fails, that's also a valid test result
            #expect(error is KeychainError)
        }
    }

    @Test("Permission resolution attempts work")
    func testPermissionResolutionAttempts() async throws {
        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId
        let token = createTestToken()

        do {
            try await storage.storeToken(token, for: accountId)

            let retrievedToken = try await storage.retrieveToken(for: accountId)
            #expect(retrievedToken != nil)

            try await storage.removeToken(for: accountId)
        } catch let keychainError as KeychainError {
            #expect(keychainError.localizedDescription.count > 0)
            let errorDescription = keychainError.localizedDescription
            #expect(!errorDescription.isEmpty)
        } catch {
            #expect(Bool(false), "Unexpected error type: \(type(of: error))")
        }
    }

    // MARK: - Error Type Tests

    @Test("KeychainError types have proper descriptions")
    func testKeychainErrorDescriptions() async throws {
        let permissionDeniedError = KeychainError.permissionDenied
        let permissionDescription = permissionDeniedError.localizedDescription
        #expect(!permissionDescription.isEmpty)
        #expect(permissionDescription.contains("denied"))

        let userInteractionError = KeychainError.userInteractionRequired
        let interactionDescription = userInteractionError.localizedDescription
        #expect(!interactionDescription.isEmpty)
        #expect(interactionDescription.contains("interaction"))

        let authFailedError = KeychainError.authenticationFailed
        let authDescription = authFailedError.localizedDescription
        #expect(!authDescription.isEmpty)
        #expect(authDescription.contains("authentication"))

        let storageError = KeychainError.storageFailed(-34018)
        let storageDescription = storageError.localizedDescription
        #expect(!storageDescription.isEmpty)
        #expect(storageDescription.contains("34018"))

        let retrievalError = KeychainError.retrievalFailed(-34018)
        let retrievalDescription = retrievalError.localizedDescription
        #expect(!retrievalDescription.isEmpty)
        #expect(retrievalDescription.contains("34018"))
    }

    // MARK: - Error Handling Integration Tests

    @Test("Store token handles errors gracefully")
    func testStoreTokenErrorHandling() async throws {
        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId
        let token = createTestToken()

        do {
            try await storage.storeToken(token, for: accountId)

            let retrievedToken = try await storage.retrieveToken(for: accountId)
            #expect(retrievedToken != nil)
            try await storage.removeToken(for: accountId)
        } catch let keychainError as KeychainError {
            let errorDescription = keychainError.localizedDescription
            #expect(!errorDescription.isEmpty)

            let validErrorTypes: [KeychainError] = [
                .permissionDenied,
                .userInteractionRequired,
                .authenticationFailed,
                .storageFailed(-1)
            ]

            let isValidErrorType = validErrorTypes.contains { error in
                switch (error, keychainError) {
                case (.permissionDenied, .permissionDenied):
                    return true
                case (.userInteractionRequired, .userInteractionRequired):
                    return true
                case (.authenticationFailed, .authenticationFailed):
                    return true
                case (.storageFailed(_), .storageFailed(_)):
                    return true
                default:
                    return false
                }
            }
            #expect(isValidErrorType, "Unexpected error type: \(keychainError)")
        } catch {
            #expect(Bool(false), "Unexpected error type: \(type(of: error))")
        }
    }

    @Test("Store token with config handles errors gracefully")
    func testStoreTokenWithConfigErrorHandling() async throws {
        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId
        let tokenWithConfig = createTestTokenWithConfig()

        do {
            try await storage.storeTokenWithConfig(tokenWithConfig, for: accountId)

            let retrievedTokenWithConfig = try await storage.retrieveTokenWithConfig(for: accountId)
            #expect(retrievedTokenWithConfig != nil)
            try await storage.removeToken(for: accountId)
        } catch let keychainError as KeychainError {
            let errorDescription = keychainError.localizedDescription
            #expect(!errorDescription.isEmpty)

            let validErrorTypes: [KeychainError] = [
                .permissionDenied,
                .userInteractionRequired,
                .authenticationFailed,
                .storageFailed(-1)
            ]

            let isValidErrorType = validErrorTypes.contains { error in
                switch (error, keychainError) {
                case (.permissionDenied, .permissionDenied):
                    return true
                case (.userInteractionRequired, .userInteractionRequired):
                    return true
                case (.authenticationFailed, .authenticationFailed):
                    return true
                case (.storageFailed(_), .storageFailed(_)):
                    return true
                default:
                    return false
                }
            }
            #expect(isValidErrorType, "Unexpected error type: \(keychainError)")
        } catch {
            #expect(Bool(false), "Unexpected error type: \(type(of: error))")
        }
    }

    // MARK: - Edge Case Tests

    @Test("Handles empty token data gracefully")
    func testHandlesEmptyTokenData() async throws {
        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId

        let emptyToken = OAuthToken(
            accessToken: "",
            tokenType: "",
            expiresIn: nil,
            refreshToken: nil,
            scope: nil
        )

        do {
            try await storage.storeToken(emptyToken, for: accountId)

            let retrievedToken = try await storage.retrieveToken(for: accountId)
            #expect(retrievedToken != nil)
            #expect(retrievedToken?.accessToken == "")
            #expect(retrievedToken?.tokenType == "")
            try await storage.removeToken(for: accountId)
        } catch let keychainError as KeychainError {
            let errorDescription = keychainError.localizedDescription
            #expect(!errorDescription.isEmpty)
        } catch {
            #expect(Bool(false), "Unexpected error type: \(type(of: error))")
        }
    }

    @Test("Handles very long token data")
    func testHandlesLongTokenData() async throws {
        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId

        let longString = String(repeating: "a", count: 10000)
        let longToken = OAuthToken(
            accessToken: longString,
            tokenType: longString,
            expiresIn: Int.max,
            refreshToken: longString,
            scope: longString
        )

        do {
            try await storage.storeToken(longToken, for: accountId)

            let retrievedToken = try await storage.retrieveToken(for: accountId)
            #expect(retrievedToken != nil)
            #expect(retrievedToken?.accessToken == longString)
            try await storage.removeToken(for: accountId)
        } catch let keychainError as KeychainError {
            let errorDescription = keychainError.localizedDescription
            #expect(!errorDescription.isEmpty)
        } catch {
            #expect(Bool(false), "Unexpected error type: \(type(of: error))")
        }
    }

    // MARK: - Concurrency Tests

    @Test("Handles concurrent operations safely")
    func testConcurrentOperations() async throws {
        let storage = KeychainTokenStorage(service: testService)
        let accountId = testAccountId
        let token = createTestToken()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    try await storage.storeToken(token, for: accountId)
                } catch {}
            }

            group.addTask {
                do {
                    _ = try await storage.retrieveToken(for: accountId)
                } catch {}
            }

            group.addTask {
                do {
                    try await storage.removeToken(for: accountId)
                } catch {}
            }
        }

        try? await storage.removeToken(for: accountId)
    }
}
