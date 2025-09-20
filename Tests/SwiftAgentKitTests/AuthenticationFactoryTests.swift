//
//  AuthenticationFactoryTests.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/20/25.
//

import Testing
import Foundation
import EasyJSON
@testable import SwiftAgentKit

@Suite("AuthenticationFactory Tests")
struct AuthenticationFactoryTests {
    
    // MARK: - String-based factory tests
    
    @Test("Factory should create Bearer token provider from string")
    func testCreateBearerTokenProviderFromString() async throws {
        let config = JSON.object([
            "token": .string("test-bearer-token")
        ])
        
        let provider = try AuthenticationFactory.createAuthProvider(authType: "bearer", config: config)
        
        #expect(provider.scheme == .bearer)
        let headers = try await provider.authenticationHeaders()
        #expect(headers["Authorization"] == "Bearer test-bearer-token")
    }
    
    @Test("Factory should create API key provider from string")
    func testCreateAPIKeyProviderFromString() async throws {
        let config = JSON.object([
            "apiKey": .string("test-api-key"),
            "headerName": .string("X-Custom-Key"),
            "prefix": .string("ApiKey ")
        ])
        
        let provider = try AuthenticationFactory.createAuthProvider(authType: "apikey", config: config)
        
        #expect(provider.scheme == .apiKey)
        let headers = try await provider.authenticationHeaders()
        #expect(headers["X-Custom-Key"] == "ApiKey test-api-key")
    }
    
    @Test("Factory should create Basic auth provider from string")
    func testCreateBasicAuthProviderFromString() async throws {
        let config = JSON.object([
            "username": .string("testuser"),
            "password": .string("testpass")
        ])
        
        let provider = try AuthenticationFactory.createAuthProvider(authType: "basic", config: config)
        
        #expect(provider.scheme == .basic)
        let headers = try await provider.authenticationHeaders()
        #expect(headers["Authorization"]?.hasPrefix("Basic ") == true)
    }
    
    @Test("Factory should create OAuth provider from string")
    func testCreateOAuthProviderFromString() async throws {
        let config = JSON.object([
            "accessToken": .string("test-access-token"),
            "refreshToken": .string("test-refresh-token"),
            "tokenEndpoint": .string("https://auth.example.com/token"),
            "clientId": .string("test-client-id"),
            "clientSecret": .string("test-client-secret"),
            "scope": .string("read write"),
            "tokenType": .string("Bearer"),
            "expiresIn": .integer(3600)
        ])
        
        let provider = try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
        
        #expect(provider.scheme == .oauth)
        let headers = try await provider.authenticationHeaders()
        #expect(headers["Authorization"] == "Bearer test-access-token")
    }
    
    @Test("Factory should handle alternative auth type names")
    func testAlternativeAuthTypeNames() async throws {
        let tokenConfig = JSON.object(["token": .string("test-token")])
        let apiKeyConfig = JSON.object(["apiKey": .string("test-key")])
        
        // Test "token" instead of "bearer"
        let tokenProvider = try AuthenticationFactory.createAuthProvider(authType: "token", config: tokenConfig)
        #expect(tokenProvider.scheme == .bearer)
        
        // Test "api_key" instead of "apikey"
        let apiKeyProvider = try AuthenticationFactory.createAuthProvider(authType: "api_key", config: apiKeyConfig)
        #expect(apiKeyProvider.scheme == .apiKey)
    }
    
