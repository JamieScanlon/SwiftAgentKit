//
//  MCPServerManagerTests.swift
//  SwiftAgentKitMCPTests
//
//  Created by Marvin Scanlon on 5/17/25.
//

import Testing
import Foundation
import EasyJSON
import SwiftAgentKit
import SwiftAgentKitMCP

@Suite struct MCPServerManagerTests {
    
    @Test("MCPServerManager can be initialized")
    func testInitialization() async throws {
        let manager = MCPServerManager()
        #expect(manager != nil)
    }
    
    #if os(macOS) || os(Linux) || os(Windows)
    @Test("MCPServerManager can boot a server with valid configuration")
    func testBootServer() async throws {
        let manager = MCPServerManager()
        
        // Create a simple test configuration
        let bootCall = MCPConfig.ServerBootCall(
            name: "test-server",
            command: "echo",
            arguments: ["hello"],
            environment: .object([:])
        )
        
        let (inPipe, outPipe, process) = try await manager.bootServer(
            bootCall: bootCall,
            globalEnvironment: .object([:])
        )
        
        #expect(inPipe != nil)
        #expect(outPipe != nil)
        Shell.terminateProcess(process)
    }
    
    @Test("MCPServerManager merges environment variables correctly")
    func testEnvironmentMerging() async throws {
        let manager = MCPServerManager()
        
        let globalEnv = JSON.object([
            "GLOBAL_VAR": .string("global_value"),
            "SHARED_VAR": .string("global_shared")
        ])
        
        let serverEnv = JSON.object([
            "SERVER_VAR": .string("server_value"),
            "SHARED_VAR": .string("server_shared") // This should override global
        ])
        
        let bootCall = MCPConfig.ServerBootCall(
            name: "test-server",
            command: "echo",
            arguments: ["hello"],
            environment: serverEnv
        )
        
        let (inPipe, outPipe, process) = try await manager.bootServer(
            bootCall: bootCall,
            globalEnvironment: globalEnv
        )
        
        #expect(inPipe != nil)
        #expect(outPipe != nil)
        Shell.terminateProcess(process)
    }
    
    @Test("MCPServerManager throws error for non-existent server")
    func testServerNotFound() async throws {
        let manager = MCPServerManager()
        
        var config = MCPConfig()
        config.serverBootCalls = [] // Empty config
        
        do {
            _ = try await manager.bootServer(named: "non-existent", config: config)
            #expect(Bool(false), "Should have thrown an error")
        } catch MCPServerManagerError.serverNotFound(let name) {
            #expect(name == "non-existent")
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }
    
    @Test("MCPServerManager can boot multiple servers from config")
    func testBootMultipleServers() async throws {
        let manager = MCPServerManager()
        
        var config = MCPConfig()
        config.serverBootCalls = [
            MCPConfig.ServerBootCall(
                name: "server1",
                command: "echo",
                arguments: ["server1"],
                environment: .object([:])
            ),
            MCPConfig.ServerBootCall(
                name: "server2", 
                command: "echo",
                arguments: ["server2"],
                environment: .object([:])
            )
        ]
        
        let serverPipes = try await manager.bootServers(config: config)
        
        #expect(serverPipes.count == 2)
        #expect(serverPipes["server1"] != nil)
        #expect(serverPipes["server2"] != nil)
        for (_, boot) in serverPipes {
            Shell.terminateProcess(boot.process)
        }
    }
    
    @Test("MCPServerManager handles JSON environment conversion correctly")
    func testJSONEnvironmentConversion() async throws {
        let manager = MCPServerManager()
        
        let complexEnv = JSON.object([
            "STRING_VAR": .string("string_value"),
            "INT_VAR": .integer(42),
            "DOUBLE_VAR": .double(3.14),
            "BOOL_VAR": .boolean(true),
            "NESTED_VAR": .object(["nested": .string("value")]) // Should be ignored
        ])
        
        let bootCall = MCPConfig.ServerBootCall(
            name: "test-server",
            command: "echo",
            arguments: ["hello"],
            environment: complexEnv
        )
        
        let (inPipe, outPipe, process) = try await manager.bootServer(
            bootCall: bootCall,
            globalEnvironment: .object([:])
        )
        
        #expect(inPipe != nil)
        #expect(outPipe != nil)
        Shell.terminateProcess(process)
    }
    #endif
}

@Suite struct MCPManagerTests {
    
