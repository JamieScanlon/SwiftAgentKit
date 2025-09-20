//
//  MCPConfigTests.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/20/25.
//

import Testing
import Foundation
import EasyJSON
@testable import SwiftAgentKitMCP

@Suite("MCPConfig Tests")
struct MCPConfigTests {
    
    // MARK: - RemoteServerConfig Tests
    
    @Test("RemoteServerConfig should initialize with all parameters")
    func testRemoteServerConfigInitialization() async throws {
        let config = MCPConfig.RemoteServerConfig(
            name: "test-server",
            url: "https://api.example.com/mcp",
            authType: "bearer",
            authConfig: .object(["token": .string("test-token")]),
            connectionTimeout: 30.0,
            requestTimeout: 60.0,
            maxRetries: 5
        )
        
        #expect(config.name == "test-server")
        #expect(config.url == "https://api.example.com/mcp")
        #expect(config.authType == "bearer")
        #expect(config.authConfig != nil)
        #expect(config.connectionTimeout == 30.0)
        #expect(config.requestTimeout == 60.0)
        #expect(config.maxRetries == 5)
    }
    
    @Test("RemoteServerConfig should initialize with minimal parameters")
    func testRemoteServerConfigMinimal() async throws {
        let config = MCPConfig.RemoteServerConfig(
            name: "minimal-server",
            url: "https://minimal.example.com/mcp"
        )
        
        #expect(config.name == "minimal-server")
        #expect(config.url == "https://minimal.example.com/mcp")
        #expect(config.authType == nil)
        #expect(config.authConfig == nil)
        #expect(config.connectionTimeout == nil)
        #expect(config.requestTimeout == nil)
        #expect(config.maxRetries == nil)
    }
    
    // MARK: - MCPConfig Tests
    
    @Test("MCPConfig should support both local and remote servers")
    func testMCPConfigMixedServers() async throws {
        var config = MCPConfig()
        
        // Add local server
        config.serverBootCalls = [
            MCPConfig.ServerBootCall(
                name: "local-server",
                command: "echo",
                arguments: ["hello"],
                environment: .object(["KEY": .string("value")])
            )
        ]
        
        // Add remote server
        config.remoteServers = [
            MCPConfig.RemoteServerConfig(
                name: "remote-server",
                url: "https://remote.example.com/mcp",
                authType: "apikey",
                authConfig: .object(["apiKey": .string("remote-key")])
            )
        ]
        
        #expect(config.serverBootCalls.count == 1)
        #expect(config.remoteServers.count == 1)
        #expect(config.serverBootCalls[0].name == "local-server")
        #expect(config.remoteServers[0].name == "remote-server")
    }
    
    @Test("MCPConfig should initialize empty")
    func testMCPConfigEmpty() async throws {
        let config = MCPConfig()
        
        #expect(config.serverBootCalls.isEmpty)
        #expect(config.remoteServers.isEmpty)
        if case .object(let env) = config.globalEnvironment {
            #expect(env.isEmpty)
        } else {
            #expect(Bool(false), "Global environment should be an empty object")
        }
    }
    
    // MARK: - MCPConfigHelper Tests
    
    @Test("MCPConfigHelper should parse local servers only")
    func testParseLocalServersOnly() async throws {
        let configJSON = """
        {
            "mcpServers": {
                "test-server": {
                    "command": "echo",
                    "args": ["hello", "world"],
                    "env": {
                        "TEST_VAR": "test-value"
                    }
                }
            },
            "globalEnv": {
                "GLOBAL_VAR": "global-value"
            }
        }
        """
        
        let tempURL = createTempConfigFile(content: configJSON)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let config = try MCPConfigHelper.parseMCPConfig(fileURL: tempURL)
        
        #expect(config.serverBootCalls.count == 1)
        #expect(config.remoteServers.count == 0)
        #expect(config.serverBootCalls[0].name == "test-server")
        #expect(config.serverBootCalls[0].command == "echo")
        #expect(config.serverBootCalls[0].arguments == ["hello", "world"])
    }
    
