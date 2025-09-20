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
        setenv("TESTSERVER_BEARER_TOKEN", "priority-bearer-token", 1)
        setenv("TESTSERVER_API_KEY", "priority-api-key", 1)
        defer {
            unsetenv("TESTSERVER_BEARER_TOKEN")
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
    
    // MARK: - PKCE OAuth Tests
    
    @Test("Factory should detect PKCE OAuth configuration")
    func testPKCEOAuthDetection() async throws {
        let pkceConfig = JSON.object([
            "issuerURL": .string("https://auth.example.com"),
            "clientId": .string("test-client-id"),
            "redirectURI": .string("https://app.example.com/callback"),
            "usePKCE": .boolean(true)
        ])
        
        let provider = try AuthenticationFactory.createAuthProvider(authType: "oauth", config: pkceConfig)
        
        #expect(provider.scheme == .oauth)
        // Verify it's actually a PKCEOAuthAuthProvider by checking the type
        #expect(provider is PKCEOAuthAuthProvider)
    }
    
    @Test("Factory should create PKCE OAuth provider with minimal config")
    func testCreatePKCEOAuthProviderMinimal() async throws {
        let config = JSON.object([
            "issuerURL": .string("https://auth.example.com"),
            "clientId": .string("test-client-id"),
            "redirectURI": .string("https://app.example.com/callback"),
            "usePKCE": .boolean(true)
        ])
        
        let provider = try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
        
        #expect(provider.scheme == .oauth)
        #expect(provider is PKCEOAuthAuthProvider)
    }
    
    @Test("Factory should create PKCE OAuth provider with full config")
    func testCreatePKCEOAuthProviderFull() async throws {
        let config = JSON.object([
            "issuerURL": .string("https://auth.example.com"),
            "clientId": .string("test-client-id"),
            "clientSecret": .string("test-client-secret"),
            "scope": .string("openid profile"),
            "redirectURI": .string("https://app.example.com/callback"),
            "authorizationEndpoint": .string("https://custom.example.com/oauth/authorize"),
            "tokenEndpoint": .string("https://custom.example.com/oauth/token"),
            "useOpenIDConnectDiscovery": .boolean(false),
            "usePKCE": .boolean(true)
        ])
        
        let provider = try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
        
        #expect(provider.scheme == .oauth)
        #expect(provider is PKCEOAuthAuthProvider)
    }
    
    @Test("Factory should throw for PKCE OAuth missing issuerURL")
    func testPKCEOAuthMissingIssuerURL() async throws {
        let config = JSON.object([
            "clientId": .string("test-client-id"),
            "redirectURI": .string("https://app.example.com/callback"),
            "usePKCE": .boolean(true)
        ])
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
        }
    }
    
    @Test("Factory should throw for PKCE OAuth missing clientId")
    func testPKCEOAuthMissingClientId() async throws {
        let config = JSON.object([
            "issuerURL": .string("https://auth.example.com"),
            "redirectURI": .string("https://app.example.com/callback"),
            "usePKCE": .boolean(true)
        ])
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
        }
    }
    
    @Test("Factory should throw for PKCE OAuth missing redirectURI")
    func testPKCEOAuthMissingRedirectURI() async throws {
        let config = JSON.object([
            "issuerURL": .string("https://auth.example.com"),
            "clientId": .string("test-client-id"),
            "usePKCE": .boolean(true)
        ])
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
        }
    }
    
    @Test("Factory should throw for PKCE OAuth invalid issuerURL")
    func testPKCEOAuthInvalidIssuerURL() async throws {
        let config = JSON.object([
            "issuerURL": .string("invalid-url"),
            "clientId": .string("test-client-id"),
            "redirectURI": .string("https://app.example.com/callback"),
            "usePKCE": .boolean(true)
        ])
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
        }
    }
    
    @Test("Factory should throw for PKCE OAuth invalid redirectURI")
    func testPKCEOAuthInvalidRedirectURI() async throws {
        let config = JSON.object([
            "issuerURL": .string("https://auth.example.com"),
            "clientId": .string("test-client-id"),
            "redirectURI": .string("invalid-uri"),
            "usePKCE": .boolean(true)
        ])
        
        #expect(throws: AuthenticationError.self) {
            try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
        }
    }
    
    @Test("Factory should create PKCE OAuth from environment")
    func testCreatePKCEOAuthFromEnvironment() async throws {
        // Clear any existing OAuth env vars first
        unsetenv("PKCESERVER_OAUTH_ACCESS_TOKEN")
        unsetenv("PKCESERVER_OAUTH_TOKEN_ENDPOINT")
        
        // Set PKCE OAuth environment variables
        setenv("PKCESERVER_PKCE_OAUTH_ISSUER_URL", "https://auth.example.com", 1)
        setenv("PKCESERVER_PKCE_OAUTH_CLIENT_ID", "env-client-id", 1)
        setenv("PKCESERVER_PKCE_OAUTH_REDIRECT_URI", "https://app.example.com/callback", 1)
        setenv("PKCESERVER_PKCE_OAUTH_CLIENT_SECRET", "env-client-secret", 1)
        setenv("PKCESERVER_PKCE_OAUTH_SCOPE", "openid profile", 1)
        setenv("PKCESERVER_PKCE_OAUTH_AUTHORIZATION_ENDPOINT", "https://custom.example.com/oauth/authorize", 1)
        setenv("PKCESERVER_PKCE_OAUTH_TOKEN_ENDPOINT", "https://custom.example.com/oauth/token", 1)
        setenv("PKCESERVER_PKCE_OAUTH_USE_OIDC_DISCOVERY", "false", 1)
        defer {
            unsetenv("PKCESERVER_PKCE_OAUTH_ISSUER_URL")
            unsetenv("PKCESERVER_PKCE_OAUTH_CLIENT_ID")
            unsetenv("PKCESERVER_PKCE_OAUTH_REDIRECT_URI")
            unsetenv("PKCESERVER_PKCE_OAUTH_CLIENT_SECRET")
            unsetenv("PKCESERVER_PKCE_OAUTH_SCOPE")
            unsetenv("PKCESERVER_PKCE_OAUTH_AUTHORIZATION_ENDPOINT")
            unsetenv("PKCESERVER_PKCE_OAUTH_TOKEN_ENDPOINT")
            unsetenv("PKCESERVER_PKCE_OAUTH_USE_OIDC_DISCOVERY")
        }
        
        let provider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: "pkceserver")
        
        #expect(provider != nil)
        #expect(provider?.scheme == .oauth)
        #expect(provider! is PKCEOAuthAuthProvider)
    }
    
    @Test("Factory should create PKCE OAuth from environment with minimal config")
    func testCreatePKCEOAuthFromEnvironmentMinimal() async throws {
        // Clear any existing OAuth env vars first
        unsetenv("MINPKCESERVER_OAUTH_ACCESS_TOKEN")
        unsetenv("MINPKCESERVER_OAUTH_TOKEN_ENDPOINT")
        
        // Set minimal PKCE OAuth environment variables
        setenv("MINPKCESERVER_PKCE_OAUTH_ISSUER_URL", "https://auth.example.com", 1)
        setenv("MINPKCESERVER_PKCE_OAUTH_CLIENT_ID", "min-client-id", 1)
        setenv("MINPKCESERVER_PKCE_OAUTH_REDIRECT_URI", "https://app.example.com/callback", 1)
        defer {
            unsetenv("MINPKCESERVER_PKCE_OAUTH_ISSUER_URL")
            unsetenv("MINPKCESERVER_PKCE_OAUTH_CLIENT_ID")
            unsetenv("MINPKCESERVER_PKCE_OAUTH_REDIRECT_URI")
        }
        
        let provider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: "minpkceserver")
        
        #expect(provider != nil)
        #expect(provider?.scheme == .oauth)
        #expect(provider! is PKCEOAuthAuthProvider)
    }
    
    @Test("Factory should prioritize PKCE OAuth over legacy OAuth in environment")
    func testPKCEOAuthEnvironmentPriority() async throws {
        // Clear any existing env vars first
        unsetenv("PRIOPKCESERVER_TOKEN")
        unsetenv("PRIOPKCESERVER_BEARER_TOKEN")
        unsetenv("PRIOPKCESERVER_API_KEY")
        unsetenv("PRIOPKCESERVER_USERNAME")
        unsetenv("PRIOPKCESERVER_PASSWORD")
        
        // Set both legacy OAuth and PKCE OAuth environment variables
        setenv("PRIOPKCESERVER_OAUTH_ACCESS_TOKEN", "legacy-access-token", 1)
        setenv("PRIOPKCESERVER_OAUTH_TOKEN_ENDPOINT", "https://legacy.example.com/token", 1)
        setenv("PRIOPKCESERVER_OAUTH_CLIENT_ID", "legacy-client-id", 1)
        
        setenv("PRIOPKCESERVER_PKCE_OAUTH_ISSUER_URL", "https://auth.example.com", 1)
        setenv("PRIOPKCESERVER_PKCE_OAUTH_CLIENT_ID", "pkce-client-id", 1)
        setenv("PRIOPKCESERVER_PKCE_OAUTH_REDIRECT_URI", "https://app.example.com/callback", 1)
        defer {
            unsetenv("PRIOPKCESERVER_OAUTH_ACCESS_TOKEN")
            unsetenv("PRIOPKCESERVER_OAUTH_TOKEN_ENDPOINT")
            unsetenv("PRIOPKCESERVER_OAUTH_CLIENT_ID")
            unsetenv("PRIOPKCESERVER_PKCE_OAUTH_ISSUER_URL")
            unsetenv("PRIOPKCESERVER_PKCE_OAUTH_CLIENT_ID")
            unsetenv("PRIOPKCESERVER_PKCE_OAUTH_REDIRECT_URI")
        }
        
        let provider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: "priopkceserver")
        
        #expect(provider != nil)
        #expect(provider?.scheme == .oauth)
        // Should prioritize PKCE OAuth over legacy OAuth
        #expect(provider! is PKCEOAuthAuthProvider)
    }
    
    @Test("Factory should handle PKCE OAuth environment with invalid URLs")
    func testPKCEOAuthEnvironmentInvalidURLs() async throws {
        // Set PKCE OAuth environment variables with URLs that have no scheme/host
        setenv("INVALIDPKCESERVER_PKCE_OAUTH_ISSUER_URL", "not-a-url", 1)
        setenv("INVALIDPKCESERVER_PKCE_OAUTH_CLIENT_ID", "test-client-id", 1)
        setenv("INVALIDPKCESERVER_PKCE_OAUTH_REDIRECT_URI", "also-not-a-url", 1)
        defer {
            unsetenv("INVALIDPKCESERVER_PKCE_OAUTH_ISSUER_URL")
            unsetenv("INVALIDPKCESERVER_PKCE_OAUTH_CLIENT_ID")
            unsetenv("INVALIDPKCESERVER_PKCE_OAUTH_REDIRECT_URI")
        }
        
        let provider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: "invalidpkceserver")
        
        // Should return nil when URLs are invalid (no scheme/host)
        #expect(provider == nil)
    }
    
    @Test("Factory should create OAuth Discovery provider")
    func testCreateOAuthDiscoveryProvider() async throws {
        let config = JSON.object([
            "resourceServerURL": .string("https://mcp.example.com"),
            "clientId": .string("test-client-id"),
            "clientSecret": .string("test-client-secret"),
            "scope": .string("openid profile"),
            "redirectURI": .string("https://client.example.com/callback"),
            "resourceType": .string("mcp"),
            "useOAuthDiscovery": .boolean(true),
            "preConfiguredAuthServerURL": .string("https://auth.example.com")
        ])
        
        let provider = try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
        
        #expect(provider.scheme == .oauth)
        // Note: We can't easily test the async methods without mocking the URLSession
        // The provider should be created successfully
    }
    
    @Test("Factory should create OAuth Discovery provider with minimal config")
    func testCreateOAuthDiscoveryProviderWithMinimalConfig() async throws {
        let config = JSON.object([
            "resourceServerURL": .string("https://mcp.example.com"),
            "clientId": .string("test-client-id"),
            "redirectURI": .string("https://client.example.com/callback"),
            "useOAuthDiscovery": .boolean(true)
        ])
        
        let provider = try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
        
        #expect(provider.scheme == .oauth)
    }
    
    @Test("Factory should throw error for OAuth Discovery with missing resourceServerURL")
    func testCreateOAuthDiscoveryProviderMissingResourceServerURL() async throws {
        let config = JSON.object([
            "resourceServerURL": .string(""), // Empty string to trigger validation error
            "clientId": .string("test-client-id"),
            "redirectURI": .string("https://client.example.com/callback"),
            "useOAuthDiscovery": .boolean(true)
        ])
        
        do {
            _ = try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
            #expect(Bool(false), "Expected creation to fail")
        } catch let error as AuthenticationError {
            if case .authenticationFailed(let message) = error {
                #expect(message.contains("Invalid resource server URL:"))
            } else {
                #expect(Bool(false), "Unexpected error case: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
    
    @Test("Factory should throw error for OAuth Discovery with invalid resourceServerURL")
    func testCreateOAuthDiscoveryProviderInvalidResourceServerURL() async throws {
        let config = JSON.object([
            "resourceServerURL": .string("invalid-url"),
            "clientId": .string("test-client-id"),
            "redirectURI": .string("https://client.example.com/callback"),
            "useOAuthDiscovery": .boolean(true)
        ])
        
        do {
            _ = try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
            #expect(Bool(false), "Expected creation to fail")
        } catch let error as AuthenticationError {
            if case .authenticationFailed(let message) = error {
                #expect(message.contains("invalid-url"))
            } else {
                #expect(Bool(false), "Unexpected error case: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
    
    @Test("Factory should throw error for OAuth Discovery with invalid clientId")
    func testCreateOAuthDiscoveryProviderInvalidClientId() async throws {
        let config = JSON.object([
            "resourceServerURL": .string("https://mcp.example.com"),
            "clientId": .string(""), // Empty string to trigger validation error
            "redirectURI": .string("https://client.example.com/callback"),
            "useOAuthDiscovery": .boolean(true)
        ])
        
        do {
            _ = try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
            #expect(Bool(false), "Expected creation to fail")
        } catch let error as AuthenticationError {
            if case .authenticationFailed(let message) = error {
                #expect(message.contains("OAuth Discovery config missing 'clientId' field"))
            } else {
                #expect(Bool(false), "Unexpected error case: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
    
    @Test("Factory should throw error for OAuth Discovery with invalid redirectURI")
    func testCreateOAuthDiscoveryProviderInvalidRedirectURI() async throws {
        let config = JSON.object([
            "resourceServerURL": .string("https://mcp.example.com"),
            "clientId": .string("test-client-id"),
            "redirectURI": .string("invalid-uri"),
            "useOAuthDiscovery": .boolean(true)
        ])
        
        do {
            _ = try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
            #expect(Bool(false), "Expected creation to fail")
        } catch let error as AuthenticationError {
            if case .authenticationFailed(let message) = error {
                #expect(message.contains("invalid-uri"))
            } else {
                #expect(Bool(false), "Unexpected error case: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
}
