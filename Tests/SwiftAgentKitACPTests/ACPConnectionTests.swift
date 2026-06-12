//
//  ACPConnectionTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import Testing
@testable import SwiftAgentKitACP

@Suite("ACP Connection Lifecycle")
struct ACPConnectionLifecycleTests {
    @Test("Client-agent lifecycle over memory transport")
    func lifecycle() async throws {
        let (client, agent, _, _) = ACPTestHelpers.pairedClientAndAgent()
        async let runAgent: Void = try await agent.run()
        try await client.connect(cwd: "/tmp")
        let text = try await client.promptCollectingText("hello ACP")
        #expect(text.contains("Echo"))
        await client.shutdown()
        await agent.stop()
        try await runAgent
    }

    @Test("Call and response round-trip")
    func callResponse() async throws {
        let (clientTransport, agentTransport) = ACPMemoryTransport.paired()
        let server = ACPConnection(transport: agentTransport)
        let client = ACPConnection(transport: clientTransport)

        await server.registerMethod("echo") { paramsData in
            let decoder = JSONDecoder()
            let _ = try decoder.decode(ACPPromptRequest.self, from: paramsData)
            return try JSONEncoder().encode(ACPPromptResponse(stopReason: .endTurn))
        }

        try await server.connect()
        try await client.connect()

        let response: ACPPromptResponse = try await client.call(
            "echo",
            params: ACPPromptRequest(sessionId: "s1", prompt: [.text("hi")])
        )
        #expect(response.stopReason == .endTurn)

        await client.disconnect()
        await server.disconnect()
    }

    @Test("Notification delivery")
    func notificationDelivery() async throws {
        let (clientTransport, agentTransport) = ACPMemoryTransport.paired()
        let receiver = ACPConnection(transport: clientTransport)
        let sender = ACPConnection(transport: agentTransport)

        let received = LockBox(false)
        await receiver.registerNotification("session/update") { _ in
            received.value = true
        }

        try await receiver.connect()
        try await sender.connect()

        try await sender.notify(
            "session/update",
            params: ACPSessionUpdateNotification(sessionId: "s1", update: .plan(entries: []))
        )

        try await Task.sleep(for: .milliseconds(50))
        #expect(received.value == true)

        await sender.disconnect()
        await receiver.disconnect()
    }

    @Test("Method not found returns error")
    func methodNotFound() async throws {
        let (clientTransport, agentTransport) = ACPMemoryTransport.paired()
        let server = ACPConnection(transport: agentTransport)
        let client = ACPConnection(transport: clientTransport)

        try await server.connect()
        try await client.connect()

        do {
            let _: ACPPromptResponse = try await client.call(
                "missing/method",
                params: ACPPromptRequest(sessionId: "s1", prompt: [])
            )
            Issue.record("Expected remote error")
        } catch let error as ACPConnectionError {
            if case .remoteError(let rpcError) = error {
                #expect(rpcError.code == ACPErrorCode.methodNotFound.rawValue)
            } else {
                Issue.record("Expected remoteError, got \(error)")
            }
        }

        await client.disconnect()
        await server.disconnect()
    }

    @Test("Call when not connected throws")
    func notConnected() async throws {
        let transport = ACPMemoryTransport()
        let connection = ACPConnection(transport: transport)
        do {
            let _: ACPInitializeResponse = try await connection.call(
                "initialize",
                params: ACPInitializeRequest(protocolVersion: 1)
            )
            Issue.record("Expected notConnected")
        } catch let error as ACPConnectionError {
            #expect(ACPTestHelpers.connectionErrorsEqual(error, .notConnected))
        }
    }

    @Test("Mark initialized flag")
    func markInitialized() async throws {
        let transport = ACPMemoryTransport()
        let connection = ACPConnection(transport: transport)
        #expect(await connection.initialized == false)
        await connection.markInitialized()
        #expect(await connection.initialized == true)
    }
}

@Suite("ACP Memory Transport")
struct ACPMemoryTransportTests {
    @Test("Paired transports deliver messages")
    func pairedDelivery() async throws {
        let (a, b) = ACPMemoryTransport.paired()
        try await a.connect()
        try await b.connect()

        let payload = "hello".data(using: .utf8)!
        try await a.send(payload)

        let stream = b.receive()
        var received: Data?
        for try await data in stream {
            received = data
            break
        }
        #expect(received == payload)

        await a.disconnect()
        await b.disconnect()
    }

    @Test("Send without connect throws")
    func sendWithoutConnect() async throws {
        let transport = ACPMemoryTransport()
        do {
            try await transport.send(Data("x".utf8))
            Issue.record("Expected notConnected")
        } catch let error as ACPConnectionError {
            #expect(ACPTestHelpers.connectionErrorsEqual(error, .notConnected))
        }
    }
}
