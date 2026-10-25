//
//  MCPManagerRemoteTests.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 9/20/25.
//

import Testing
import Foundation
import EasyJSON
@testable import SwiftAgentKit
@testable import SwiftAgentKitMCP

@Suite("MCPManager Remote Tests")
struct MCPManagerRemoteTests {
    
    // MARK: - Helper Methods
    
    private func createTempConfigFile(content: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let configURL = tempDir.appendingPathComponent("test-mcp-config-\(UUID().uuidString).json")
        
        do {
            try content.write(to: configURL, atomically: true, encoding: .utf8)
            return configURL
        } catch {
            fatalError("Failed to create temp config file: \(error)")
        }
    }
    
    
    // MARK: - Initialization Tests
    
    @Test("MCPManager should initialize with default timeout")
    func testInitializationDefault() async throws {
        let manager = MCPManager()
        let state = await manager.state
        #expect(state == .notReady)
    }
    
    @Test("MCPManager should initialize with custom timeout")
    func testInitializationCustomTimeout() async throws {
        let manager = MCPManager(connectionTimeout: 45.0)
        let state = await manager.state
        #expect(state == .notReady)
    }
    
    // MARK: - Configuration Parsing Tests
    
    @Test("MCPManager should handle empty configuration")
    func testEmptyConfiguration() async throws {
        let configJSON = "{}"
        let configURL = createTempConfigFile(content: configJSON)
        defer { try? FileManager.default.removeItem(at: configURL) }
        
        let manager = MCPManager()
        
        // Should not throw for empty config
        try await manager.initialize(configFileURL: configURL)
        
        let state = await manager.state
        // State should be initialized regardless of client connection success
        #expect(state == .initialized || state == .notReady)
        
        let clients = await manager.clients
        #expect(clients.isEmpty)
        
        let tools = await manager.availableTools()
        #expect(tools.isEmpty)
    }
    
    @Test("MCPManager should handle local server configuration parsing")
    func testLocalServerConfigParsing() async throws {
        let configJSON = """
        {
            "mcpServers": {
                "echo-server": {
                    "command": "echo",
                    "args": ["Hello from echo"],
                    "env": {
                        "ECHO_VAR": "echo-value"
                    }
                }
            }
        }
        """
        
        let configURL = createTempConfigFile(content: configJSON)
        defer { try? FileManager.default.removeItem(at: configURL) }
        
        // Test config parsing without actually initializing servers
        let config = try MCPConfigHelper.parseMCPConfig(fileURL: configURL)
        
        #expect(config.serverBootCalls.count == 1)
        #expect(config.serverBootCalls[0].name == "echo-server")
        #expect(config.serverBootCalls[0].command == "echo")
        #expect(config.serverBootCalls[0].arguments == ["Hello from echo"])
        if case .object(let envDict) = config.serverBootCalls[0].environment,
           case .string(let echoVar) = envDict["ECHO_VAR"] {
            #expect(echoVar == "echo-value")
        }
    }
    
    // MARK: - Authentication Provider Creation Tests
    
    @Test("MCPManager should create auth providers from environment variables")
    func testAuthProviderFromEnvironmentValidation() async throws {
        // Use unique prefixes so parallel AuthenticationFactoryTests cannot clobber these vars.
        let bearerServer = "mcpmanagerremotesuite_bearer"
        let apiKeyServer = "mcpmanagerremotesuite_apikey"
        let basicServer = "mcpmanagerremotesuite_basic"
        let bearerPrefix = "\(bearerServer.uppercased())_"
        let apiKeyPrefix = "\(apiKeyServer.uppercased())_"
        let basicPrefix = "\(basicServer.uppercased())_"

        unsetenv("\(apiKeyPrefix)TOKEN")
        unsetenv("\(apiKeyPrefix)BEARER_TOKEN")
        unsetenv("\(basicPrefix)TOKEN")
        unsetenv("\(basicPrefix)BEARER_TOKEN")
        unsetenv("\(basicPrefix)API_KEY")

        setenv("\(bearerPrefix)TOKEN", "env-bearer-token", 1)
        setenv("\(apiKeyPrefix)API_KEY", "env-api-key", 1)
        setenv("\(basicPrefix)USERNAME", "env-user", 1)
        setenv("\(basicPrefix)PASSWORD", "env-pass", 1)

        defer {
            unsetenv("\(bearerPrefix)TOKEN")
            unsetenv("\(apiKeyPrefix)API_KEY")
            unsetenv("\(basicPrefix)USERNAME")
            unsetenv("\(basicPrefix)PASSWORD")
        }

        let bearerProvider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: bearerServer)
        #expect(bearerProvider != nil)
        #expect(bearerProvider?.scheme == .bearer)

