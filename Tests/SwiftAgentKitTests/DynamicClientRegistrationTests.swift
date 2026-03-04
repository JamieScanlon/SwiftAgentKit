//
//  DynamicClientRegistrationTests.swift
//  SwiftAgentKitTests
//

import Testing
import Foundation
@testable import SwiftAgentKit

/// Tests for Dynamic Client Registration models (RFC 7591)
struct DynamicClientRegistrationTests {

    // MARK: - ClientRegistrationRequest

    @Test("ClientRegistrationRequest mcpClientRequest creates valid request")
    func mcpClientRequest() throws {
        let request = DynamicClientRegistration.ClientRegistrationRequest.mcpClientRequest(
            redirectUris: ["https://app.example/callback"],
            clientName: "Test MCP Client",
            scope: "mcp openid"
        )
        #expect(request.redirectUris == ["https://app.example/callback"])
        #expect(request.applicationType == "native")
        #expect(request.clientName == "Test MCP Client")
        #expect(request.tokenEndpointAuthMethod == "none")
        #expect(request.grantTypes?.contains("authorization_code") == true)
        #expect(request.grantTypes?.contains("refresh_token") == true)
        #expect(request.responseTypes == ["code"])
        #expect(request.scope == "mcp openid")
    }

    @Test("ClientRegistrationRequest mcpClientRequest with nil clientName uses default")
    func mcpClientRequestDefaultName() throws {
        let request = DynamicClientRegistration.ClientRegistrationRequest.mcpClientRequest(
            redirectUris: ["http://localhost/cb"],
            clientName: nil,
            scope: nil
        )
        #expect(request.clientName == "MCP Client")
        #expect(request.scope == "mcp")
    }

    @Test("ClientRegistrationRequest encode and decode roundtrip")
    func requestEncodeDecode() throws {
        let request = DynamicClientRegistration.ClientRegistrationRequest(
            redirectUris: ["https://example.com/cb"],
            applicationType: "native",
            clientName: "Test",
            grantTypes: ["authorization_code"],
            responseTypes: ["code"],
            scope: "mcp"
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DynamicClientRegistration.ClientRegistrationRequest.self, from: data)
        #expect(decoded.redirectUris == request.redirectUris)
        #expect(decoded.applicationType == request.applicationType)
        #expect(decoded.clientName == request.clientName)
        #expect(decoded.scope == request.scope)
    }

    @Test("ClientRegistrationRequest CodingKeys use snake_case")
    func requestCodingKeys() throws {
        let request = DynamicClientRegistration.ClientRegistrationRequest.mcpClientRequest(
            redirectUris: ["https://x/cb"],
            clientName: "Name",
            scope: "s"
        )
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["redirect_uris"] != nil)
        #expect(json?["application_type"] as? String == "native")
        #expect(json?["client_name"] as? String == "Name")
    }

    // MARK: - ClientRegistrationResponse

    @Test("ClientRegistrationResponse encode and decode roundtrip")
    func responseEncodeDecode() throws {
        let response = DynamicClientRegistration.ClientRegistrationResponse(
            clientId: "client-123",
            clientSecret: "secret-456",
            clientIdIssuedAt: 1234567890,
            clientSecretExpiresAt: 3600,
            redirectUris: ["https://example.com/cb"],
            applicationType: "native",
            clientName: "Test Client",
            scope: "mcp"
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(DynamicClientRegistration.ClientRegistrationResponse.self, from: data)
        #expect(decoded.clientId == response.clientId)
        #expect(decoded.clientSecret == response.clientSecret)
        #expect(decoded.clientIdIssuedAt == response.clientIdIssuedAt)
        #expect(decoded.clientSecretExpiresAt == response.clientSecretExpiresAt)
        #expect(decoded.redirectUris == response.redirectUris)
        #expect(decoded.clientName == response.clientName)
        #expect(decoded.scope == response.scope)
    }

    @Test("ClientRegistrationResponse CodingKeys use snake_case")
    func responseCodingKeys() throws {
        let response = DynamicClientRegistration.ClientRegistrationResponse(
            clientId: "id",
            clientSecret: "secret",
            clientIdIssuedAt: 1,
            clientSecretExpiresAt: nil,
            redirectUris: nil,
            clientName: "Name",
            scope: "s"
        )
        let data = try JSONEncoder().encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["client_id"] as? String == "id")
        #expect(json?["client_secret"] as? String == "secret")
        #expect(json?["client_id_issued_at"] as? Int == 1)
        #expect(json?["client_name"] as? String == "Name")
    }

    // MARK: - ClientRegistrationError

    @Test("ClientRegistrationError encode and decode")
    func registrationErrorEncodeDecode() throws {
        let error = DynamicClientRegistration.ClientRegistrationError(
            error: "invalid_redirect_uri",
            errorDescription: "Redirect URI not allowed",
            errorUri: "https://docs.example/errors"
        )
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(DynamicClientRegistration.ClientRegistrationError.self, from: data)
        #expect(decoded.error == error.error)
        #expect(decoded.errorDescription == error.errorDescription)
        #expect(decoded.errorUri == error.errorUri)
    }

    // MARK: - DynamicClientRegistrationConfig

    @Test("DynamicClientRegistrationConfig init and encode")
    func configInit() throws {
        let url = URL(string: "https://auth.example.com/register")!
        let config = DynamicClientRegistrationConfig(
            registrationEndpoint: url,
            initialAccessToken: "token",
            registrationAuthMethod: "bearer",
            additionalHeaders: ["X-Custom": "value"],
            requestTimeout: 30.0
        )
        #expect(config.registrationEndpoint == url)
        #expect(config.initialAccessToken == "token")
        #expect(config.registrationAuthMethod == "bearer")
        #expect(config.additionalHeaders?["X-Custom"] == "value")
        #expect(config.requestTimeout == 30.0)
    }

    @Test("DynamicClientRegistrationConfig fromServerMetadata returns nil when no endpoint")
    func configFromMetadataNil() throws {
        let metadata = OAuthServerMetadata(
            issuer: "https://auth.example.com",
            authorizationEndpoint: "https://auth.example.com/authorize",
            tokenEndpoint: "https://auth.example.com/token",
            registrationEndpoint: nil
        )
        let config = DynamicClientRegistrationConfig.fromServerMetadata(metadata)
        #expect(config == nil)
    }

    @Test("DynamicClientRegistrationConfig fromServerMetadata returns config when endpoint present")
    func configFromMetadataSuccess() throws {
        let metadata = OAuthServerMetadata(
            issuer: "https://auth.example.com",
            authorizationEndpoint: "https://auth.example.com/authorize",
            tokenEndpoint: "https://auth.example.com/token",
            registrationEndpoint: "https://auth.example.com/register",
            registrationEndpointAuthMethodsSupported: ["bearer"]
        )
        let config = DynamicClientRegistrationConfig.fromServerMetadata(metadata)
        #expect(config != nil)
        #expect(config?.registrationEndpoint.absoluteString == "https://auth.example.com/register")
        #expect(config?.registrationAuthMethod == "bearer")
    }
}