    @Test("MCPConfigHelper should parse remote servers only")
    func testParseRemoteServersOnly() async throws {
        let configJSON = """
        {
            "remoteServers": {
                "api-server": {
                    "url": "https://api.example.com/mcp",
                    "authType": "bearer",
                    "authConfig": {
                        "token": "api-token"
                    },
                    "connectionTimeout": 25,
                    "requestTimeout": 50,
                    "maxRetries": 3
                },
                "simple-server": {
                    "url": "https://simple.example.com/mcp"
                }
            }
        }
        """
        
        let tempURL = createTempConfigFile(content: configJSON)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let config = try MCPConfigHelper.parseMCPConfig(fileURL: tempURL)
        
        #expect(config.serverBootCalls.count == 0)
        #expect(config.remoteServers.count == 2)
        
        let apiServer = config.remoteServers.first { $0.name == "api-server" }!
        #expect(apiServer.url == "https://api.example.com/mcp")
        #expect(apiServer.authType == "bearer")
        #expect(apiServer.authConfig != nil)
        #expect(apiServer.connectionTimeout == 25)
        #expect(apiServer.requestTimeout == 50)
        #expect(apiServer.maxRetries == 3)
        
        let simpleServer = config.remoteServers.first { $0.name == "simple-server" }!
        #expect(simpleServer.url == "https://simple.example.com/mcp")
        #expect(simpleServer.authType == nil)
        #expect(simpleServer.authConfig == nil)
    }
    
    @Test("MCPConfigHelper should parse mixed configuration")
    func testParseMixedConfiguration() async throws {
        let configJSON = """
        {
            "mcpServers": {
                "local-server": {
                    "command": "python",
                    "args": ["-m", "local_mcp_server"],
                    "env": {
                        "PYTHONPATH": "/path/to/server"
                    }
                }
            },
            "remoteServers": {
                "remote-server": {
                    "url": "https://remote.example.com/mcp",
                    "authType": "oauth",
                    "authConfig": {
                        "accessToken": "oauth-token",
                        "tokenEndpoint": "https://auth.example.com/token",
                        "clientId": "client-123"
                    }
                }
            },
            "globalEnv": {
                "LOG_LEVEL": "debug"
            }
        }
        """
        
        let tempURL = createTempConfigFile(content: configJSON)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let config = try MCPConfigHelper.parseMCPConfig(fileURL: tempURL)
        
        #expect(config.serverBootCalls.count == 1)
        #expect(config.remoteServers.count == 1)
        
        // Verify local server
        let localServer = config.serverBootCalls[0]
        #expect(localServer.name == "local-server")
        #expect(localServer.command == "python")
        #expect(localServer.arguments == ["-m", "local_mcp_server"])
        
        // Verify remote server
        let remoteServer = config.remoteServers[0]
        #expect(remoteServer.name == "remote-server")
        #expect(remoteServer.url == "https://remote.example.com/mcp")
        #expect(remoteServer.authType == "oauth")
        #expect(remoteServer.authConfig != nil)
        
        // Verify OAuth config parsing
        if case .object(let authConfigDict) = remoteServer.authConfig! {
            if case .string(let accessToken) = authConfigDict["accessToken"] {
                #expect(accessToken == "oauth-token")
            } else {
                #expect(Bool(false), "Access token should be a string")
            }
            
            if case .string(let clientId) = authConfigDict["clientId"] {
                #expect(clientId == "client-123")
            } else {
                #expect(Bool(false), "Client ID should be a string")
            }
        } else {
            #expect(Bool(false), "Auth config should be an object")
        }
    }
    
    @Test("MCPConfigHelper should handle empty configuration")
    func testParseEmptyConfiguration() async throws {
        let configJSON = "{}"
        
        let tempURL = createTempConfigFile(content: configJSON)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let config = try MCPConfigHelper.parseMCPConfig(fileURL: tempURL)
        
        #expect(config.serverBootCalls.isEmpty)
        #expect(config.remoteServers.isEmpty)
        if case .object(let env) = config.globalEnvironment {
            #expect(env.isEmpty)
        } else {
            #expect(Bool(false), "Global environment should be an empty object")
        }
    }
    
