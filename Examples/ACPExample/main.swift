//
//  main.swift
//  ACPExample
//

import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitACP

@main
struct ACPExample {
    static func main() async throws {
        SwiftAgentKitLogging.bootstrap(logger: Logging.Logger(label: "ACPExample"))
        let logger = SwiftAgentKitLogging.logger(for: .examples("ACPExample"))
        logger.info("Starting in-process ACP client/agent demo")

        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let adapter = EchoACPAgentAdapter(name: "demo-echo-agent", responseText: "Hello from ACP")

        let agent = ACPAgent(adapter: adapter, transport: agentTransport)
        let client = ACPClient(
            name: "demo-client",
            transport: clientTransport,
            delegate: DefaultACPClientDelegate()
        )

        async let agentTask: Void = try await agent.run()
        try await client.connect()
        try await client.newSession(cwd: FileManager.default.currentDirectoryPath)

        let response = try await client.promptCollectingText("What is SwiftAgentKitACP?")
        logger.info("Agent response: \(response)")

        await client.shutdown()
        await agent.stop()
        try await agentTask
    }
}