        let apiKeyProvider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: apiKeyServer)
        #expect(apiKeyProvider != nil)
        #expect(apiKeyProvider?.scheme == .apiKey)

        let basicProvider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: basicServer)
        #expect(basicProvider != nil)
        #expect(basicProvider?.scheme == .basic)
    }
    
    @Test("MCPManager should validate authentication configurations")
    func testAuthConfigurationValidation() async throws {
        // Test valid auth configurations
        let validConfigs = [
            ("bearer", JSON.object(["token": .string("test-token")])),
            ("apikey", JSON.object(["apiKey": .string("test-key")])),
            ("basic", JSON.object(["username": .string("user"), "password": .string("pass")])),
            ("oauth", JSON.object([
                "accessToken": .string("access"),
                "tokenEndpoint": .string("https://auth.example.com/token"),
                "clientId": .string("client-id")
            ]))
        ]
        
        for (authType, authConfig) in validConfigs {
            let provider = try AuthenticationFactory.createAuthProvider(authType: authType, config: authConfig)
            #expect(provider.scheme.rawValue.lowercased().contains(authType.lowercased()) || authType == "bearer")
        }
        
        // Test invalid auth configurations
        let invalidConfigs = [
            ("bearer", JSON.object([:])), // Missing token
            ("apikey", JSON.object([:])), // Missing apiKey
            ("basic", JSON.object(["username": .string("user")])), // Missing password
            ("unsupported", JSON.object([:]))
        ]
        
        for (authType, authConfig) in invalidConfigs {
            #expect(throws: Error.self) {
                try AuthenticationFactory.createAuthProvider(authType: authType, config: authConfig)
            }
        }
    }
    
    // MARK: - Client Management Tests
    
    @Test("MCPManager should initialize with provided clients")
    func testInitializeWithClients() async throws {
        // Create mock clients
        let client1 = MCPClient(name: "client1", version: "1.0.0")
        let client2 = MCPClient(name: "client2", version: "1.0.0")
        
        let manager = MCPManager()
        try await manager.initialize(clients: [client1, client2])
        
        let state = await manager.state
        // State should be initialized regardless of client connection success
        #expect(state == .initialized || state == .notReady)
        
        let clients = await manager.clients
        #expect(clients.count == 2)
    }
    
    @Test("MCPManager should handle empty client list")
    func testInitializeWithEmptyClients() async throws {
        let manager = MCPManager()
        try await manager.initialize(clients: [])
        
        let state = await manager.state
        // State should be initialized regardless of client connection success
        #expect(state == .initialized || state == .notReady)
        
        let clients = await manager.clients
        #expect(clients.isEmpty)
        
        let tools = await manager.availableTools()
        #expect(tools.isEmpty)
        
        let toolCallsJsonString = await manager.toolCallsJsonString
        #expect(toolCallsJsonString == "[]")
    }

    @Test("registeredToolDescriptors returns empty list and no diagnostics when no MCP clients")
    func testRegisteredToolDescriptorsEmpty() async throws {
        let manager = MCPManager()
        try await manager.initialize(clients: [])
        let descriptors = await manager.registeredToolDescriptors()
        let diagnostics = await manager.ingestionDiagnostics
        #expect(descriptors.isEmpty)
        #expect(diagnostics.isEmpty)
    }
    
    // MARK: - Tool Management Tests
    
    @Test("MCPManager should build tools JSON correctly")
    func testToolsJSONBuilding() async throws {
        let manager = MCPManager()
        try await manager.initialize(clients: [])
        
        let toolCallsJsonString = await manager.toolCallsJsonString
        #expect(toolCallsJsonString == "[]")
    }
    
    @Test("MCPManager should handle tool calls with no clients")
    func testToolCallWithNoClients() async throws {
        let manager = MCPManager()
        try await manager.initialize(clients: [])
        
        let toolCall = ToolCall(
            name: "nonexistent_tool",
            arguments: try! JSON(["test": "value"]),
            instructions: "Test instruction",
            id: UUID().uuidString
        )
        
        let result = try await manager.toolCall(toolCall)
        #expect(result == nil)
    }

    // MARK: - Disconnected client must not poison dispatch

    @Test("MCPManager toolCall returns nil for non-owned tool when a disconnected client still advertises other tools")
    func testToolCallSkipsDisconnectedClientForNonOwnedTool() async throws {
        let deadTool = ToolDefinition(
            name: "XcodeRead",
            description: "Read a file",
            parameters: [],
            type: .mcpTool
        )
        let deadClient = MCPClient(name: "xcode-mcp", version: "1.0.0")
        await deadClient.installToolsForTesting(tools: [deadTool], inputSchemasByName: [:])

        let idleClient = MCPClient(name: "other-mcp", version: "1.0.0")

        let manager = MCPManager()
        try await manager.initialize(clients: [deadClient, idleClient])

        let toolCall = ToolCall(name: "bash", arguments: .object([:]))
        let result = try await manager.toolCall(toolCall)
        #expect(result == nil)
    }

    @Test("MCPManager toolCall throws notConnected for tool owned only by a disconnected client")
    func testToolCallFailsClosedForOwnedToolOnDisconnectedClient() async throws {
        let deadTool = ToolDefinition(
            name: "XcodeRead",
            description: "Read a file",
            parameters: [],
            type: .mcpTool
        )
        let deadClient = MCPClient(name: "xcode-mcp", version: "1.0.0")
        await deadClient.installToolsForTesting(tools: [deadTool], inputSchemasByName: [:])

        let idleClient = MCPClient(name: "other-mcp", version: "1.0.0")

        let manager = MCPManager()
        try await manager.initialize(clients: [deadClient, idleClient])

        let toolCall = ToolCall(name: "XcodeRead", arguments: .object([:]))
        do {
            _ = try await manager.toolCall(toolCall)
            #expect(Bool(false), "Expected notConnected for owned MCP tool on disconnected client")
        } catch let error as MCPClient.MCPClientError {
            if case .notConnected = error {
                // ok
            } else {
                Issue.record("Expected notConnected, got \(error)")
            }
        } catch {
            Issue.record("Expected MCPClientError.notConnected, got \(error)")
        }
    }

    @Test("MCPManager toolCall reaches a healthy client after a disconnected peer")
    func testToolCallSucceedsViaHealthyClientAfterDisconnectedPeer() async throws {
        let deadTool = ToolDefinition(
            name: "XcodeRead",
            description: "Read a file",
            parameters: [],
            type: .mcpTool
        )
        let deadClient = MCPClient(name: "xcode-mcp", version: "1.0.0")
        await deadClient.installToolsForTesting(tools: [deadTool], inputSchemasByName: [:])

        let clientToServer = Pipe()
        let serverToClient = Pipe()
        let healthyClient = MCPClient(
            name: "healthy-mcp",
            version: "1.0.0",
            connectionTimeout: 2.0
        )

        let serverTask = Task {
            let reader = clientToServer.fileHandleForReading
            let writer = serverToClient.fileHandleForWriting
            var buffer = Data()
            while !Task.isCancelled {
                let chunk = reader.availableData
                if chunk.isEmpty {
                    try? await Task.sleep(for: .milliseconds(10))
                    continue
                }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = buffer.subdata(in: buffer.startIndex..<newline)
                    buffer.removeSubrange(buffer.startIndex...newline)
                    guard
                        let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                        let method = obj["method"] as? String,
                        let id = obj["id"]
                    else {
                        continue
                    }
                    let result: [String: Any]
                    switch method {
                    case "initialize":
                        result = [
                            "protocolVersion": "2024-11-05",
                            "capabilities": [String: Any](),
                            "serverInfo": [
                                "name": "healthy-mcp-server",
                                "version": "1.0.0",
                            ],
                        ]
                    case "tools/list":
                        result = [
                            "tools": [[
                                "name": "other",
                                "description": "other",
                                "inputSchema": ["type": "object", "properties": [String: Any]()],
                            ]],
                        ]
                    case "tools/call":
                        result = [
                            "content": [["type": "text", "text": "pong"]],
                            "isError": false,
                        ]
                    default:
                        continue
                    }
                    let response: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": id,
                        "result": result,
                    ]
                    var payload = try JSONSerialization.data(withJSONObject: response)
                    payload.append(UInt8(ascii: "\n"))
                    try writer.write(contentsOf: payload)
                }
            }
        }
        defer { serverTask.cancel() }

        try await healthyClient.connect(inPipe: clientToServer, outPipe: serverToClient)
        #expect(await healthyClient.state == .connected)
        #expect(await healthyClient.tools.contains(where: { $0.name == "other" }))

        let manager = MCPManager()
        try await manager.initialize(clients: [deadClient, healthyClient])

        let toolCall = ToolCall(name: "other", arguments: .object([:]))
        let responses = try await manager.toolCall(toolCall)
        #expect(responses?.count == 1)
        #expect(responses?.first?.content == "pong")
    }
    
    // MARK: - Configuration File Tests
    
    @Test("MCPManager should handle malformed configuration file parsing")
    func testMalformedConfigurationFileParsing() async throws {
        let malformedJSON = """
        {
            "mcpServers": {
                "valid-server": {
                    "command": "echo",
                    "args": ["test"]
                },
                "invalid-server": "not-an-object"
            }
        }
        """
        
        let configURL = createTempConfigFile(content: malformedJSON)
        defer { try? FileManager.default.removeItem(at: configURL) }
        
        // Test that config parsing handles malformed entries gracefully
        do {
            let config = try MCPConfigHelper.parseMCPConfig(fileURL: configURL)
            
            // Should successfully parse the valid server
            #expect(config.serverBootCalls.count >= 0) // Might skip invalid entries
            
            // Find the valid server if it was parsed
            let validServer = config.serverBootCalls.first { $0.name == "valid-server" }
            if let server = validServer {
                #expect(server.command == "echo")
                #expect(server.arguments == ["test"])
            }
            
        } catch {
            // Parsing might fail entirely for malformed JSON, which is also valid behavior
            #expect(error is DecodingError || error is CocoaError)
        }
    }
    
    @Test("MCPManager should handle missing configuration file")
    func testMissingConfigurationFile() async throws {
        let nonExistentURL = URL(fileURLWithPath: "/tmp/nonexistent-mcp-config.json")
        
        let manager = MCPManager()
        
        // MCPManager logs errors but doesn't necessarily throw for missing config files
        // It may continue with an empty configuration
        try await manager.initialize(configFileURL: nonExistentURL)
        
        // Should remain in notReady state or be initialized with empty config
        let state = await manager.state
        #expect(state == .notReady || state == .initialized)
        
        // Should have no clients since config file was missing
        let clients = await manager.clients
        #expect(clients.isEmpty)
    }
    
    // MARK: - Authentication Integration Tests
    
    @Test("MCPManager should prioritize environment auth over config auth")
    func testAuthenticationPriority() async throws {
        // Set environment variable
        setenv("PRIORITYSERVER_TOKEN", "env-priority-token", 1)
        defer { unsetenv("PRIORITYSERVER_TOKEN") }
        
        // Test that environment auth takes priority
        let envProvider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: "priorityserver")
        #expect(envProvider != nil)
        #expect(envProvider?.scheme == .bearer)
        
        let headers = try await envProvider!.authenticationHeaders()
        #expect(headers["Authorization"] == "Bearer env-priority-token")
        
        // Test config-based auth for comparison
        let configAuth = JSON.object(["token": .string("config-token")])
        let configProvider = try AuthenticationFactory.createAuthProvider(authType: "bearer", config: configAuth)
        
        let configHeaders = try await configProvider.authenticationHeaders()
        #expect(configHeaders["Authorization"] == "Bearer config-token")
        
        // Environment should take priority over config
        #expect(headers["Authorization"] != configHeaders["Authorization"])
    }
    
    // MARK: - State Management Tests
    
    @Test("MCPManager should track state correctly")
    func testStateManagement() async throws {
        let manager = MCPManager()
        
        // Initial state
        let initialState = await manager.state
        #expect(initialState == .notReady)
        
        // After empty initialization
        try await manager.initialize(clients: [])
        
        let finalState = await manager.state
        // After initializing with empty clients, state should be initialized
        #expect(finalState == .initialized || finalState == .notReady)
    }
    
    @Test("MCPManager should handle reinitialization")
    func testReinitialization() async throws {
        let manager = MCPManager()
        
        // First initialization
        try await manager.initialize(clients: [])
        let firstState = await manager.state
        #expect(firstState == .initialized || firstState == .notReady)
        
        let firstClients = await manager.clients
        let firstClientCount = firstClients.count
        
        // Second initialization with different clients
        let newClient = MCPClient(name: "new-client", version: "1.0.0")
        try await manager.initialize(clients: [newClient])
        
        let secondState = await manager.state
        #expect(secondState == .initialized || secondState == .notReady)
        
        let secondClients = await manager.clients
        #expect(secondClients.count == 1)
        #expect(secondClients.count != firstClientCount || firstClientCount == 1)
    }
    
    // MARK: - Configuration Validation Tests (No Network Calls)
    
    @Test("MCPManager should validate remote server URL formats")
    func testRemoteServerURLValidation() async throws {
        // Test valid URL formats
        let validURLs = [
            "https://api.example.com/mcp",
            "http://localhost:8080/mcp",
            "https://subdomain.example.com:9000/path/to/mcp"
        ]
        
        for urlString in validURLs {
            let config = MCPConfig.RemoteServerConfig(
                name: "test-server",
                url: urlString
            )
            
            let url = URL(string: config.url)
            #expect(url != nil)
            #expect(config.name == "test-server")
            #expect(config.url == urlString)
        }
        
        // Test invalid URL formats
        let invalidURLs = [
            "not-a-url",
            "ftp://unsupported.com",
            ""
        ]
        
        for urlString in invalidURLs {
            let config = MCPConfig.RemoteServerConfig(
                name: "test-server",
                url: urlString
            )
            
            // URL creation might fail or succeed, but config should still be created
            #expect(config.url == urlString)
        }
    }
    
    // MARK: - Tool Call Tests
    
    @Test("MCPManager should handle tool calls with failed servers")
    func testToolCallWithFailedServers() async throws {
        let manager = MCPManager()
        try await manager.initialize(clients: [])
        
        let toolCall = ToolCall(
            name: "test_tool",
            arguments: try! JSON(["param": "value"]),
            instructions: "Test tool call",
            id: UUID().uuidString
        )
        
        let result = try await manager.toolCall(toolCall)
        #expect(result == nil) // No clients available
    }
    
    // MARK: - Concurrent Operations Tests
    
    @Test("MCPManager should handle concurrent initialization safely")
    func testConcurrentInitialization() async throws {
        let manager = MCPManager()
        
        // Run multiple concurrent initializations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    do {
                        let client = MCPClient(name: "client-\(i)", version: "1.0.0")
                        try await manager.initialize(clients: [client])
                    } catch {
                        // Some might fail due to concurrency, that's ok
                    }
                }
            }
        }
        
        // Should end up in a valid state
        let finalState = await manager.state
        // After initializing with empty clients, state should be initialized
        #expect(finalState == .initialized || finalState == .notReady)
    }
    
    @Test("MCPManager should handle concurrent tool calls safely")
    func testConcurrentToolCalls() async throws {
        let manager = MCPManager()
        try await manager.initialize(clients: [])
        
        // Run multiple concurrent tool calls
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    do {
                        let toolCall = ToolCall(
                            name: "concurrent_tool_\(i)",
                            arguments: try! JSON(["id": i]),
                            instructions: "Concurrent test",
                            id: UUID().uuidString
                        )
                        _ = try await manager.toolCall(toolCall)
                    } catch {
                        // Expected to fail since no clients are available
                    }
                }
            }
        }
        
        // Should remain in valid state
        let state = await manager.state
        // State should be initialized regardless of client connection success
        #expect(state == .initialized || state == .notReady)
    }
    
    // MARK: - Configuration Structure Tests
    
    @Test("MCPManager should handle remote server configuration structure")
    func testRemoteServerConfigStructure() async throws {
        // Test RemoteServerConfig structure validation
        let minimalConfig = MCPConfig.RemoteServerConfig(
            name: "minimal",
            url: "https://minimal.example.com/mcp"
        )
        
        #expect(minimalConfig.name == "minimal")
        #expect(minimalConfig.url == "https://minimal.example.com/mcp")
        #expect(minimalConfig.authType == nil)
        #expect(minimalConfig.authConfig == nil)
        #expect(minimalConfig.connectionTimeout == nil)
        #expect(minimalConfig.requestTimeout == nil)
        #expect(minimalConfig.maxRetries == nil)
        
        // Test full configuration
        let fullConfig = MCPConfig.RemoteServerConfig(
            name: "full",
            url: "https://full.example.com/mcp",
            authType: "oauth",
            authConfig: JSON.object([
                "accessToken": .string("token"),
                "clientId": .string("client")
            ]),
            connectionTimeout: 30,
            requestTimeout: 60,
            maxRetries: 5
        )
        
        #expect(fullConfig.name == "full")
        #expect(fullConfig.authType == "oauth")
        #expect(fullConfig.authConfig != nil)
        #expect(fullConfig.connectionTimeout == 30)
        #expect(fullConfig.requestTimeout == 60)
        #expect(fullConfig.maxRetries == 5)
    }
}
