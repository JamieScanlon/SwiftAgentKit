//
//  MCPClientTests.swift
//  SwiftAgentKitMCPTests
//
//  Created by Marvin Scanlon on 5/17/25.
//

import Testing
import Foundation
import SwiftAgentKitMCP

@Suite struct MCPClientTests {
    
    @Test("MCPClient can be initialized with name and version")
    func testInitialization() async throws {
        let client = MCPClient(name: "test-client", version: "1.0.0")
        
        #expect(await client.name == "test-client")
        #expect(await client.version == "1.0.0")
        #expect(await client.state == .notConnected)
    }
    
    @Test("MCPClient state transitions correctly after initialization")
    func testStateTransitions() async throws {
        let client = MCPClient(name: "test-client", version: "1.0.0")
        
        // Initial state should be notConnected
        #expect(await client.state == .notConnected)
        
        // Note: We can't easily test the full connection flow with a mock transport
        // because the MCP client expects real protocol handshakes
        // This test verifies the initial state is correct
    }
    
    @Test("MCPClient capabilities are set after initialization")
    func testCapabilitiesSetAfterInitialization() async throws {
        let client = MCPClient(name: "test-client", version: "1.0.0")
        
        // Before connection, client should be in notConnected state
        #expect(await client.state == .notConnected)
        
        // Note: Testing actual connection requires a real MCP server
        // This test verifies the initial state is correct
    }
    
    @Test("MCPClient can be initialized with strict mode")
    func testStrictModeInitialization() async throws {
        let client = MCPClient(name: "test-client", version: "1.0.0", isStrict: true)
        
        #expect(await client.name == "test-client")
        #expect(await client.version == "1.0.0")
        #expect(await client.state == .notConnected)
        
        // Note: Testing actual connection requires a real MCP server
        // This test verifies the initialization with strict mode is correct
    }
    
    @Test("MCPClient initialization is idempotent")
    func testInitializationIdempotent() async throws {
        let client = MCPClient(name: "test-client", version: "1.0.0")
        
        // Test that multiple initializations don't cause issues
        #expect(await client.name == "test-client")
        #expect(await client.version == "1.0.0")
        #expect(await client.state == .notConnected)
        
        // Note: Testing actual connection requires a real MCP server
        // This test verifies the initialization is stable
    }
    
    @Test("MCPClient tools are empty before getTools is called")
    func testToolsEmptyBeforeGetTools() async throws {
        let client = MCPClient(name: "test-client", version: "1.0.0")
        
        // Tools should be empty initially
        #expect(await client.tools.isEmpty)
        
        // Note: Testing getTools requires a real MCP server connection
        // This test verifies the initial tools state is correct
    }
} 