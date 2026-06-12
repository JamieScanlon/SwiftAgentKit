//
//  ACPClientTests.swift
//  SwiftAgentKitACPTests
//

import EasyJSON
import Foundation
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

    @Test("Connect twice throws alreadyConnected")
    func alreadyConnected() async throws {
        let (client, agent) = try await ACPTestHelpers.connectedClientAndAgent()
        defer {
            Task { await client.shutdown(); await agent.stop() }
        }

        do {
            try await client.connect(cwd: "/tmp")
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
        let transport = ACPMemoryTransport()
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
}

@Suite("ACP Client Errors")
struct ACPClientErrorTests {
    @Test("Error descriptions")
    func descriptions() {
        #expect(ACPClient.ACPClientError.alreadyConnected.errorDescription?.isEmpty == false)
        #expect(ACPClient.ACPClientError.noSession.errorDescription?.isEmpty == false)
        #expect(ACPClient.ACPClientError.bootFailed("reason").errorDescription?.contains("reason") == true)
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
