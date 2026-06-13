//
//  ACPAuthTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import SwiftAgentKit
import Testing
@testable import SwiftAgentKitACP

@Suite("ACP Auth")
struct ACPAuthTests {
    @Test("Invalid auth method returns invalidParams")
    func invalidAuthMethod() async throws {
        struct AuthAdapter: ACPAgentAdapter {
            let agentInfo = ACPImplementation(name: "auth-agent", version: "1.0.0")
            let agentCapabilities = ACPAgentCapabilities()
            var authMethods: [ACPAuthMethod] { [ACPAuthMethod(id: "token")] }
            func handlePrompt(
                sessionId: String,
                prompt: [ACPContentBlock],
                eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
            ) async throws -> ACPStopReason { .endTurn }
        }

        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: AuthAdapter(), transport: agentTransport)
        let rpcClient = JSONRPCConnection(transport: clientTransport)

        try await agent.run()
        defer { Task { await agent.stop() } }
        try await rpcClient.connect()

        let _: ACPInitializeResponse = try await rpcClient.call(
            "initialize",
            params: ACPInitializeRequest(protocolVersion: 1)
        )

        do {
            let _: ACPAuthenticateResponse = try await rpcClient.call(
                "authenticate",
                params: ACPAuthenticateRequest(methodId: "unknown")
            )
            Issue.record("Expected invalidParams")
        } catch let error as JSONRPCConnectionError {
            if case .remoteError(let rpcError) = error {
                #expect(rpcError.code == JSONRPCErrorCode.invalidParams.rawValue)
            } else {
                Issue.record("Expected remoteError")
            }
        }

        await rpcClient.disconnect()
    }

    @Test("Logout clears authentication")
    func logoutClearsAuth() async throws {
        struct LogoutAdapter: ACPAgentAdapter {
            let agentInfo = ACPImplementation(name: "logout-agent", version: "1.0.0")
            let agentCapabilities = ACPAgentCapabilities(
                auth: ACPAuthCapabilities(logout: ACPCapabilityMarker())
            )
            var authMethods: [ACPAuthMethod] { [ACPAuthMethod(id: "token")] }
            private let logoutCalled = LockBox(false)

            func handlePrompt(
                sessionId: String,
                prompt: [ACPContentBlock],
                eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
            ) async throws -> ACPStopReason { .endTurn }

            func logout() async throws {
                logoutCalled.value = true
            }
        }

        let adapter = LogoutAdapter()
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: adapter, transport: agentTransport)
        let client = ACPClient(name: "auth-client", transport: clientTransport)

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        #expect(await client.isAuthenticated)

        try await client.logout()
        #expect(await client.isAuthenticated == false)

        do {
            _ = try await client.newSession(cwd: "/tmp")
            Issue.record("Expected authRequired after logout")
        } catch let error as JSONRPCConnectionError {
            if case .remoteError(let rpcError) = error {
                #expect(rpcError.code == ACPErrorCode.authRequired.rawValue)
            } else {
                Issue.record("Expected remoteError")
            }
        }

        _ = try await agentRun
        await client.shutdown()
        await agent.stop()
    }

    @Test("Client authenticate selects method explicitly")
    func clientExplicitAuthenticate() async throws {
        struct AuthAdapter: ACPAgentAdapter {
            let agentInfo = ACPImplementation(name: "auth-agent", version: "1.0.0")
            let agentCapabilities = ACPAgentCapabilities()
            var authMethods: [ACPAuthMethod] {
                [ACPAuthMethod(id: "oauth"), ACPAuthMethod(id: "token")]
            }
            private let authenticatedMethod = LockBox<String?>(nil)

            func handlePrompt(
                sessionId: String,
                prompt: [ACPContentBlock],
                eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
            ) async throws -> ACPStopReason { .endTurn }

            func authenticate(methodId: String) async throws {
                authenticatedMethod.value = methodId
            }
        }

        let adapter = AuthAdapter()
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: adapter, transport: agentTransport)
        let client = ACPClient(name: "auth-client", transport: clientTransport)

        async let agentRun: Void = try await agent.run()
        try await client.connect(autoAuthenticate: false)
        #expect(await client.isAuthenticated == false)
        #expect(await client.authMethods.count == 2)

        try await client.authenticate(methodId: "oauth")
        #expect(await client.isAuthenticated)

        _ = try await client.newSession(cwd: "/tmp")
        _ = try await agentRun
        await client.shutdown()
        await agent.stop()
    }

    @Test("Client logout throws when capability unsupported")
    func clientLogoutUnsupported() async throws {
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let agent = ACPAgent(adapter: EchoACPAgentAdapter(), transport: agentTransport)
        let client = ACPClient(name: "auth-client", transport: clientTransport)

        async let agentRun: Void = try await agent.run()
        try await client.connect()

        do {
            try await client.logout()
            Issue.record("Expected capabilityNotSupported")
        } catch let error as ACPClient.ACPClientError {
            if case .capabilityNotSupported(let method) = error {
                #expect(method == "logout")
            } else {
                Issue.record("Expected capabilityNotSupported")
            }
        }

        _ = try await agentRun
        await client.shutdown()
        await agent.stop()
    }
}
