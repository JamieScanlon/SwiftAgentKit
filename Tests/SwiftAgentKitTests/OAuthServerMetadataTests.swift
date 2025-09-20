//
//  OAuthServerMetadataTests.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Testing
import Foundation
import SwiftAgentKit

@Suite("OAuthServerMetadata Tests")
struct OAuthServerMetadataTests {
    
    @Test("Parse valid OAuth server metadata")
    func testParseValidOAuthServerMetadata() throws {
        let jsonData = """
        {
            "issuer": "https://auth.example.com",
            "authorization_endpoint": "https://auth.example.com/oauth/authorize",
            "token_endpoint": "https://auth.example.com/oauth/token",
            "token_endpoint_auth_methods_supported": ["client_secret_post", "client_secret_basic", "none"],
            "grant_types_supported": ["authorization_code", "refresh_token"],
            "code_challenge_methods_supported": ["S256", "plain"],
            "response_types_supported": ["code"],
            "response_modes_supported": ["query", "fragment"],
            "scopes_supported": ["openid", "profile", "email"],
            "jwks_uri": "https://auth.example.com/.well-known/jwks.json",
            "userinfo_endpoint": "https://auth.example.com/oauth/userinfo",
            "subject_types_supported": ["public"],
            "token_endpoint_auth_signing_alg_values_supported": ["RS256"],
            "revocation_endpoint": "https://auth.example.com/oauth/revoke",
            "introspection_endpoint": "https://auth.example.com/oauth/introspect"
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(OAuthServerMetadata.self, from: jsonData)
        
        #expect(metadata.issuer == "https://auth.example.com")
        #expect(metadata.authorizationEndpoint == "https://auth.example.com/oauth/authorize")
        #expect(metadata.tokenEndpoint == "https://auth.example.com/oauth/token")
        #expect(metadata.codeChallengeMethodsSupported?.contains("S256") == true)
        #expect(metadata.grantTypesSupported?.contains("authorization_code") == true)
        #expect(metadata.tokenEndpointAuthMethodsSupported?.contains("none") == true)
    }
    
    @Test("Validate PKCE support - supported")
    func testValidatePKCESupportSupported() throws {
        let jsonData = """
        {
            "code_challenge_methods_supported": ["S256", "plain"]
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(OAuthServerMetadata.self, from: jsonData)
        
        let isSupported = try metadata.validatePKCESupport()
        #expect(isSupported == true)
    }
    
    @Test("Validate PKCE support - not supported (missing field)")
    func testValidatePKCESupportMissingField() throws {
        let jsonData = """
        {
            "issuer": "https://auth.example.com"
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(OAuthServerMetadata.self, from: jsonData)
        
        #expect(throws: OAuthMetadataError.self) {
            try metadata.validatePKCESupport()
        }
    }
    
    @Test("Validate PKCE support - not supported (empty array)")
    func testValidatePKCESupportEmptyArray() throws {
        let jsonData = """
        {
            "code_challenge_methods_supported": []
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(OAuthServerMetadata.self, from: jsonData)
        
        #expect(throws: OAuthMetadataError.self) {
            try metadata.validatePKCESupport()
        }
    }
    
    @Test("Validate PKCE support - not supported (no S256)")
    func testValidatePKCESupportNoS256() throws {
        let jsonData = """
        {
            "code_challenge_methods_supported": ["plain"]
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(OAuthServerMetadata.self, from: jsonData)
        
        #expect(throws: OAuthMetadataError.self) {
            try metadata.validatePKCESupport()
        }
    }
    
    @Test("Check authorization code grant support")
    func testCheckAuthorizationCodeGrantSupport() throws {
        let jsonData = """
        {
            "grant_types_supported": ["authorization_code", "refresh_token"]
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(OAuthServerMetadata.self, from: jsonData)
        
        #expect(metadata.supportsAuthorizationCodeGrant() == true)
    }
    
    @Test("Check authorization code grant support - not supported")
    func testCheckAuthorizationCodeGrantSupportNotSupported() throws {
        let jsonData = """
        {
            "grant_types_supported": ["client_credentials"]
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(OAuthServerMetadata.self, from: jsonData)
        
        #expect(metadata.supportsAuthorizationCodeGrant() == false)
    }
    
    @Test("Check public client authentication support")
    func testCheckPublicClientAuthenticationSupport() throws {
        let jsonData = """
        {
            "token_endpoint_auth_methods_supported": ["client_secret_post", "none"]
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(OAuthServerMetadata.self, from: jsonData)
        
        #expect(metadata.supportsPublicClientAuthentication() == true)
    }
    
    @Test("Check public client authentication support - not supported")
    func testCheckPublicClientAuthenticationSupportNotSupported() throws {
        let jsonData = """
        {
            "token_endpoint_auth_methods_supported": ["client_secret_post", "client_secret_basic"]
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(OAuthServerMetadata.self, from: jsonData)
        
        #expect(metadata.supportsPublicClientAuthentication() == false)
    }
    
    @Test("Parse OpenID Connect provider metadata")
    func testParseOpenIDConnectProviderMetadata() throws {
        let jsonData = """
        {
            "issuer": "https://auth.example.com",
            "authorization_endpoint": "https://auth.example.com/oauth/authorize",
            "token_endpoint": "https://auth.example.com/oauth/token",
            "code_challenge_methods_supported": ["S256"],
            "userinfo_endpoint": "https://auth.example.com/oauth/userinfo",
            "claims_supported": ["sub", "name", "email"],
            "claim_types_supported": ["normal"],
            "response_types_supported": ["code"],
            "subject_types_supported": ["public"],
            "response_modes_supported": ["query"]
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(OpenIDConnectProviderMetadata.self, from: jsonData)
        
        #expect(metadata.oauthMetadata.issuer == "https://auth.example.com")
        #expect(metadata.userinfoEndpoint == "https://auth.example.com/oauth/userinfo")
        #expect(metadata.claimsSupported?.contains("sub") == true)
        #expect(metadata.claimTypesSupported?.contains("normal") == true)
    }
    
    @Test("OpenID Connect metadata PKCE validation")
    func testOpenIDConnectMetadataPKCEValidation() throws {
        let jsonData = """
        {
            "code_challenge_methods_supported": ["S256"]
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(OpenIDConnectProviderMetadata.self, from: jsonData)
        
        let isSupported = try metadata.validatePKCESupport()
        #expect(isSupported == true)
    }
    
    
    @Test("Encode and decode metadata")
    func testEncodeAndDecodeMetadata() throws {
        let jsonData = """
        {
            "issuer": "https://auth.example.com",
            "authorization_endpoint": "https://auth.example.com/oauth/authorize",
            "token_endpoint": "https://auth.example.com/oauth/token",
            "token_endpoint_auth_methods_supported": ["client_secret_post", "none"],
            "grant_types_supported": ["authorization_code"],
            "code_challenge_methods_supported": ["S256"],
            "response_types_supported": ["code"],
            "response_modes_supported": ["query"],
            "scopes_supported": ["openid", "profile"],
            "jwks_uri": "https://auth.example.com/.well-known/jwks.json",
            "userinfo_endpoint": "https://auth.example.com/oauth/userinfo",
            "subject_types_supported": ["public"],
            "token_endpoint_auth_signing_alg_values_supported": ["RS256"],
            "revocation_endpoint": "https://auth.example.com/oauth/revoke",
            "introspection_endpoint": "https://auth.example.com/oauth/introspect"
        }
        """.data(using: .utf8)!
        
        let originalMetadata = try JSONDecoder().decode(OAuthServerMetadata.self, from: jsonData)
        let encoded = try JSONEncoder().encode(originalMetadata)
        let decoded = try JSONDecoder().decode(OAuthServerMetadata.self, from: encoded)
        
        #expect(decoded.issuer == originalMetadata.issuer)
        #expect(decoded.authorizationEndpoint == originalMetadata.authorizationEndpoint)
        #expect(decoded.tokenEndpoint == originalMetadata.tokenEndpoint)
        #expect(decoded.codeChallengeMethodsSupported == originalMetadata.codeChallengeMethodsSupported)
    }
}

