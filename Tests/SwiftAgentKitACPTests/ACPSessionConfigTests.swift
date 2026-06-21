//
//  ACPSessionConfigTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import SwiftAgentKit
import Testing
@testable import SwiftAgentKitACP

private struct ConfigurableTestACPAgentAdapter: ACPAgentAdapter {
    let agentInfo: ACPImplementation
    let agentCapabilities: ACPAgentCapabilities
    private let modeState: LockBox<ACPSessionModeState>
    private let configOptions: LockBox<[ACPSessionConfigOption]>

    init(name: String = "config-agent") {
        self.agentInfo = ACPImplementation(name: name, version: "1.0.0")
        self.agentCapabilities = ACPAgentCapabilities(
            sessionCapabilities: ACPSessionCapabilities(
                setMode: ACPCapabilityMarker(),
                setConfigOption: ACPCapabilityMarker()
            )
        )
        self.modeState = LockBox(
            ACPSessionModeState(
                currentModeId: "ask",
                availableModes: [
                    ACPSessionMode(id: "ask", name: "Ask"),
                    ACPSessionMode(id: "code", name: "Code")
                ]
            )
        )
        self.configOptions = LockBox([
            ACPSessionConfigOption(
                id: "mode",
                name: "Session Mode",
                category: "mode",
                currentValue: "ask",
                options: [
                    ACPSessionConfigSelectOption(value: "ask", name: "Ask"),
                    ACPSessionConfigSelectOption(value: "code", name: "Code")
                ]
            )
        ])
    }

    func handlePrompt(
        sessionId: String,
        prompt: [ACPContentBlock],
        client: ACPAgentClient,
        eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
    ) async throws -> ACPStopReason {
        let userText = prompt.compactMap { block -> String? in
            if case .text(let text) = block { return text }
            return nil
        }.joined(separator: " ")
        try await eventSink(.agentMessageChunk(messageId: "m1", content: .text("Reply: \(userText)")))
        return .endTurn
    }

    func sessionSetup(
        sessionId: String,
        cwd: String,
        mcpServers: [ACPMcpServer]
    ) async throws -> (configOptions: [ACPSessionConfigOption]?, mode: ACPSessionModeState?) {
        (configOptions.value, modeState.value)
    }

    func setSessionMode(sessionId: String, modeId: String) async throws -> ACPSessionModeState? {
        var mode = modeState.value
        mode.currentModeId = modeId
        modeState.value = mode
        return mode
    }

    func setSessionConfigOption(
        sessionId: String,
        configId: String,
        value: String
    ) async throws -> [ACPSessionConfigOption] {
        var options = configOptions.value
        guard let index = options.firstIndex(where: { $0.id == configId }) else {
            throw ACPAgentAdapterError.methodNotSupported("session/set_config_option")
        }
        options[index].currentValue = value
        configOptions.value = options
        return options
    }
}

@Suite("ACP Session Configuration")
struct ACPSessionConfigTests {
    @Test("Session new returns initial mode and config options")
    func sessionNewReturnsConfig() async throws {
        let adapter = ConfigurableTestACPAgentAdapter()
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: adapter, transport: agentTransport)
        let client = ACPClient(name: "config-client", transport: clientTransport)

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        let created = try await client.newSession(cwd: "/project")

        #expect(created.mode?.currentModeId == "ask")
        #expect(created.configOptions?.count == 1)
        #expect(created.configOptions?.first?.currentValue == "ask")

        _ = try await agentRun
        await client.shutdown()
        await agent.stop()
    }

    @Test("Set session mode end-to-end")
    func setSessionMode() async throws {
        let adapter = ConfigurableTestACPAgentAdapter()
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: adapter, transport: agentTransport)
        let client = ACPClient(name: "config-client", transport: clientTransport)

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        let created = try await client.newSession(cwd: "/project")

        _ = try await client.setSessionMode(sessionId: created.sessionId, modeId: "code")

        _ = try await agentRun
        await client.shutdown()
        await agent.stop()
    }

    @Test("Set session config option end-to-end")
    func setSessionConfigOption() async throws {
        let adapter = ConfigurableTestACPAgentAdapter()
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: adapter, transport: agentTransport)
        let client = ACPClient(name: "config-client", transport: clientTransport)

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        let created = try await client.newSession(cwd: "/project")

        let response = try await client.setSessionConfigOption(
            sessionId: created.sessionId,
            configId: "mode",
            value: "code"
        )
        #expect(response.configOptions.first?.currentValue == "code")

        _ = try await agentRun
        await client.shutdown()
        await agent.stop()
    }

    @Test("Unsupported set_mode returns methodNotFound")
    func setModeCapabilityGating() async throws {
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: EchoACPAgentAdapter(), transport: agentTransport)
        let rpcClient = JSONRPCConnection(transport: clientTransport)

        try await agent.run()
        defer { Task { await agent.stop() } }
        try await rpcClient.connect()

        let _: ACPInitializeResponse = try await rpcClient.call(
            "initialize",
            params: ACPInitializeRequest(protocolVersion: 1)
        )
        let session: ACPNewSessionResponse = try await rpcClient.call(
            "session/new",
            params: ACPNewSessionRequest(cwd: "/tmp")
        )

        do {
            let _: ACPSetSessionModeResponse = try await rpcClient.call(
                "session/set_mode",
                params: ACPSetSessionModeRequest(sessionId: session.sessionId, modeId: "code")
            )
            Issue.record("Expected methodNotFound")
        } catch let error as JSONRPCConnectionError {
            if case .remoteError(let rpcError) = error {
                #expect(rpcError.code == JSONRPCErrorCode.methodNotFound.rawValue)
            } else {
                Issue.record("Expected remoteError")
            }
        }

        await rpcClient.disconnect()
    }

    @Test("Client setSessionMode throws when capability unsupported")
    func clientSetModeUnsupported() async throws {
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: EchoACPAgentAdapter(), transport: agentTransport)
        let client = ACPClient(name: "config-client", transport: clientTransport)

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        let created = try await client.newSession(cwd: "/tmp")

        do {
            _ = try await client.setSessionMode(sessionId: created.sessionId, modeId: "code")
            Issue.record("Expected capabilityNotSupported")
        } catch let error as ACPClient.ACPClientError {
            if case .capabilityNotSupported(let method) = error {
                #expect(method == "session/set_mode")
            } else {
                Issue.record("Expected capabilityNotSupported")
            }
        }

        _ = try await agentRun
        await client.shutdown()
        await agent.stop()
    }
}
