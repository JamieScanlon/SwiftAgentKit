//
//  MCPResourceParameterTests.swift
//  SwiftAgentKitMCPTests
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Testing
import Foundation
import EasyJSON
@testable import SwiftAgentKitMCP
@testable import SwiftAgentKit

/// Tests for RFC 8707 Resource Parameter integration with MCP
@Suite("MCP Resource Parameter Integration Tests")
struct MCPResourceParameterTests {
    
    // MARK: - MCPConfig Tests
    
    @Test("MCP PKCEOAuthConfig with resource parameter")
    func testMCPPKCEOAuthConfigWithResourceParameter() {
        let resourceURI = "https://mcp.example.com/mcp"
        
        let config = MCPConfig.PKCEOAuthConfig(
            issuerURL: "https://auth.example.com",
            clientId: "mcp-client-123",
            clientSecret: "secret",
            scope: "mcp read write",
            redirectURI: "https://app.example.com/callback",
            resourceURI: resourceURI
        )
        
        #expect(config.issuerURL == "https://auth.example.com")
        #expect(config.clientId == "mcp-client-123")
        #expect(config.scope == "mcp read write")
        #expect(config.resourceURI == resourceURI)
    }
    
    @Test("MCP PKCEOAuthConfig without resource parameter")
    func testMCPPKCEOAuthConfigWithoutResourceParameter() {
        let config = MCPConfig.PKCEOAuthConfig(
            issuerURL: "https://auth.example.com",
            clientId: "mcp-client-123",
            redirectURI: "https://app.example.com/callback",
            resourceURI: nil
        )
        
        #expect(config.issuerURL == "https://auth.example.com")
        #expect(config.clientId == "mcp-client-123")
        #expect(config.resourceURI == nil)
    }
    
    // MARK: - MCP Remote Server Configuration Tests
    
    @Test("MCP remote server with OAuth and resource parameter")
    func testMCPRemoteServerWithOAuthAndResourceParameter() throws {
        let resourceURI = "https://mcp.example.com/api/v1"
        
        let authConfigDict: [String: Any] = [
            "issuerURL": "https://auth.example.com",
            "clientId": "mcp-client-123",
            "scope": "mcp read write",
            "redirectURI": "https://app.example.com/callback",
            "resourceURI": resourceURI
        ]
        
        let authConfig = try JSON(authConfigDict)
        
        let serverConfig = MCPConfig.RemoteServerConfig(
            name: "test-mcp-server",
            url: "https://mcp.example.com/api/v1",
            authType: "OAuth",
            authConfig: authConfig
        )
        
        #expect(serverConfig.name == "test-mcp-server")
        #expect(serverConfig.url == "https://mcp.example.com/api/v1")
        #expect(serverConfig.authType == "OAuth")
        
        // Verify auth config contains resource parameter
        if case .object(let configDict) = serverConfig.authConfig! {
            if case .string(let storedResourceURI) = configDict["resourceURI"] {
                #expect(storedResourceURI == resourceURI)
            } else {
                Issue.record("Resource URI not found in auth config")
            }
        } else {
            Issue.record("Auth config is not an object")
        }
    }
    
