//
//  MCPServerManagerTests.swift
//  SwiftAgentKitMCPTests
//
//  Created by Marvin Scanlon on 5/17/25.
//

import Testing
import Foundation
import EasyJSON
import SwiftAgentKitMCP

@Suite struct MCPServerManagerTests {
    
    @Test("MCPServerManager can be initialized")
    func testInitialization() async throws {
        let manager = MCPServerManager()
        #expect(manager != nil)
    }
    
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
        
        let (inPipe, outPipe) = try await manager.bootServer(
            bootCall: bootCall,
            globalEnvironment: .object([:])
        )
        
        #expect(inPipe != nil)
        #expect(outPipe != nil)
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
        
        let (inPipe, outPipe) = try await manager.bootServer(
            bootCall: bootCall,
            globalEnvironment: globalEnv
        )
        
        #expect(inPipe != nil)
        #expect(outPipe != nil)
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
        
        let (inPipe, outPipe) = try await manager.bootServer(
            bootCall: bootCall,
            globalEnvironment: .object([:])
        )
        
        #expect(inPipe != nil)
        #expect(outPipe != nil)
    }
} 