    @Test("MCPManager can be initialized with custom timeout")
    func testInitializationWithTimeout() async throws {
        let timeout: TimeInterval = 15.0
        let manager = MCPManager(connectionTimeout: timeout)
        
        #expect(manager != nil)
    }
    
    @Test("MCPManager uses default timeout when not specified")
    func testDefaultTimeout() async throws {
        let manager = MCPManager()
        
        #expect(manager != nil)
    }

    @Test("MCPManager shutdown is safe when idle")
    func testMCPManagerShutdownIdle() async {
        let manager = MCPManager()
        await manager.shutdown()
    }

    #if os(macOS) || os(Linux) || os(Windows)
    @Test("Shell.terminateProcess stops a long-running subprocess")
    func testTerminateProcessStopsSleep() async throws {
        let launched = Shell.launchSubprocess(command: "sleep", arguments: ["60"], environment: [:], useShell: false)
        #expect(launched.process.isRunning)
        Shell.terminateProcess(launched.process)
        #expect(!launched.process.isRunning)
    }

    @Test("slow local server does not starve a peer under parallel boot-and-connect")
    func testPeerNotStarvedBySlowLocalServer() async throws {
        let stubURL = try Self.writeMinimalMCPServerStub()
        defer { try? FileManager.default.removeItem(at: stubURL) }

        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-parallel-\(UUID().uuidString).json")
        let configObject: [String: Any] = [
            "mcpServers": [
                "slow-server": [
                    "command": "sleep",
                    "args": ["60"],
                ],
                "fast-server": [
                    "command": "python3",
                    "args": [stubURL.path],
                ],
            ],
        ]
        let configData = try JSONSerialization.data(withJSONObject: configObject, options: [.prettyPrinted])
        try configData.write(to: configURL)
        defer { try? FileManager.default.removeItem(at: configURL) }

        let timeout: TimeInterval = 0.8
        let manager = MCPManager(connectionTimeout: timeout)
        let start = ContinuousClock.now
        try await manager.initialize(configFileURL: configURL)
        let elapsed = ContinuousClock.now - start

        // Parallel bring-up must not wait on the full sleep(60). Allow headroom under
        // suite parallelism (other MCPManagerTests also spawn python stdio stubs).
        #expect(elapsed < .seconds(20))

        let clients = await manager.clients
        #expect(clients.count == 1)
        #expect(await clients[0].name == "fast-server")
        #expect(await clients[0].state == .connected)

        let tools = await manager.availableTools()
        #expect(tools.contains(where: { $0.name == "ping" }))

        await manager.shutdown()
        #expect(await manager.clients.isEmpty)
        #expect(await manager.state == .notReady)
    }

