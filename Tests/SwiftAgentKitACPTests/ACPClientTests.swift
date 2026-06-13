//
//  ACPClientTests.swift
//  SwiftAgentKitACPTests
//

import EasyJSON
import Foundation
import SwiftAgentKit
import Testing
@testable import SwiftAgentKitACP

@Suite("ACP Client")
struct ACPClientTests {
    @Test("Connect establishes session and agent info")
    func connect() async throws {
        let (client, agent) = try await ACPTestHelpers.connectedClientAndAgent()
        defer {
            Task { await client.shutdown(); await agent.stop() }
        }

        #expect(await client.state == .sessionReady)
        #expect(await client.agentInfo?.name == "test-agent")
        #expect(await client.sessionId != nil)
        #expect(await client.agentCapabilities != nil)
    }

    @Test("Connect supplies mcpServers from provider and static config")
    func connectWithMcpProvider() async throws {
        let staticServers = [ACPMcpServer(name: "config-tools", command: "cfg-mcp")]
        let dynamicServers = [ACPMcpServer(name: "runtime-tools", command: "rt-mcp", arguments: ["--stdio"])]
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: EchoACPAgentAdapter(), transport: agentTransport)
        let client = ACPClient(
            name: "test-client",
            transport: clientTransport,
            staticMcpBootServers: staticServers,
            sessionMcpServersProvider: { _ in dynamicServers }
        )

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        try await client.newSession(cwd: "/workspace")
        _ = try await agentRun

        guard let sessionId = await client.sessionId else {
            Issue.record("Missing sessionId")
            return
        }
        let stored = await agent.mcpServers(forSessionId: sessionId)
        #expect(stored?.count == 2)
        #expect(stored?[0].name == "config-tools")
        #expect(stored?[1].name == "runtime-tools")
        #expect(stored?[1].args == ["--stdio"])