    @Test("MCPConfigHelper should handle malformed remote server configs")
    func testParseMalformedRemoteServers() async throws {
        let configJSON = """
        {
            "remoteServers": {
                "valid-server": {
                    "url": "https://valid.example.com/mcp"
                },
                "invalid-server-no-url": {
                    "authType": "bearer"
                },
                "invalid-server-bad-format": "not-an-object"
            }
        }
        """
        
        let tempURL = createTempConfigFile(content: configJSON)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let config = try MCPConfigHelper.parseMCPConfig(fileURL: tempURL)
        
        // Should only parse the valid server
        #expect(config.remoteServers.count == 1)
        #expect(config.remoteServers[0].name == "valid-server")
        #expect(config.remoteServers[0].url == "https://valid.example.com/mcp")
    }
    
    @Test("MCPConfigHelper should handle invalid JSON")
    func testParseInvalidJSON() async throws {
        let invalidJSON = "{ invalid json }"
        
        let tempURL = createTempConfigFile(content: invalidJSON)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        #expect(throws: Error.self) {
            try MCPConfigHelper.parseMCPConfig(fileURL: tempURL)
        }
    }
    
    @Test("MCPConfigHelper should handle missing file")
    func testParseMissingFile() async throws {
        let nonExistentURL = URL(fileURLWithPath: "/tmp/nonexistent-config.json")
        
        #expect(throws: Error.self) {
            try MCPConfigHelper.parseMCPConfig(fileURL: nonExistentURL)
        }
    }
    
    // MARK: - Authentication Config Tests
    
    @Test("Should parse different authentication configurations")
    func testParseAuthenticationConfigurations() async throws {
        let configJSON = """
        {
            "remoteServers": {
                "bearer-server": {
                    "url": "https://bearer.example.com/mcp",
                    "authType": "bearer",
                    "authConfig": {
                        "token": "bearer-token-123"
                    }
                },
                "apikey-server": {
                    "url": "https://apikey.example.com/mcp",
                    "authType": "apikey",
                    "authConfig": {
                        "apiKey": "api-key-456",
                        "headerName": "X-Custom-Key",
                        "prefix": "Key "
                    }
                },
                "basic-server": {
                    "url": "https://basic.example.com/mcp",
                    "authType": "basic",
                    "authConfig": {
                        "username": "test-user",
                        "password": "test-pass"
                    }
                },
                "oauth-server": {
                    "url": "https://oauth.example.com/mcp",
                    "authType": "oauth",
                    "authConfig": {
                        "accessToken": "oauth-access",
                        "refreshToken": "oauth-refresh",
                        "tokenEndpoint": "https://auth.example.com/token",
                        "clientId": "oauth-client-id",
                        "scope": "read write"
                    }
                }
            }
        }
        """
        
        let tempURL = createTempConfigFile(content: configJSON)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let config = try MCPConfigHelper.parseMCPConfig(fileURL: tempURL)
        
        #expect(config.remoteServers.count == 4)
        
        // Test each auth type
        let bearerServer = config.remoteServers.first { $0.name == "bearer-server" }!
        #expect(bearerServer.authType == "bearer")
        
        let apikeyServer = config.remoteServers.first { $0.name == "apikey-server" }!
        #expect(apikeyServer.authType == "apikey")
        
        let basicServer = config.remoteServers.first { $0.name == "basic-server" }!
        #expect(basicServer.authType == "basic")
        
        let oauthServer = config.remoteServers.first { $0.name == "oauth-server" }!
        #expect(oauthServer.authType == "oauth")
        
        // Verify auth config parsing
        if case .object(let oauthConfig) = oauthServer.authConfig! {
            if case .string(let accessToken) = oauthConfig["accessToken"] {
                #expect(accessToken == "oauth-access")
            }
            if case .string(let clientId) = oauthConfig["clientId"] {
                #expect(clientId == "oauth-client-id")
            }
        } else {
            #expect(Bool(false), "OAuth config should be parsed as object")
        }
    }
    
    // MARK: - Codable Tests
    
    @Test("MCPConfig should be encodable")
    func testMCPConfigEncodable() async throws {
        var config = MCPConfig()
        
        config.serverBootCalls = [
            MCPConfig.ServerBootCall(
                name: "test-local",
                command: "echo",
                arguments: ["test"],
                environment: .object(["KEY": .string("value")])
            )
        ]
        
        config.remoteServers = [
            MCPConfig.RemoteServerConfig(
                name: "test-remote",
                url: "https://test.example.com/mcp",
                authType: "bearer"
            )
        ]
        
        // Should be able to encode without throwing
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        #expect(data.count > 0)
        
        // Should be able to decode back
        let decoder = JSONDecoder()
        let decodedConfig = try decoder.decode(MCPConfig.self, from: data)
        
        #expect(decodedConfig.serverBootCalls.count == 1)
        #expect(decodedConfig.remoteServers.count == 1)
        #expect(decodedConfig.serverBootCalls[0].name == "test-local")
        #expect(decodedConfig.remoteServers[0].name == "test-remote")
    }
    
    // MARK: - Edge Cases
    
    @Test("Should handle complex authentication configurations")
    func testComplexAuthConfigurations() async throws {
        let configJSON = """
        {
            "remoteServers": {
                "complex-oauth": {
                    "url": "https://complex.example.com/mcp",
                    "authType": "oauth",
                    "authConfig": {
                        "accessToken": "complex-access-token",
                        "refreshToken": "complex-refresh-token",
                        "tokenEndpoint": "https://auth.complex.com/oauth/token",
                        "clientId": "complex-client-id-with-special-chars-!@#$%",
                        "clientSecret": "complex-secret-with-unicode-密码",
                        "scope": "read write admin delete",
                        "tokenType": "Bearer",
                        "expiresIn": 7200
                    },
                    "connectionTimeout": 45.5,
                    "requestTimeout": 120.75,
                    "maxRetries": 10
                }
            }
        }
        """
        
        let tempURL = createTempConfigFile(content: configJSON)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let config = try MCPConfigHelper.parseMCPConfig(fileURL: tempURL)
        
        #expect(config.remoteServers.count == 1)
        
        let complexServer = config.remoteServers[0]
        #expect(complexServer.name == "complex-oauth")
        #expect(complexServer.authType == "oauth")
        #expect(complexServer.connectionTimeout == 45.5)
        #expect(complexServer.requestTimeout == 120.75)
        #expect(complexServer.maxRetries == 10)
        
        // Verify complex auth config
        if case .object(let authConfig) = complexServer.authConfig! {
            if case .string(let clientId) = authConfig["clientId"] {
                #expect(clientId == "complex-client-id-with-special-chars-!@#$%")
            }
            if case .string(let clientSecret) = authConfig["clientSecret"] {
                #expect(clientSecret == "complex-secret-with-unicode-密码")
            }
            if case .string(let scope) = authConfig["scope"] {
                #expect(scope == "read write admin delete")
            }
            if case .integer(let expiresIn) = authConfig["expiresIn"] {
                #expect(expiresIn == 7200)
            }
        } else {
            #expect(Bool(false), "Complex auth config should be parsed correctly")
        }
    }
    
    @Test("Should handle servers with no authentication")
    func testServersWithNoAuth() async throws {
        let configJSON = """
        {
            "remoteServers": {
                "public-server": {
                    "url": "https://public.example.com/mcp",
                    "connectionTimeout": 15,
                    "maxRetries": 2
                }
            }
        }
        """
        
        let tempURL = createTempConfigFile(content: configJSON)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let config = try MCPConfigHelper.parseMCPConfig(fileURL: tempURL)
        
        #expect(config.remoteServers.count == 1)
        
        let publicServer = config.remoteServers[0]
        #expect(publicServer.name == "public-server")
        #expect(publicServer.authType == nil)
        #expect(publicServer.authConfig == nil)
        #expect(publicServer.connectionTimeout == 15)
        #expect(publicServer.maxRetries == 2)
    }
    
    // MARK: - Helper Methods
    
    private func createTempConfigFile(content: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let configURL = tempDir.appendingPathComponent("test-config-\(UUID().uuidString).json")
        
        do {
            try content.write(to: configURL, atomically: true, encoding: .utf8)
            return configURL
        } catch {
            fatalError("Failed to create temp config file: \(error)")
        }
    }
}
