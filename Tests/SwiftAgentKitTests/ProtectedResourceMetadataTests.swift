//
//  ProtectedResourceMetadataTests.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Testing
import Foundation
import SwiftAgentKit

@Suite("ProtectedResourceMetadata Tests")
struct ProtectedResourceMetadataTests {
    
    @Test("Parse valid protected resource metadata")
    func testParseValidProtectedResourceMetadata() throws {
        let jsonData = """
        {
            "issuer": "https://auth.example.com",
            "authorization_endpoint": "https://auth.example.com/oauth/authorize",
            "token_endpoint": "https://auth.example.com/oauth/token",
            "jwks_uri": "https://auth.example.com/.well-known/jwks.json",
            "token_endpoint_auth_methods_supported": ["client_secret_post", "client_secret_basic", "none"],
            "grant_types_supported": ["authorization_code", "refresh_token"],
            "code_challenge_methods_supported": ["S256", "plain"],
            "response_types_supported": ["code"],
            "response_modes_supported": ["query", "fragment"],
            "scopes_supported": ["openid", "profile", "email"],
            "userinfo_endpoint": "https://auth.example.com/oauth/userinfo",
            "subject_types_supported": ["public"],
            "token_endpoint_auth_signing_alg_values_supported": ["RS256"],
            "revocation_endpoint": "https://auth.example.com/oauth/revoke",
            "introspection_endpoint": "https://auth.example.com/oauth/introspect",
            "resource": "https://mcp.example.com",
            "authorization_request_parameters_supported": ["client_id", "response_type", "redirect_uri"],
            "authorization_response_parameters_supported": ["code", "state"]
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: jsonData)
        
        #expect(metadata.issuer == "https://auth.example.com")
        #expect(metadata.authorizationEndpoint == "https://auth.example.com/oauth/authorize")
        #expect(metadata.tokenEndpoint == "https://auth.example.com/oauth/token")
        #expect(metadata.resource == "https://mcp.example.com")
        #expect(metadata.codeChallengeMethodsSupported?.contains("S256") == true)
        #expect(metadata.grantTypesSupported?.contains("authorization_code") == true)
        #expect(metadata.tokenEndpointAuthMethodsSupported?.contains("none") == true)
        #expect(metadata.authorizationRequestParametersSupported?.contains("client_id") == true)
        #expect(metadata.authorizationResponseParametersSupported?.contains("code") == true)
    }
    
    @Test("Validate PKCE support - supported")
    func testValidatePKCESupportSupported() throws {
        let jsonData = """
        {
            "code_challenge_methods_supported": ["S256", "plain"]
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: jsonData)
        
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
        
        let metadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: jsonData)
        
        #expect(throws: ProtectedResourceMetadataError.self) {
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
        
