//
//  ACPStreamableHTTPTransportTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import Testing
import SwiftAgentKit
@testable import SwiftAgentKitACP

@Suite("ACP Streamable HTTP Transport")
struct ACPStreamableHTTPTransportTests {

    @Test("ACP HTTP header constants match RFD")
    func httpHeaderConstants() {
        #expect(ACPHTTPHeaders.connectionId == "Acp-Connection-Id")
        #expect(ACPHTTPHeaders.sessionId == "Acp-Session-Id")
    }

    @Test("Streamable HTTP client transport can be constructed")
    func clientTransportConstruction() async {
        let url = URL(string: "https://agent.example.com/acp")!
        let transport = ACPStreamableHTTPClientTransport(endpointURL: url)
        let connectionId = await transport.connectionId()
        #expect(connectionId == nil)
    }

    @Test("HTTP bridge transport forwards ingress to agent receive stream")
    func httpBridgeIngress() async throws {
        let outbound = LockBox<[Data]>([])
        let bridge = ACPHTTPBridgeTransport { data in
            outbound.value.append(data)
        }
        try await bridge.connect()

        let payload = Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}".utf8)
        bridge.ingest(payload)

        let stream = bridge.receive()
        var received: Data?
        for try await chunk in stream {
            received = chunk
            break
        }
        #expect(received == payload)

        await bridge.disconnect()
    }
}