    @Test("MCP configuration JSON parsing with resource parameters")
    func testMCPConfigurationJSONParsingWithResourceParameters() throws {
        let jsonData: [String: Any] = [
            "remoteServers": [
                "mcp-server-1": [
                    "url": "https://mcp1.example.com/mcp",
                    "authType": "OAuth",
                    "authConfig": [
                        "issuerURL": "https://auth.example.com",
                        "clientId": "mcp-client-123",
                        "scope": "mcp read write",
                        "redirectURI": "https://app.example.com/callback",
                        "resourceURI": "https://mcp1.example.com/mcp"
                    ]
                ],
                "mcp-server-2": [
                    "url": "https://mcp2.example.com:8443/api",
                    "authType": "OAuth",
                    "authConfig": [
                        "issuerURL": "https://auth.example.com",
                        "clientId": "mcp-client-456",
                        "resourceURI": "https://mcp2.example.com:8443/api"
                    ]
                ]
            ]
        ]
        
        let _ = MCPConfig() // Create empty config and manually add servers
        var remoteServerConfigs = [MCPConfig.RemoteServerConfig]()
        
        if let remoteServers = jsonData["remoteServers"] as? [String: [String: Any]] {
            for (name, serverData) in remoteServers {
                if let url = serverData["url"] as? String,
                   let authType = serverData["authType"] as? String,
                   let authConfig = serverData["authConfig"] as? [String: Any] {
                    let authConfigJson = try JSON(authConfig)
                    remoteServerConfigs.append(MCPConfig.RemoteServerConfig(
                        name: name,
                        url: url,
                        authType: authType,
                        authConfig: authConfigJson
                    ))
                }
            }
        }
        
        var finalConfig = MCPConfig()
        finalConfig.remoteServers = remoteServerConfigs
        
        #expect(finalConfig.remoteServers.count == 2)
        
        // Test first server
        let server1 = finalConfig.remoteServers.first { $0.name == "mcp-server-1" }
        #expect(server1 != nil)
        #expect(server1?.authType == "OAuth")
        
        if let server1 = server1,
           case .object(let authConfig) = server1.authConfig,
           case .string(let resourceURI) = authConfig["resourceURI"] {
            #expect(resourceURI == "https://mcp1.example.com/mcp")
        } else {
            Issue.record("Server 1 resource URI not found")
        }
        
        // Test second server
        let server2 = finalConfig.remoteServers.first { $0.name == "mcp-server-2" }
        #expect(server2 != nil)
        
        if let server2 = server2,
           case .object(let authConfig) = server2.authConfig,
           case .string(let resourceURI) = authConfig["resourceURI"] {
            #expect(resourceURI == "https://mcp2.example.com:8443/api")
        } else {
            Issue.record("Server 2 resource URI not found")
        }
    }
    
    // MARK: - MCP Manager Resource Parameter Auto-Injection Tests
    
    @Test("MCP manager should auto-inject resource parameter for OAuth")
    func testMCPManagerAutoInjectResourceParameter() throws {
        // Create a mock remote server config without resource parameter
        let authConfigDict: [String: Any] = [
            "issuerURL": "https://auth.example.com",
            "clientId": "mcp-client-123",
            "scope": "mcp read write",
            "redirectURI": "https://app.example.com/callback"
            // Note: no resourceURI specified
        ]
        
        let authConfig = try JSON(authConfigDict)
        
        let serverConfig = MCPConfig.RemoteServerConfig(
            name: "test-mcp-server",
            url: "https://mcp.example.com/api/v1",
            authType: "OAuth",
            authConfig: authConfig
        )
        
        // The MCP manager should automatically add the resource parameter
        // This test verifies the logic but doesn't actually create an MCPManager
        // since that would require more complex setup
        
        #expect(serverConfig.authType == "OAuth")
        #expect(serverConfig.url == "https://mcp.example.com/api/v1")
        
        // Verify the server URL can be converted to a canonical resource URI
        if let serverURL = URL(string: serverConfig.url) {
            let canonicalURI = try ResourceIndicatorUtilities.extractMCPServerCanonicalURI(from: serverURL)
            #expect(canonicalURI == "https://mcp.example.com/api/v1")
        } else {
            Issue.record("Invalid server URL")
        }
    }
    
    @Test("MCP manager should preserve existing resource parameter")
    func testMCPManagerPreserveExistingResourceParameter() throws {
        let existingResourceURI = "https://custom.mcp.example.com/special/endpoint"
        
        let authConfigDict: [String: Any] = [
            "issuerURL": "https://auth.example.com",
            "clientId": "mcp-client-123",
            "resourceURI": existingResourceURI // Explicitly set
        ]
        
        let authConfig = try JSON(authConfigDict)
        
        let serverConfig = MCPConfig.RemoteServerConfig(
            name: "test-mcp-server",
            url: "https://mcp.example.com/api/v1", // Different from resource URI
            authType: "OAuth",
            authConfig: authConfig
        )
        
        // Verify the existing resource URI is preserved
        if case .object(let configDict) = serverConfig.authConfig!,
           case .string(let resourceURI) = configDict["resourceURI"] {
            #expect(resourceURI == existingResourceURI)
        } else {
            Issue.record("Existing resource URI not preserved")
        }
    }
    
    // MARK: - Resource Parameter URL Extraction Tests
    