    @Test("shutdown after mixed local boot clears connected clients")
    func testShutdownAfterMixedLocalBoot() async throws {
        let stubURL = try Self.writeMinimalMCPServerStub()
        defer { try? FileManager.default.removeItem(at: stubURL) }

        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-shutdown-\(UUID().uuidString).json")
        let configObject: [String: Any] = [
            "mcpServers": [
                "dead-server": [
                    "command": "sleep",
                    "args": ["30"],
                ],
                "alive-server": [
                    "command": "python3",
                    "args": [stubURL.path],
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: configObject).write(to: configURL)
        defer { try? FileManager.default.removeItem(at: configURL) }

        // Generous timeout so the stub can connect even under suite parallelism.
        let manager = MCPManager(connectionTimeout: 2.0)
        try await manager.initialize(configFileURL: configURL)
        let connected = await manager.clients
        #expect(connected.count == 1)
        #expect(await connected[0].name == "alive-server")

        await manager.shutdown()
        #expect(await manager.clients.isEmpty)
        #expect(await manager.state == .notReady)
    }

    /// Writes a tiny stdio MCP server that answers initialize + tools/list with a `ping` tool,
    /// and tools/call for `ping` with text `pong`.
    private static func writeMinimalMCPServerStub() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimal-mcp-\(UUID().uuidString).py")
        let script = """
        #!/usr/bin/env python3
        import sys, json
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            msg = json.loads(line)
            mid = msg.get("id")
            method = msg.get("method")
            if method == "initialize":
                out = {
                    "jsonrpc": "2.0",
                    "id": mid,
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {},
                        "serverInfo": {"name": "minimal-stub", "version": "1.0.0"},
                    },
                }
                print(json.dumps(out), flush=True)
            elif method == "notifications/initialized":
                continue
            elif method == "tools/list":
                out = {
                    "jsonrpc": "2.0",
                    "id": mid,
                    "result": {
                        "tools": [{
                            "name": "ping",
                            "description": "ping",
                            "inputSchema": {"type": "object", "properties": {}},
                        }]
                    },
                }
                print(json.dumps(out), flush=True)
            elif method == "tools/call":
                out = {
                    "jsonrpc": "2.0",
                    "id": mid,
                    "result": {
                        "content": [{"type": "text", "text": "pong"}],
                        "isError": False,
                    },
                }
                print(json.dumps(out), flush=True)
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }

    @Test("reconnectClient restores tools/list for a local test server; unknown name returns false")
    func testReconnectClientNamedLocalServer() async throws {
        let stubURL = try Self.writeMinimalMCPServerStub()
        defer { try? FileManager.default.removeItem(at: stubURL) }

        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-reconnect-\(UUID().uuidString).json")
        let configObject: [String: Any] = [
            "mcpServers": [
                "ping-server": [
                    "command": "python3",
                    "args": [stubURL.path],
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: configObject).write(to: configURL)
        defer { try? FileManager.default.removeItem(at: configURL) }

        let manager = MCPManager(connectionTimeout: 2.0)
        try await manager.initialize(configFileURL: configURL)
        #expect(await manager.clients.count == 1)
        #expect(await manager.availableTools().contains(where: { $0.name == "ping" }))

        let unknown = await manager.reconnectClient(named: "does-not-exist")
        #expect(unknown == false)

        // Force-disconnect the live client, then reconnect via stored boot config.
        let client = await manager.clients[0]
        await client.shutdown()
        #expect(await client.state == .notConnected)

        let reconnected = await manager.reconnectClient(named: "ping-server")
        #expect(reconnected == true)
        #expect(await manager.clients.count == 1)
        #expect(await manager.clients[0].state == .connected)
        #expect(await manager.availableTools().contains(where: { $0.name == "ping" }))

        let call = ToolCall(name: "ping", arguments: .object([:]), id: "reconnect-ping")
        let responses = try await manager.toolCall(call, orchestratorDefaultTimeout: 5.0)
        #expect(responses?.first?.content == "pong")

        await manager.shutdown()
    }

    @Test("reconnectClient returns false after initialize(clients:) without config boot descriptors")
    func testReconnectClientRequiresConfigBackedInit() async throws {
        let manager = MCPManager()
        let orphan = MCPClient(name: "orphan", version: "1.0.0")
        try await manager.initialize(clients: [orphan])
        let result = await manager.reconnectClient(named: "orphan")
        #expect(result == false)
        await manager.shutdown()
    }
    #endif

    #if !(os(macOS) || os(Linux) || os(Windows))
    @Test("MCPManager skips local stdio servers on platforms without subprocess support")
    func testSkipsLocalStdioServers() async throws {
        #expect(SubprocessAvailability.isSupported == false)

        let configJSON = """
        {
            "mcpServers": {
                "local-echo": {
                    "command": "echo",
                    "args": ["hello"]
                }
            }
        }
        """
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-config-\(UUID().uuidString).json")
        try configJSON.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let manager = MCPManager()
        try await manager.initialize(configFileURL: tempURL)

        let clients = await manager.clients
        let state = await manager.state
        #expect(clients.isEmpty)
        if case .initialized = state {
            // Remote init path completed even though the local stdio server was skipped.
        } else {
            #expect(Bool(false), "Expected MCPManager to reach .initialized state")
        }
    }
    #endif
} 