        let metadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: jsonData)
        
        #expect(throws: ProtectedResourceMetadataError.self) {
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
        
        let metadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: jsonData)
        
        #expect(throws: ProtectedResourceMetadataError.self) {
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
        
        let metadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: jsonData)
        
        #expect(metadata.supportsAuthorizationCodeGrant() == true)
    }
    
    @Test("Check authorization code grant support - not supported")
    func testCheckAuthorizationCodeGrantSupportNotSupported() throws {
        let jsonData = """
        {
            "grant_types_supported": ["client_credentials"]
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: jsonData)
        
        #expect(metadata.supportsAuthorizationCodeGrant() == false)
    }
    
    @Test("Check public client authentication support")
    func testCheckPublicClientAuthenticationSupport() throws {
        let jsonData = """
        {
            "token_endpoint_auth_methods_supported": ["client_secret_post", "none"]
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: jsonData)
        
        #expect(metadata.supportsPublicClientAuthentication() == true)
    }
    
    @Test("Check public client authentication support - not supported")
    func testCheckPublicClientAuthenticationSupportNotSupported() throws {
        let jsonData = """
        {
            "token_endpoint_auth_methods_supported": ["client_secret_post", "client_secret_basic"]
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: jsonData)
        
        #expect(metadata.supportsPublicClientAuthentication() == false)
    }
    
    @Test("Extract authorization server URL")
    func testExtractAuthorizationServerURL() throws {
        let jsonData = """
        {
            "issuer": "https://auth.example.com"
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: jsonData)
        
        let authServerURL = metadata.authorizationServerURL()
        #expect(authServerURL?.absoluteString == "https://auth.example.com")
    }
    
    @Test("Extract authorization server URL - no issuer")
    func testExtractAuthorizationServerURLNoIssuer() throws {
        let jsonData = """
        {
            "authorization_endpoint": "https://auth.example.com/oauth/authorize"
        }
        """.data(using: .utf8)!
        
        let metadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: jsonData)
        
        let authServerURL = metadata.authorizationServerURL()
        #expect(authServerURL == nil)
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
            "introspection_endpoint": "https://auth.example.com/oauth/introspect",
            "resource": "https://mcp.example.com",
            "authorization_request_parameters_supported": ["client_id", "response_type"],
            "authorization_response_parameters_supported": ["code", "state"]
        }
        """.data(using: .utf8)!
        
        let originalMetadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: jsonData)
        let encoded = try JSONEncoder().encode(originalMetadata)
        let decoded = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: encoded)
        
        #expect(decoded.issuer == originalMetadata.issuer)
        #expect(decoded.authorizationEndpoint == originalMetadata.authorizationEndpoint)
        #expect(decoded.tokenEndpoint == originalMetadata.tokenEndpoint)
        #expect(decoded.resource == originalMetadata.resource)
        #expect(decoded.codeChallengeMethodsSupported == originalMetadata.codeChallengeMethodsSupported)
        #expect(decoded.authorizationRequestParametersSupported == originalMetadata.authorizationRequestParametersSupported)
        #expect(decoded.authorizationResponseParametersSupported == originalMetadata.authorizationResponseParametersSupported)
    }
}

@Suite("WWWAuthenticateParser Tests")
struct WWWAuthenticateParserTests {
    
    @Test("Parse simple Bearer challenge")
    func testParseSimpleBearerChallenge() throws {
        let headerValue = "Bearer realm=\"example\", resource_metadata=\"https://mcp.example.com/.well-known/oauth-protected-resource\""
        
        let parameters = WWWAuthenticateParser.parseWWWAuthenticateHeader(headerValue)
        
        #expect(parameters["realm"] == "example")
        #expect(parameters["resource_metadata"] == "https://mcp.example.com/.well-known/oauth-protected-resource")
    }
    
    @Test("Parse OAuth challenge with multiple parameters")
    func testParseOAuthChallengeWithMultipleParameters() throws {
        let headerValue = "OAuth realm=\"mcp-server\", resource_metadata=\"https://mcp.example.com/.well-known/oauth-protected-resource/mcp\", error=\"invalid_token\", error_description=\"The access token expired\""
        
        let parameters = WWWAuthenticateParser.parseWWWAuthenticateHeader(headerValue)
        
        #expect(parameters["realm"] == "mcp-server")
        #expect(parameters["resource_metadata"] == "https://mcp.example.com/.well-known/oauth-protected-resource/mcp")
        #expect(parameters["error"] == "invalid_token")
        #expect(parameters["error_description"] == "The access token expired")
    }
    
    @Test("Parse multiple challenges")
    func testParseMultipleChallenges() throws {
        let headerValue = "Bearer realm=\"example\", resource_metadata=\"https://mcp.example.com/.well-known/oauth-protected-resource\", OAuth realm=\"alternative\""
        
        let parameters = WWWAuthenticateParser.parseWWWAuthenticateHeader(headerValue)
        
        #expect(parameters["realm"] == "alternative") // Last one wins
        #expect(parameters["resource_metadata"] == "https://mcp.example.com/.well-known/oauth-protected-resource")
    }
    
    @Test("Parse challenge with quoted values")
    func testParseChallengeWithQuotedValues() throws {
        let headerValue = "Bearer realm=\"example with spaces\", resource_metadata=\"https://mcp.example.com/.well-known/oauth-protected-resource\""
        
        let parameters = WWWAuthenticateParser.parseWWWAuthenticateHeader(headerValue)
        
        #expect(parameters["realm"] == "example with spaces")
        #expect(parameters["resource_metadata"] == "https://mcp.example.com/.well-known/oauth-protected-resource")
    }
    
    @Test("Parse challenge with unquoted values")
    func testParseChallengeWithUnquotedValues() throws {
        let headerValue = "Bearer realm=example, resource_metadata=https://mcp.example.com/.well-known/oauth-protected-resource"
        
        let parameters = WWWAuthenticateParser.parseWWWAuthenticateHeader(headerValue)
        
        #expect(parameters["realm"] == "example")
        #expect(parameters["resource_metadata"] == "https://mcp.example.com/.well-known/oauth-protected-resource")
    }
    
    @Test("Parse challenge with non-OAuth scheme")
    func testParseChallengeWithNonOAuthScheme() throws {
        let headerValue = "Basic realm=\"example\", Digest realm=\"alternative\", Bearer resource_metadata=\"https://mcp.example.com/.well-known/oauth-protected-resource\""
        
        let parameters = WWWAuthenticateParser.parseWWWAuthenticateHeader(headerValue)
        
        #expect(parameters["resource_metadata"] == "https://mcp.example.com/.well-known/oauth-protected-resource")
        #expect(parameters["realm"] == nil) // Basic and Digest challenges should be ignored
    }
    
    @Test("Parse empty header")
    func testParseEmptyHeader() throws {
        let headerValue = ""
        
        let parameters = WWWAuthenticateParser.parseWWWAuthenticateHeader(headerValue)
        
        #expect(parameters.isEmpty == true)
    }
    
    @Test("Parse header with no OAuth schemes")
    func testParseHeaderWithNoOAuthSchemes() throws {
        let headerValue = "Basic realm=\"example\", Digest realm=\"alternative\""
        
        let parameters = WWWAuthenticateParser.parseWWWAuthenticateHeader(headerValue)
        
        #expect(parameters.isEmpty == true)
    }
}
