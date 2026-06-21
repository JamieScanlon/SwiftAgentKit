//
//  ACPSessionLifecycleTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import SwiftAgentKit
import Testing
@testable import SwiftAgentKitACP

private struct SessionLifecycleTestAdapter: ACPAgentAdapter {
    let agentInfo: ACPImplementation
    let agentCapabilities: ACPAgentCapabilities
    private let defaultHistory: [ACPSessionUpdate]

    init(name: String = "lifecycle-agent", defaultHistory: [ACPSessionUpdate] = []) {
        self.agentInfo = ACPImplementation(name: name, version: "1.0.0")
        self.agentCapabilities = ACPAgentCapabilities(
            loadSession: true,
            sessionCapabilities: .fullLifecycle()
        )
        self.defaultHistory = defaultHistory
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

    func loadSessionHistory(
        sessionId: String,
        eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
    ) async throws {
        for update in defaultHistory {
            try await eventSink(update)
        }
    }
}

@Suite("ACP Session Lifecycle")
struct ACPSessionLifecycleTests {
    @Test("Connect initializes without creating a session")
    func connectOnly() async throws {
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: EchoACPAgentAdapter(), transport: agentTransport)
        let client = ACPClient(name: "test-client", transport: clientTransport)

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        _ = try await agentRun

        #expect(await client.state == .initialized)
        #expect(await client.sessionId == nil)

        await client.shutdown()
        await agent.stop()
    }

    @Test("List, close, and delete session lifecycle")
    func listCloseDelete() async throws {
        let adapter = SessionLifecycleTestAdapter()
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: adapter, transport: agentTransport)
        let client = ACPClient(name: "test-client", transport: clientTransport)

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        let created = try await client.newSession(cwd: "/project")
        _ = try await agentRun

        let listed = try await client.listSessions(cwd: "/project")
        #expect(listed.sessions.contains { $0.sessionId == created.sessionId })

        _ = try await client.closeSession()
        #expect(await client.state == .initialized)
        #expect(await client.sessionId == nil)

        let listedAfterClose = try await client.listSessions(cwd: "/project")
        #expect(listedAfterClose.sessions.contains { $0.sessionId == created.sessionId })

        _ = try await client.deleteSession(sessionId: created.sessionId)
        let listedAfterDelete = try await client.listSessions(cwd: "/project")
        #expect(!listedAfterDelete.sessions.contains { $0.sessionId == created.sessionId })