    @Test("Factory should throw for unsupported auth type")
    func testUnsupportedAuthType() async throws {
        let config = JSON.object([:])
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(authType: "unsupported", config: config)
        }
    }
    
    // MARK: - Enum-based factory tests
    
    @Test("Factory should create providers from enum schemes")
    func testCreateProviderFromEnumScheme() async throws {
        let config = JSON.object([
            "token": .string("enum-test-token")
        ])
        
        let provider = try AuthenticationFactory.createAuthProvider(scheme: .bearer, config: config)
        
        #expect(provider.scheme == .bearer)
        let headers = try await provider.authenticationHeaders()
        #expect(headers["Authorization"] == "Bearer enum-test-token")
    }
    
    @Test("Factory should throw for custom scheme")
    func testCustomSchemeThrows() async throws {
        let config = JSON.object([:])
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(scheme: .custom("custom-scheme"), config: config)
        }
    }
    
    // MARK: - Environment variable tests
    
    @Test("Factory should create Bearer token from environment")
    func testCreateBearerTokenFromEnvironment() async throws {
        // Set environment variables
        setenv("TESTSERVER_TOKEN", "env-bearer-token", 1)
        defer { unsetenv("TESTSERVER_TOKEN") }
        
        let provider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: "testserver")
        
        #expect(provider != nil)
        #expect(provider?.scheme == .bearer)
        
        let headers = try await provider!.authenticationHeaders()
        #expect(headers["Authorization"] == "Bearer env-bearer-token")
    }
    
    @Test("Factory should create API key from environment")
    func testCreateAPIKeyFromEnvironment() async throws {
        // Clear any existing Bearer token env vars first
        unsetenv("APISERVER_TOKEN")
        unsetenv("APISERVER_BEARER_TOKEN")
        
        // Set environment variables
        setenv("APISERVER_API_KEY", "env-api-key", 1)
        setenv("APISERVER_API_HEADER", "X-Env-Key", 1)
        setenv("APISERVER_API_PREFIX", "Key ", 1)
        defer {
            unsetenv("APISERVER_API_KEY")
            unsetenv("APISERVER_API_HEADER")
            unsetenv("APISERVER_API_PREFIX")
        }
        
        let provider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: "apiserver")
        
        #expect(provider != nil)
        #expect(provider?.scheme == .apiKey)
        
        let headers = try await provider!.authenticationHeaders()
        #expect(headers["X-Env-Key"] == "Key env-api-key")
    }
    
    @Test("Factory should create Basic auth from environment")
    func testCreateBasicAuthFromEnvironment() async throws {
        // Clear any existing token env vars first
        unsetenv("BASICSERVER_TOKEN")
        unsetenv("BASICSERVER_BEARER_TOKEN")
        unsetenv("BASICSERVER_API_KEY")
        
        // Set environment variables
        setenv("BASICSERVER_USERNAME", "env-user", 1)
        setenv("BASICSERVER_PASSWORD", "env-pass", 1)
        defer {
            unsetenv("BASICSERVER_USERNAME")
            unsetenv("BASICSERVER_PASSWORD")
        }
        
        let provider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: "basicserver")
        
        #expect(provider != nil)
        #expect(provider?.scheme == .basic)
        
        let headers = try await provider!.authenticationHeaders()
        #expect(headers["Authorization"]?.hasPrefix("Basic ") == true)
    }
    
    @Test("Factory should create OAuth from environment")
    func testCreateOAuthFromEnvironment() async throws {
        // Clear any existing token env vars first
        unsetenv("OAUTHSERVER_TOKEN")
        unsetenv("OAUTHSERVER_BEARER_TOKEN")
        unsetenv("OAUTHSERVER_API_KEY")
        unsetenv("OAUTHSERVER_USERNAME")
        unsetenv("OAUTHSERVER_PASSWORD")
        
        // Set environment variables
        setenv("OAUTHSERVER_OAUTH_ACCESS_TOKEN", "env-access-token", 1)
        setenv("OAUTHSERVER_OAUTH_REFRESH_TOKEN", "env-refresh-token", 1)
        setenv("OAUTHSERVER_OAUTH_TOKEN_ENDPOINT", "https://env.example.com/token", 1)
        setenv("OAUTHSERVER_OAUTH_CLIENT_ID", "env-client-id", 1)
        setenv("OAUTHSERVER_OAUTH_CLIENT_SECRET", "env-client-secret", 1)
        setenv("OAUTHSERVER_OAUTH_SCOPE", "env-scope", 1)
        setenv("OAUTHSERVER_OAUTH_TOKEN_TYPE", "Bearer", 1)
        defer {
            unsetenv("OAUTHSERVER_OAUTH_ACCESS_TOKEN")
            unsetenv("OAUTHSERVER_OAUTH_REFRESH_TOKEN")
            unsetenv("OAUTHSERVER_OAUTH_TOKEN_ENDPOINT")
            unsetenv("OAUTHSERVER_OAUTH_CLIENT_ID")
            unsetenv("OAUTHSERVER_OAUTH_CLIENT_SECRET")
            unsetenv("OAUTHSERVER_OAUTH_SCOPE")
            unsetenv("OAUTHSERVER_OAUTH_TOKEN_TYPE")
        }
        
        let provider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: "oauthserver")
        
        #expect(provider != nil)
        #expect(provider?.scheme == .oauth)
        
        let headers = try await provider!.authenticationHeaders()
        #expect(headers["Authorization"] == "Bearer env-access-token")
    }
    
    @Test("Factory should return nil when no environment variables found")
    func testNoEnvironmentVariables() async throws {
        let provider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: "nonexistent")
        #expect(provider == nil)
    }
    
    @Test("Factory should prioritize Bearer token over API key in environment")
    func testEnvironmentPriority() async throws {
        // Set both Bearer token and API key
        setenv("TESTSERVER_TOKEN", "priority-bearer-token", 1)
        setenv("TESTSERVER_API_KEY", "priority-api-key", 1)
        defer {
            unsetenv("TESTSERVER_TOKEN")
            unsetenv("TESTSERVER_API_KEY")
        }
        
        let provider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: "testserver")
        
        #expect(provider != nil)
        #expect(provider?.scheme == .bearer) // Should prioritize Bearer token
        
        let headers = try await provider!.authenticationHeaders()
        #expect(headers["Authorization"] == "Bearer priority-bearer-token")
    }
    
    // MARK: - Configuration validation tests
    
    @Test("Factory should throw for missing Bearer token")
    func testMissingBearerToken() async throws {
        let config = JSON.object([:]) // Missing token
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(authType: "bearer", config: config)
        }
    }
    
    @Test("Factory should throw for missing API key")
    func testMissingAPIKey() async throws {
        let config = JSON.object([:]) // Missing apiKey
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(authType: "apikey", config: config)
        }
    }
    
    @Test("Factory should throw for missing Basic auth credentials")
    func testMissingBasicAuthCredentials() async throws {
        let configMissingUsername = JSON.object([
            "password": .string("testpass")
        ])
        
        let configMissingPassword = JSON.object([
            "username": .string("testuser")
        ])
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(authType: "basic", config: configMissingUsername)
        }
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(authType: "basic", config: configMissingPassword)
        }
    }
    
    @Test("Factory should throw for missing OAuth required fields")
    func testMissingOAuthRequiredFields() async throws {
        let configMissingAccessToken = JSON.object([
            "tokenEndpoint": .string("https://example.com/token"),
            "clientId": .string("client-id")
        ])
        
        let configMissingTokenEndpoint = JSON.object([
            "accessToken": .string("access-token"),
            "clientId": .string("client-id")
        ])
        
        let configMissingClientId = JSON.object([
            "accessToken": .string("access-token"),
            "tokenEndpoint": .string("https://example.com/token")
        ])
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(authType: "oauth", config: configMissingAccessToken)
        }
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(authType: "oauth", config: configMissingTokenEndpoint)
        }
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(authType: "oauth", config: configMissingClientId)
        }
    }
    
    @Test("Factory should handle invalid OAuth token endpoint URL")
    func testInvalidOAuthTokenEndpoint() async throws {
        let config = JSON.object([
            "accessToken": .string("access-token"),
            "tokenEndpoint": .string("invalid-url"),
            "clientId": .string("client-id")
        ])
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
        }
    }
    
    @Test("Factory should handle non-object config")
    func testNonObjectConfig() async throws {
        let config = JSON.string("not-an-object")
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(authType: "bearer", config: config)
        }
    }
    
    @Test("API key factory should use defaults for optional fields")
    func testAPIKeyDefaults() async throws {
        let config = JSON.object([
            "apiKey": .string("test-key")
        ])
        
        let provider = try AuthenticationFactory.createAuthProvider(authType: "apikey", config: config)
        let headers = try await provider.authenticationHeaders()
        
        #expect(headers["X-API-Key"] == "test-key") // Should use default header name
    }
    
    @Test("OAuth factory should use defaults for optional fields")
    func testOAuthDefaults() async throws {
        let config = JSON.object([
            "accessToken": .string("test-token"),
            "tokenEndpoint": .string("https://example.com/token"),
            "clientId": .string("test-client")
        ])
        
        let provider = try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
        let headers = try await provider.authenticationHeaders()
        
        #expect(headers["Authorization"] == "Bearer test-token") // Should use default token type
    }
}
