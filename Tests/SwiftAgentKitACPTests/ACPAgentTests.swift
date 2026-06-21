//
//  ACPAgentTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import SwiftAgentKit
import Testing
@testable import SwiftAgentKitACP

@Suite("ACP Agent")
struct ACPAgentTests {
    @Test("Run transitions to running state")
    func run() async throws {
        let (_, agent, _, _) = ACPTestHelpers.pairedClientAndAgent()
        try await agent.run()
        #expect(await agent.state == .running)
        await agent.stop()
        #expect(await agent.state == .stopped)
    }

    @Test("Run twice throws alreadyRunning")
    func alreadyRunning() async throws {
        let (_, agent, _, _) = ACPTestHelpers.pairedClientAndAgent()
        try await agent.run()
        defer { Task { await agent.stop() } }

        do {
            try await agent.run()
            Issue.record("Expected alreadyRunning")
        } catch let error as ACPAgent.ACPAgentError {
            #expect(ACPTestHelpers.agentErrorsEqual(error, .alreadyRunning))
        }
    }

    @Test("Stop when not running is no-op")
    func stopWhenIdle() async {
        let (_, agent, _, _) = ACPTestHelpers.pairedClientAndAgent()
        await agent.stop()
        #expect(await agent.state == .idle)
    }

    @Test("Initialize returns agent capabilities")
    func initializeHandshake() async throws {
        let adapter = EchoACPAgentAdapter(name: "cap-agent", version: "3.0.0")
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: adapter, transport: agentTransport)
        let client = JSONRPCConnection(transport: clientTransport)

        try await agent.run()
        defer { Task { await agent.stop() } }
        try await client.connect()

        let response: ACPInitializeResponse = try await client.call(
            "initialize",
            params: ACPInitializeRequest(
                protocolVersion: 1,
                clientInfo: ACPImplementation(name: "test-client", version: "1.0.0")
            )
        )
        #expect(response.agentInfo?.name == "cap-agent")
        #expect(response.protocolVersion == 1)