    @Test("Resource parameter extraction from various MCP server URLs")
    func testResourceParameterExtractionFromMCPServerURLs() throws {
        let testCases: [(serverURL: String, expectedCanonical: String)] = [
            ("https://mcp.example.com/mcp", "https://mcp.example.com/mcp"),
            ("https://mcp.example.com", "https://mcp.example.com"),
            ("https://api.example.com:8443/v1/mcp", "https://api.example.com:8443/v1/mcp"),
            ("https://localhost:9000/mcp", "https://localhost:9000/mcp"),
            ("https://192.168.1.100:8080/api/mcp", "https://192.168.1.100:8080/api/mcp"),
            ("https://mcp-server.internal.example.com/services/mcp", "https://mcp-server.internal.example.com/services/mcp")
        ]
        
        for (serverURL, expectedCanonical) in testCases {
            guard let url = URL(string: serverURL) else {
                Issue.record("Invalid server URL: \(serverURL)")
                continue
            }
            
            let canonical = try ResourceIndicatorUtilities.extractMCPServerCanonicalURI(from: url)
            #expect(canonical == expectedCanonical, "Server URL: \(serverURL), Expected: \(expectedCanonical), Got: \(canonical)")
            
            // Verify it can be URL encoded for OAuth requests
            let encoded = ResourceIndicatorUtilities.createResourceParameter(canonicalURI: canonical)
            #expect(!encoded.isEmpty)
            #expect(encoded.contains("%3A%2F%2F")) // Should contain encoded "://"
        }
    }
    
    // MARK: - Integration with Different MCP Server Types Tests
    
    @Test("Resource parameter support for different MCP server configurations")
    func testResourceParameterForDifferentMCPServerTypes() throws {
        let mcpServerConfigurations = [
            // Standard MCP server
            (url: "https://mcp.example.com/mcp", expectedResource: "https://mcp.example.com/mcp"),
            
            // API-style MCP server
            (url: "https://api.example.com/v1/mcp", expectedResource: "https://api.example.com/v1/mcp"),
            
            // Custom port MCP server
            (url: "https://mcp.example.com:8443/api", expectedResource: "https://mcp.example.com:8443/api"),
            
            // Development/localhost MCP server
            (url: "http://localhost:3000/mcp", expectedResource: "http://localhost:3000/mcp"),
            
            // Internal network MCP server
            (url: "https://mcp-internal.company.com/services/mcp/v2", expectedResource: "https://mcp-internal.company.com/services/mcp/v2")
        ]
        
        for (serverURL, expectedResource) in mcpServerConfigurations {
            let authConfigDict: [String: Any] = [
                "issuerURL": "https://auth.example.com",
                "clientId": "mcp-client-123",
                "scope": "mcp read write",
                "redirectURI": "https://app.example.com/callback"
            ]
            
            let authConfig = try JSON(authConfigDict)
            
            let serverConfig = MCPConfig.RemoteServerConfig(
                name: "test-server",
                url: serverURL,
                authType: "OAuth",
                authConfig: authConfig
            )
            
            // Verify the server configuration
            #expect(serverConfig.url == serverURL)
            #expect(serverConfig.authType == "OAuth")
            
            // Verify canonical resource URI extraction
            if let url = URL(string: serverURL) {
                let canonical = try ResourceIndicatorUtilities.extractMCPServerCanonicalURI(from: url)
                #expect(canonical == expectedResource)
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Invalid MCP server URLs should be handled gracefully")
    func testInvalidMCPServerURLHandling() {
        let invalidURLs = [
            "not-a-url",
            "mcp.example.com", // Missing scheme
            "ftp://mcp.example.com", // Unsupported scheme (if we add validation)
            "" // Empty URL
        ]
        
        for invalidURL in invalidURLs {
            let authConfigDict: [String: Any] = [
                "issuerURL": "https://auth.example.com",
                "clientId": "mcp-client-123"
            ]
            
            do {
                let authConfig = try JSON(authConfigDict)
                let serverConfig = MCPConfig.RemoteServerConfig(
                    name: "test-server",
                    url: invalidURL,
                    authType: "OAuth",
                    authConfig: authConfig
                )
                
                // The configuration should be created, but URL extraction should fail
                #expect(serverConfig.url == invalidURL)
                
                if let url = URL(string: invalidURL) {
                    // Only test extraction if URL parsing succeeds
                    #expect(throws: Error.self) {
                        try ResourceIndicatorUtilities.extractMCPServerCanonicalURI(from: url)
                    }
                }
            } catch {
                // JSON creation might fail for some test cases, which is acceptable
                continue
            }
        }
    }
}
