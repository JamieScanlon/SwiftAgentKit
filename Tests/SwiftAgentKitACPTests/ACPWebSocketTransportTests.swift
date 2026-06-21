//
//  ACPWebSocketTransportTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import Testing
import SwiftAgentKit
@testable import SwiftAgentKitACP

@Suite("ACP WebSocket Transport")
struct ACPWebSocketTransportTests {

    @Test("Raw frame transport completes ACP initialize and prompt flow")
    func rawFrameRoundTrip() async throws {
        let (clientTransport, agentTransport) = JSONRPCRawFrameMemoryTransport.paired()
        let agent = ACPAgent(
            adapter: EchoACPAgentAdapter(name: "raw-frame-agent", responseText: "Raw frame hello"),
            transport: agentTransport
        )
        let client = ACPClient(name: "raw-frame-client", transport: clientTransport)

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        try await client.newSession(cwd: "/tmp")
        _ = try await agentRun

        let text = try await client.promptCollectingText("ping")
        #expect(text.contains("Raw frame hello") || text.contains("Echo") || text.contains("ping"))

        await client.shutdown()
        await agent.stop()
    }

    @Test("WebSocket client transport uses raw framing")
    func webSocketClientFraming() {
        let transport = ACPWebSocketClientTransport(endpointURL: URL(string: "ws://127.0.0.1:8080/acp")!)
        #expect(transport.jsonRPCFraming == .rawFrame)
    }

    @Test("ACPAgentServer configuration defaults to /acp path")
    func serverConfigurationDefaults() {
        let config = ACPAgentServer.Configuration()
        #expect(config.path == "acp")
        #expect(config.port == 8080)
    }
}