        await client.disconnect()
    }

    @Test("Authenticate enables session creation")
    func authenticateFlow() async throws {
        struct AuthAdapter: ACPAgentAdapter {
            let agentInfo = ACPImplementation(name: "auth-agent", version: "1.0.0")
            let agentCapabilities = ACPAgentCapabilities()
            var authMethods: [ACPAuthMethod] { [ACPAuthMethod(id: "token")] }
            func handlePrompt(
                sessionId: String,
                prompt: [ACPContentBlock],
                client: ACPAgentClient,
                eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
            ) async throws -> ACPStopReason { .endTurn }
        }

        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: AuthAdapter(), transport: agentTransport)
        let client = JSONRPCConnection(transport: clientTransport)

        try await agent.run()
        defer { Task { await agent.stop() } }
        try await client.connect()

        let initResponse: ACPInitializeResponse = try await client.call(
            "initialize",
            params: ACPInitializeRequest(protocolVersion: 1)
        )
        #expect(initResponse.authMethods.count == 1)

        let _: ACPAuthenticateResponse = try await client.call(
            "authenticate",
            params: ACPAuthenticateRequest(methodId: "token")
        )

        let session: ACPNewSessionResponse = try await client.call(
            "session/new",
            params: ACPNewSessionRequest(cwd: "/tmp")
        )
        #expect(session.sessionId.isEmpty == false)

        await client.disconnect()
    }

    @Test("Session new stores mcpServers on session state")
    func sessionStoresMcpServers() async throws {
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: EchoACPAgentAdapter(), transport: agentTransport)
        let client = JSONRPCConnection(transport: clientTransport)

        try await agent.run()
        defer { Task { await agent.stop() } }
        try await client.connect()

        let _: ACPInitializeResponse = try await client.call(
            "initialize",
            params: ACPInitializeRequest(protocolVersion: 1)
        )

        let mcpServers = [
            ACPMcpServer(name: "tools", command: "mcp", arguments: ["--stdio"], environment: ["KEY": "val"])
        ]
        let session: ACPNewSessionResponse = try await client.call(
            "session/new",
            params: ACPNewSessionRequest(cwd: "/workspace", mcpServers: mcpServers)
        )

        let stored = await agent.mcpServers(forSessionId: session.sessionId)
        #expect(stored?.count == 1)
        #expect(stored?[0].name == "tools")
        #expect(stored?[0].command == "mcp")
        #expect(stored?[0].args == ["--stdio"])
        #expect(stored?[0].env?["KEY"] == "val")

        await client.disconnect()
    }

    @Test("Session not found for unknown session prompt")
    func sessionNotFound() async throws {
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: EchoACPAgentAdapter(), transport: agentTransport)
        let client = JSONRPCConnection(transport: clientTransport)

        try await agent.run()
        defer { Task { await agent.stop() } }
        try await client.connect()

        let _: ACPInitializeResponse = try await client.call(
            "initialize",
            params: ACPInitializeRequest(protocolVersion: 1)
        )
        let _: ACPNewSessionResponse = try await client.call(
            "session/new",
            params: ACPNewSessionRequest(cwd: "/tmp")
        )

        do {
            let _: ACPPromptResponse = try await client.call(
                "session/prompt",
                params: ACPPromptRequest(sessionId: "unknown-session", prompt: [.text("hi")])
            )
            Issue.record("Expected error for unknown session")
        } catch let error as JSONRPCConnectionError {
            if case .remoteError(let rpcError) = error {
                #expect(rpcError.code == ACPErrorCode.sessionNotFound.rawValue)
            } else {
                Issue.record("Expected remoteError, got \(error)")
            }
        }

        await client.disconnect()
    }

    @Test("Session new without auth throws authRequired")
    func authRequired() async throws {
        struct AuthAdapter: ACPAgentAdapter {
            let agentInfo = ACPImplementation(name: "auth-agent", version: "1.0.0")
            let agentCapabilities = ACPAgentCapabilities()
            var authMethods: [ACPAuthMethod] { [ACPAuthMethod(id: "token")] }
            func handlePrompt(
                sessionId: String,
                prompt: [ACPContentBlock],
                client: ACPAgentClient,
                eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
            ) async throws -> ACPStopReason { .endTurn }
        }

        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: AuthAdapter(), transport: agentTransport)
        let client = JSONRPCConnection(transport: clientTransport)

        try await agent.run()
        defer { Task { await agent.stop() } }
        try await client.connect()

        let _: ACPInitializeResponse = try await client.call(
            "initialize",
            params: ACPInitializeRequest(protocolVersion: 1)
        )

        do {
            let _: ACPNewSessionResponse = try await client.call(
                "session/new",
                params: ACPNewSessionRequest(cwd: "/tmp")
            )
            Issue.record("Expected authRequired")
        } catch let error as JSONRPCConnectionError {
            if case .remoteError(let rpcError) = error {
                #expect(rpcError.code == ACPErrorCode.authRequired.rawValue)
            } else {
                Issue.record("Expected remoteError")
            }
        }

        await client.disconnect()
    }

    @Test("Cancel prompt returns cancelled stop reason")
    func cancelPromptReturnsCancelled() async throws {
        struct SlowAdapter: ACPAgentAdapter {
            let agentInfo = ACPImplementation(name: "slow-agent", version: "1.0.0")
            let agentCapabilities = ACPAgentCapabilities()

            func handlePrompt(
                sessionId: String,
                prompt: [ACPContentBlock],
                client: ACPAgentClient,
                eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
            ) async throws -> ACPStopReason {
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
                return .cancelled
            }
        }

        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: SlowAdapter(), transport: agentTransport)
        let client = JSONRPCConnection(transport: clientTransport)

        try await agent.run()
        defer { Task { await agent.stop() } }
        try await client.connect()

        let _: ACPInitializeResponse = try await client.call(
            "initialize",
            params: ACPInitializeRequest(protocolVersion: 1)
        )
        let session: ACPNewSessionResponse = try await client.call(
            "session/new",
            params: ACPNewSessionRequest(cwd: "/tmp")
        )

        async let promptResponse: ACPPromptResponse = try await client.call(
            "session/prompt",
            params: ACPPromptRequest(sessionId: session.sessionId, prompt: [.text("hang")])
        )

        try await Task.sleep(nanoseconds: 50_000_000)
        try await client.notify(
            "session/cancel",
            params: ACPSessionCancelParams(sessionId: session.sessionId)
        )

        let response = try await promptResponse
        #expect(response.stopReason == .cancelled)

        await client.disconnect()
    }
}

@Suite("ACP Agent State")
struct ACPAgentStateTests {
    @Test("Stores sessions and auth flag")
    func sessionStorage() {
        let state = ACPAgentState()
        state.withLock {
            state.isAuthenticated = true
            state.sessions["s1"] = ACPAgentState.ACPSessionState(sessionId: "s1", cwd: "/tmp", mcpServers: [])
        }
        let authenticated = state.withLock { state.isAuthenticated }
        let exists = state.withLock { state.sessions["s1"] != nil }
        #expect(authenticated)
        #expect(exists)
    }
}

@Suite("ACP Agent Errors")
struct ACPAgentErrorTests {
    @Test("Error descriptions")
    func descriptions() {
        #expect(ACPAgent.ACPAgentError.alreadyRunning.errorDescription?.isEmpty == false)
        #expect(ACPAgent.ACPAgentError.notRunning.errorDescription?.isEmpty == false)
        #expect(ACPAgent.ACPAgentError.sessionNotFound("s1").errorDescription?.contains("s1") == true)
    }
}