        await client.shutdown()
        await agent.stop()
    }

    @Test("Load session replays history")
    func loadSessionHistory() async throws {
        let history: [ACPSessionUpdate] = [
            .userMessageChunk(messageId: "u1", content: .text("prior user message")),
            .agentMessageChunk(messageId: "h1", content: .text("prior agent message"))
        ]
        let adapter = SessionLifecycleTestAdapter(defaultHistory: history)

        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: adapter, transport: agentTransport)
        let client = ACPClient(name: "test-client", transport: clientTransport)

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        let created = try await client.newSession(cwd: "/project")
        _ = try await client.closeSession()

        let (_, historyStream) = try await client.loadSession(sessionId: created.sessionId, cwd: "/project")
        var userReplayed: [String] = []
        var agentReplayed: [String] = []
        for await update in historyStream {
            switch update {
            case .userMessageChunk(_, let content):
                if case .text(let text) = content { userReplayed.append(text) }
            case .agentMessageChunk(_, let content):
                if case .text(let text) = content { agentReplayed.append(text) }
            default:
                break
            }
        }
        #expect(userReplayed.joined().contains("prior user message"))
        #expect(agentReplayed.joined().contains("prior agent message"))
        #expect(await client.sessionId == created.sessionId)
        #expect(await client.state == .sessionReady)

        await client.shutdown()
        await agent.stop()
        _ = try await agentRun
    }

    @Test("Resume session without history replay")
    func resumeSession() async throws {
        let adapter = SessionLifecycleTestAdapter()
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: adapter, transport: agentTransport)
        let client = ACPClient(name: "test-client", transport: clientTransport)

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        let created = try await client.newSession(cwd: "/project")
        _ = try await agentRun

        _ = try await client.closeSession()
        _ = try await client.resumeSession(sessionId: created.sessionId, cwd: "/project")
        #expect(await client.sessionId == created.sessionId)
        #expect(await client.state == .sessionReady)

        let text = try await client.promptCollectingText("resume check")
        #expect(text.contains("resume check"))

        await client.shutdown()
        await agent.stop()
    }

    @Test("Unsupported capability throws on client")
    func unsupportedCapability() async throws {
        let (client, agent) = try await ACPTestHelpers.connectedClientAndAgent()
        defer {
            Task { await client.shutdown(); await agent.stop() }
        }

        do {
            _ = try await client.listSessions()
            Issue.record("Expected capabilityNotSupported")
        } catch let error as ACPClient.ACPClientError {
            #expect(ACPTestHelpers.clientErrorsEqual(error, .capabilityNotSupported("session/list")))
        }
    }

    @Test("Agent rejects session/list when capability not advertised")
    func agentCapabilityGating() async throws {
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

        do {
            let _: ACPListSessionsResponse = try await rpcClient.call(
                "session/list",
                params: ACPListSessionsRequest()
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
}

@Suite("ACP Manager Session Lifecycle")
struct ACPManagerSessionLifecycleTests {
    private actor MockSessionLifecycleClient: ACPSessionLifecycleClient {
        let info: ACPImplementation
        var mockSessionId: String?
        var mockCapabilities: ACPAgentCapabilities

        init(name: String, sessionId: String? = "mock-session") {
            self.info = ACPImplementation(name: name, version: "1.0.0")
            self.mockSessionId = sessionId
            self.mockCapabilities = ACPAgentCapabilities(
                loadSession: true,
                sessionCapabilities: .fullLifecycle()
            )
        }

        var agentInfo: ACPImplementation? { info }
        var sessionId: String? { mockSessionId }
        var agentCapabilities: ACPAgentCapabilities? { mockCapabilities }
        var toolCallTimeout: TimeInterval? { nil }

        func promptStream(_ instructions: String) async throws -> (
            updates: AsyncStream<ACPSessionUpdate>,
            response: Task<ACPPromptResponse, Error>
        ) {
            let updates = AsyncStream<ACPSessionUpdate> { $0.finish() }
            let response = Task<ACPPromptResponse, Error> { ACPPromptResponse(stopReason: .endTurn) }
            return (updates, response)
        }

        func cancelPrompt() async throws {}

        var authMethods: [ACPAuthMethod] { [] }
        var isAuthenticated: Bool { true }

        func authenticate(methodId: String) async throws {}

        func logout() async throws {}

        func setSessionMode(sessionId: String, modeId: String) async throws -> ACPSetSessionModeResponse {
            ACPSetSessionModeResponse()
        }

        func setSessionConfigOption(
            sessionId: String,
            configId: String,
            value: String
        ) async throws -> ACPSetSessionConfigOptionResponse {
            ACPSetSessionConfigOptionResponse(configOptions: [])
        }

        func newSession(cwd: String, additionalRoots: [String]?) async throws -> ACPNewSessionResponse {
            mockSessionId = "new-\(cwd)"
            return ACPNewSessionResponse(sessionId: mockSessionId!)
        }

        func listSessions(cursor: String?, cwd: String?) async throws -> ACPListSessionsResponse {
            guard let mockSessionId else { return ACPListSessionsResponse(sessions: []) }
            return ACPListSessionsResponse(
                sessions: [ACPSessionInfo(sessionId: mockSessionId, cwd: cwd ?? "/tmp")]
            )
        }

        func loadSession(
            sessionId: String,
            cwd: String,
            additionalDirectories: [String]?
        ) async throws -> (response: ACPLoadSessionResponse, history: AsyncStream<ACPSessionUpdate>) {
            mockSessionId = sessionId
            let history = AsyncStream<ACPSessionUpdate> { $0.finish() }
            return (ACPLoadSessionResponse(), history)
        }

        func resumeSession(
            sessionId: String,
            cwd: String,
            additionalDirectories: [String]?
        ) async throws -> ACPResumeSessionResponse {
            mockSessionId = sessionId
            return ACPResumeSessionResponse()
        }

        func closeSession() async throws -> ACPCloseSessionResponse {
            mockSessionId = nil
            return ACPCloseSessionResponse()
        }

        func deleteSession(sessionId: String) async throws -> ACPDeleteSessionResponse {
            if mockSessionId == sessionId {
                mockSessionId = nil
            }
            return ACPDeleteSessionResponse()
        }

        func shutdown() async {}
    }

    @Test("Manager delegates session lifecycle to client")
    func managerSessionAPIs() async throws {
        let manager = ACPManager()
        let mockClient = MockSessionLifecycleClient(name: "lifecycle-agent")
        try await manager.initialize(clients: [mockClient])

        let created = try await manager.newSession(agentName: "lifecycle-agent", cwd: "/workspace")
        #expect(created.sessionId == "new-/workspace")

        let listed = try await manager.listSessions(agentName: "lifecycle-agent", cwd: "/workspace")
        #expect(listed.sessions.count == 1)

        let (_, history) = try await manager.loadSession(
            agentName: "lifecycle-agent",
            sessionId: "loaded-session",
            cwd: "/workspace"
        )
        for await _ in history {}

        _ = try await manager.resumeSession(
            agentName: "lifecycle-agent",
            sessionId: "loaded-session",
            cwd: "/workspace"
        )
        _ = try await manager.closeSession(agentName: "lifecycle-agent")
        _ = try await manager.deleteSession(agentName: "lifecycle-agent", sessionId: "loaded-session")
    }
}