        await client.shutdown()
        await agent.stop()
    }

    @Test("Connect twice throws alreadyConnected")
    func alreadyConnected() async throws {
        let (client, agent) = try await ACPTestHelpers.connectedClientAndAgent()
        defer {
            Task { await client.shutdown(); await agent.stop() }
        }

        do {
            try await client.connect()
            Issue.record("Expected alreadyConnected")
        } catch let error as ACPClient.ACPClientError {
            #expect(ACPTestHelpers.clientErrorsEqual(error, .alreadyConnected))
        }
    }

    @Test("Prompt returns stop reason and streams updates")
    func prompt() async throws {
        let (client, agent) = try await ACPTestHelpers.connectedClientAndAgent()
        defer {
            Task { await client.shutdown(); await agent.stop() }
        }

        let (response, updates) = try await client.prompt("test prompt")
        var chunks: [String] = []
        for await update in updates {
            if case .agentMessageChunk(_, let content) = update,
               case .text(let text) = content {
                chunks.append(text)
            }
        }
        #expect(response.stopReason == .endTurn)
        #expect(chunks.joined().contains("test prompt"))
        #expect(await client.state == .sessionReady)
    }

    @Test("PromptCollectingText aggregates streamed chunks")
    func promptCollectingText() async throws {
        let (client, agent) = try await ACPTestHelpers.connectedClientAndAgent()
        defer {
            Task { await client.shutdown(); await agent.stop() }
        }

        let text = try await client.promptCollectingText("collect me")
        #expect(text.contains("collect me"))
    }

    @Test("Prompt without session throws noSession")
    func promptWithoutSession() async throws {
        let transport = JSONRPCMemoryTransport()
        let client = ACPClient(name: "lonely", transport: transport)
        do {
            _ = try await client.prompt("hi")
            Issue.record("Expected noSession")
        } catch let error as ACPClient.ACPClientError {
            #expect(ACPTestHelpers.clientErrorsEqual(error, .noSession))
        }
    }

    @Test("Cancel prompt sends notification")
    func cancelPrompt() async throws {
        let (client, agent) = try await ACPTestHelpers.connectedClientAndAgent()
        defer {
            Task { await client.shutdown(); await agent.stop() }
        }

        try await client.cancelPrompt()
    }

    @Test("Shutdown resets client state")
    func shutdown() async throws {
        let (client, agent) = try await ACPTestHelpers.connectedClientAndAgent()
        await client.shutdown()
        await agent.stop()

        #expect(await client.state == .disconnected)
        #expect(await client.sessionId == nil)
        #expect(await client.agentInfo == nil)
    }

    @Test("Default connect advertises terminal capability false")
    func defaultTerminalCapabilityFalse() async throws {
        let (client, agent) = try await ACPTestHelpers.connectedClientAndAgent()
        defer {
            Task { await client.shutdown(); await agent.stop() }
        }

        let capabilities = await agent.clientCapabilitiesFromInitialize()
        #expect(capabilities?.terminal == false)
    }

    @Test("terminal/create rejected at handler gate when capability false")
    func terminalCreateRejectedWhenCapabilityFalse() async throws {
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let delegate = RecordingTerminalDelegate()
        let client = ACPClient(
            name: "test-client",
            transport: clientTransport,
            delegate: delegate
        )
        let agentConnection = JSONRPCConnection(transport: agentTransport)
        await ACPTestHelpers.registerMinimalAgentStub(on: agentConnection)

        try await agentConnection.connect()
        defer { Task { await agentConnection.disconnect(); await client.shutdown() } }

        try await client.connect()
        try await client.newSession(cwd: "/tmp")
        guard let sessionId = await client.sessionId else {
            Issue.record("Missing sessionId")
            return
        }

        do {
            let _: ACPCreateTerminalResponse = try await agentConnection.call(
                "terminal/create",
                params: ACPCreateTerminalRequest(sessionId: sessionId, command: "echo")
            )
            Issue.record("Expected methodNotFound")
        } catch let error as JSONRPCConnectionError {
            if case .remoteError(let rpcError) = error {
                #expect(rpcError.code == JSONRPCErrorCode.methodNotFound.rawValue)
            } else {
                Issue.record("Expected remoteError, got \(error)")
            }
        }

        #expect(delegate.createTerminalCallCount.value == 0)
    }

    @Test("terminal:create forwarded to delegate when capability true")
    func terminalCreateForwardedWhenCapabilityTrue() async throws {
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let delegate = RecordingTerminalDelegate(terminalId: "term-42")
        let client = ACPClient(
            name: "test-client",
            transport: clientTransport,
            delegate: delegate,
            clientCapabilities: ACPClient.defaultClientCapabilities(advertiseTerminal: true)
        )
        let agentConnection = JSONRPCConnection(transport: agentTransport)
        await ACPTestHelpers.registerMinimalAgentStub(on: agentConnection)

        try await agentConnection.connect()
        defer { Task { await agentConnection.disconnect(); await client.shutdown() } }

        try await client.connect()
        try await client.newSession(cwd: "/tmp")
        guard let sessionId = await client.sessionId else {
            Issue.record("Missing sessionId")
            return
        }

        let response: ACPCreateTerminalResponse = try await agentConnection.call(
            "terminal/create",
            params: ACPCreateTerminalRequest(sessionId: sessionId, command: "echo")
        )
        #expect(response.terminalId == "term-42")
        #expect(delegate.createTerminalCallCount.value == 1)
    }

    @Test("setDelegate swaps inbound handler target after connect")
    func setDelegateAfterConnect() async throws {
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let initialDelegate = DefaultACPClientDelegate(autoApprovePermissions: false)
        let replacementDelegate = RecordingTerminalDelegate(terminalId: "term-swapped")
        let client = ACPClient(
            name: "test-client",
            transport: clientTransport,
            delegate: initialDelegate,
            clientCapabilities: ACPClient.defaultClientCapabilities(advertiseTerminal: true)
        )
        let agentConnection = JSONRPCConnection(transport: agentTransport)
        await ACPTestHelpers.registerMinimalAgentStub(on: agentConnection)

        try await agentConnection.connect()
        defer { Task { await agentConnection.disconnect(); await client.shutdown() } }

        try await client.connect()
        try await client.newSession(cwd: "/tmp")
        await client.setDelegate(replacementDelegate)

        guard let sessionId = await client.sessionId else {
            Issue.record("Missing sessionId")
            return
        }

        let response: ACPCreateTerminalResponse = try await agentConnection.call(
            "terminal/create",
            params: ACPCreateTerminalRequest(sessionId: sessionId, command: "echo")
        )
        #expect(response.terminalId == "term-swapped")
        #expect(replacementDelegate.createTerminalCallCount.value == 1)
    }

    @Test("Per-client terminal capabilities differ")
    func perClientTerminalCapabilitiesDiffer() async throws {
        let (clientTransport1, agentTransport1) = JSONRPCMemoryTransport.paired()
        let agent1 = ACPAgent(adapter: EchoACPAgentAdapter(name: "agent-1"), transport: agentTransport1)
        let client1 = ACPClient(name: "client-1", transport: clientTransport1)

        let (clientTransport2, agentTransport2) = JSONRPCMemoryTransport.paired()
        let agent2 = ACPAgent(adapter: EchoACPAgentAdapter(name: "agent-2"), transport: agentTransport2)
        let client2 = ACPClient(
            name: "client-2",
            transport: clientTransport2,
            clientCapabilities: ACPClient.defaultClientCapabilities(advertiseTerminal: true)
        )

        async let run1: Void = try await agent1.run()
        try await client1.connect()
        try await client1.newSession(cwd: "/tmp")
        _ = try await run1

        async let run2: Void = try await agent2.run()
        try await client2.connect()
        try await client2.newSession(cwd: "/tmp")
        _ = try await run2

        #expect(await agent1.clientCapabilitiesFromInitialize()?.terminal == false)
        #expect(await agent2.clientCapabilitiesFromInitialize()?.terminal == true)

        await client1.shutdown()
        await agent1.stop()
        await client2.shutdown()
        await agent2.stop()
    }
}

@Suite("ACP Client Errors")
struct ACPClientErrorTests {
    @Test("Error descriptions")
    func descriptions() {
        #expect(ACPClient.ACPClientError.alreadyConnected.errorDescription?.isEmpty == false)
        #expect(ACPClient.ACPClientError.noSession.errorDescription?.isEmpty == false)
        #expect(ACPClient.ACPClientError.bootFailed("reason").errorDescription?.contains("reason") == true)
        #expect(ACPClient.ACPClientError.capabilityNotSupported("session/list").errorDescription?.contains("session/list") == true)
    }
}

@Suite("JSON ACP Environment")
struct JSONACPEnvironmentTests {
    @Test("Extracts string environment values")
    func acpEnvironment() {
        let json: JSON = .object([
            "API_KEY": .string("secret"),
            "COUNT": .integer(3),
            "nested": .object(["x": .string("y")])
        ])
        let env = json.acpEnvironment
        #expect(env["API_KEY"] == "secret")
        #expect(env["COUNT"] == nil)
        #expect(env["nested"] == nil)
    }

    @Test("Non-object JSON yields empty environment")
    func nonObject() {
        #expect(JSON.string("x").acpEnvironment.isEmpty)
    }
}
