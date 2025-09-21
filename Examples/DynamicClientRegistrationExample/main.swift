//
//  main.swift
//  DynamicClientRegistrationExample
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Foundation
import SwiftAgentKit
import SwiftAgentKitMCP
import Logging

/// Example demonstrating OAuth 2.0 Dynamic Client Registration (RFC 7591) with MCP
/// This example shows how to automatically register with authorization servers
/// without requiring manual client ID configuration.
@main
struct DynamicClientRegistrationExample {
    
    static func main() async {
        // Set up logging
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .info
            return handler
        }
        
        let logger = Logger(label: "DynamicClientRegistrationExample")
        logger.info("Starting Dynamic Client Registration Example")
        
        do {
            // Example 1: Basic Dynamic Client Registration
            try await basicDynamicClientRegistrationExample()
            
            // Example 2: MCP Server with Dynamic Client Registration
            try await mcpServerWithDynamicClientRegistrationExample()
            
            // Example 3: Dynamic Client Registration from OAuth Discovery
            try await dynamicClientRegistrationFromDiscoveryExample()
            
            logger.info("Dynamic Client Registration Example completed successfully")
            
        } catch {
            logger.error("Dynamic Client Registration Example failed: \(error)")
            exit(1)
        }
    }
    
    /// Example 1: Basic Dynamic Client Registration
    static func basicDynamicClientRegistrationExample() async throws {
        let logger = Logger(label: "BasicDynamicClientRegistration")
        logger.info("=== Basic Dynamic Client Registration Example ===")
        
        // Create registration configuration
        guard let registrationEndpoint = URL(string: "https://auth.example.com/register") else {
            throw ExampleError.invalidURL("Invalid registration endpoint URL")
        }
        
        let registrationConfig = DynamicClientRegistrationConfig(
            registrationEndpoint: registrationEndpoint,
            initialAccessToken: nil, // No initial access token required
            registrationAuthMethod: nil,
            additionalHeaders: nil,
            requestTimeout: 30.0
        )
        
        // Create registration request for an MCP client
        let registrationRequest = DynamicClientRegistration.ClientRegistrationRequest.mcpClientRequest(
            redirectUris: ["https://example.com/mcp/callback"],
            clientName: "SwiftAgentKit MCP Client",
            scope: "mcp read write"
        )
        
        logger.info("Registration request created:")
        logger.info("- Client Name: \(registrationRequest.clientName ?? "Unknown")")
        logger.info("- Redirect URIs: \(registrationRequest.redirectUris.joined(separator: ", "))")
        logger.info("- Scope: \(registrationRequest.scope ?? "None")")
        logger.info("- Grant Types: \(registrationRequest.grantTypes?.joined(separator: ", ") ?? "None")")
        
        // Note: In a real implementation, you would call the registration client
        // For this example, we'll simulate the response
        let simulatedResponse = DynamicClientRegistration.ClientRegistrationResponse(
            clientId: "example-client-12345",
            clientSecret: "example-secret-67890",
            clientIdIssuedAt: Int(Date().timeIntervalSince1970),
            clientSecretExpiresAt: nil,
            redirectUris: registrationRequest.redirectUris,
            applicationType: registrationRequest.applicationType,
            clientName: registrationRequest.clientName,
            scope: registrationRequest.scope
        )
        
        logger.info("Registration successful!")
        logger.info("- Client ID: \(simulatedResponse.clientId)")
        logger.info("- Client Secret: \(simulatedResponse.clientSecret?.prefix(8).appending("...") ?? "None")")
        logger.info("- Issued At: \(Date(timeIntervalSince1970: TimeInterval(simulatedResponse.clientIdIssuedAt ?? 0)))")
        
        logger.info("Basic Dynamic Client Registration Example completed")
    }
    
    /// Example 2: MCP Server with Dynamic Client Registration
    static func mcpServerWithDynamicClientRegistrationExample() async throws {
        let logger = Logger(label: "MCPDynamicClientRegistration")
        logger.info("=== MCP Server with Dynamic Client Registration Example ===")
        
        // Create MCP configuration with dynamic client registration
        var mcpConfig = MCPConfig()
        
        // Add a remote server with dynamic client registration
        let remoteServer = MCPConfigHelper.createRemoteServerWithDynamicClientRegistration(
            name: "example-mcp-server",
            url: "https://mcp.example.com",
            registrationEndpoint: "https://auth.example.com/register",
            redirectUris: ["https://example.com/mcp/callback"],
            clientName: "SwiftAgentKit MCP Client",
            scope: "mcp read write",
            initialAccessToken: nil,
            softwareStatement: nil,
            useCredentialStorage: true,
            connectionTimeout: 30.0,
            requestTimeout: 60.0,
            maxRetries: 3
        )
        
        mcpConfig.remoteServers.append(remoteServer)
        
        logger.info("MCP Configuration created with dynamic client registration:")
        logger.info("- Server Name: \(remoteServer.name)")
        logger.info("- Server URL: \(remoteServer.url)")
        logger.info("- Auth Type: \(remoteServer.authType ?? "None")")
        logger.info("- Connection Timeout: \(remoteServer.connectionTimeout ?? 0) seconds")
        logger.info("- Request Timeout: \(remoteServer.requestTimeout ?? 0) seconds")
        logger.info("- Max Retries: \(remoteServer.maxRetries ?? 0)")
        
        // Display auth configuration
        if let authConfig = remoteServer.authConfig {
            logger.info("Auth Configuration:")
            if case .object(let authDict) = authConfig {
                for (key, value) in authDict {
                    let valueString = switch value {
                    case .string(let str): str
                    case .boolean(let bool): String(bool)
                    case .integer(let int): String(int)
                    case .double(let double): String(double)
                    default: "\(value)"
                    }
                    logger.info("  - \(key): \(valueString)")
                }
            }
        }
        
        // Create MCP Manager (this would normally connect to real servers)
        let mcpManager = MCPManager()
        
        logger.info("MCP Manager created with dynamic client registration support")
        logger.info("Note: In a real implementation, this would connect to the MCP server")
        logger.info("and automatically register the client with the authorization server")
        
        logger.info("MCP Server with Dynamic Client Registration Example completed")
    }
    
    /// Example 3: Dynamic Client Registration from OAuth Discovery
    static func dynamicClientRegistrationFromDiscoveryExample() async throws {
        let logger = Logger(label: "DynamicClientRegistrationFromDiscovery")
        logger.info("=== Dynamic Client Registration from OAuth Discovery Example ===")
        
        // Simulate OAuth server metadata discovery
        let serverMetadata = OAuthServerMetadata(
            issuer: "https://auth.example.com",
            authorizationEndpoint: "https://auth.example.com/auth",
            tokenEndpoint: "https://auth.example.com/token",
            tokenEndpointAuthMethodsSupported: ["client_secret_basic", "client_secret_post"],
            grantTypesSupported: ["authorization_code", "refresh_token", "client_credentials"],
            codeChallengeMethodsSupported: ["S256", "plain"],
            responseTypesSupported: ["code"],
            responseModesSupported: ["query", "fragment"],
            scopesSupported: ["mcp", "read", "write", "admin"],
            jwksUri: "https://auth.example.com/jwks",
            userinfoEndpoint: "https://auth.example.com/userinfo",
            subjectTypesSupported: ["public", "pairwise"],
            tokenEndpointAuthSigningAlgValuesSupported: ["RS256", "ES256"],
            registrationEndpoint: "https://auth.example.com/register",
            registrationEndpointAuthMethodsSupported: ["client_secret_basic", "none"],
            registrationEndpointFieldsSupported: ["redirect_uris", "client_name", "logo_uri", "tos_uri"],
            softwareStatementFieldsSupported: ["software_id", "software_version"],
            revocationEndpoint: "https://auth.example.com/revoke",
            introspectionEndpoint: "https://auth.example.com/introspect"
        )
        
        logger.info("OAuth Server Metadata discovered:")
        logger.info("- Issuer: \(serverMetadata.issuer ?? "Unknown")")
        logger.info("- Authorization Endpoint: \(serverMetadata.authorizationEndpoint ?? "Unknown")")
        logger.info("- Token Endpoint: \(serverMetadata.tokenEndpoint ?? "Unknown")")
        logger.info("- Registration Endpoint: \(serverMetadata.registrationEndpoint ?? "Not supported")")
        logger.info("- Supported Grant Types: \(serverMetadata.grantTypesSupported?.joined(separator: ", ") ?? "None")")
        logger.info("- Supported Scopes: \(serverMetadata.scopesSupported?.joined(separator: ", ") ?? "None")")
        logger.info("- Code Challenge Methods: \(serverMetadata.codeChallengeMethodsSupported?.joined(separator: ", ") ?? "None")")
        
        // Create dynamic client registration config from metadata
        if let registrationConfig = DynamicClientRegistrationConfig.fromServerMetadata(
            serverMetadata,
            initialAccessToken: nil,
            additionalHeaders: ["X-Client-Version": "1.0.0"]
        ) {
            logger.info("Dynamic Client Registration configuration created from metadata:")
            logger.info("- Registration Endpoint: \(registrationConfig.registrationEndpoint)")
            logger.info("- Registration Auth Method: \(registrationConfig.registrationAuthMethod ?? "None")")
            logger.info("- Additional Headers: \(registrationConfig.additionalHeaders?.description ?? "None")")
            
            // Create MCP server configuration using the discovered metadata
            let remoteServer = MCPConfigHelper.createRemoteServerWithDynamicClientRegistrationFromMetadata(
                name: "discovered-mcp-server",
                url: "https://mcp.example.com",
                serverMetadata: serverMetadata,
                redirectUris: ["https://example.com/mcp/callback"],
                clientName: "SwiftAgentKit Discovery Client",
                scope: "mcp read write"
            )
            
            if let server = remoteServer {
                logger.info("MCP Server configuration created from OAuth discovery:")
                logger.info("- Server Name: \(server.name)")
                logger.info("- Server URL: \(server.url)")
                logger.info("- Auth Type: \(server.authType ?? "None")")
                
                logger.info("This configuration would automatically:")
                logger.info("1. Register the client with the authorization server")
                logger.info("2. Obtain client credentials")
                logger.info("3. Store credentials securely")
                logger.info("4. Use credentials for MCP server authentication")
            } else {
                logger.warning("Failed to create MCP server configuration - registration endpoint not available")
            }
        } else {
            logger.warning("Dynamic Client Registration not supported by this authorization server")
            logger.info("Fallback options:")
            logger.info("1. Use pre-configured client ID")
            logger.info("2. Present UI for manual client registration")
            logger.info("3. Use alternative authentication method")
        }
        
        logger.info("Dynamic Client Registration from OAuth Discovery Example completed")
    }
}

/// Example-specific errors
enum ExampleError: LocalizedError {
    case invalidURL(String)
    case registrationFailed(String)
    case discoveryFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let message):
            return "Invalid URL: \(message)"
        case .registrationFailed(let message):
            return "Registration failed: \(message)"
        case .discoveryFailed(let message):
            return "Discovery failed: \(message)"
        }
    }
}

/// Extension to provide additional logging utilities
extension Logger {
    func info(_ message: String, metadata: Logger.Metadata? = nil) {
        self.info("\(message)", metadata: metadata)
    }
    
    func warning(_ message: String, metadata: Logger.Metadata? = nil) {
        self.warning("\(message)", metadata: metadata)
    }
    
    func error(_ message: String, metadata: Logger.Metadata? = nil) {
        self.error("\(message)", metadata: metadata)
    }
}
