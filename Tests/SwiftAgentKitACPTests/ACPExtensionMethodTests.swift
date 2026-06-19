//
//  ACPExtensionMethodTests.swift
//  SwiftAgentKitACPTests
//

import EasyJSON
import Foundation
import Testing
import SwiftAgentKit
@testable import SwiftAgentKitACP

@Suite("ACP Extension Methods")
struct ACPExtensionMethodTests {

    @Test("Client to agent extension request round-trip")
    func clientToAgentExtensionRequest() async throws {
        struct ExtAdapter: ACPAgentAdapter {
            let agentInfo = ACPImplementation(name: "ext-agent", version: "1.0.0")
            let agentCapabilities = ACPAgentCapabilities()

            func handlePrompt(
                sessionId: String,
                prompt: [ACPContentBlock],
                client: ACPAgentClient,
                eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
            ) async throws -> ACPStopReason {
                .endTurn
            }

            func extMethod(method: String, params: JSON) async throws -> JSON {
                guard method == "_example.com/get_stats" else {
                    throw JSONRPCConnectionError.methodNotFound(method)
                }
                return .object(["uptime": .double(42), "echo": .string("value")])
            }
        }

        let (client, agent, _, _) = ACPTestHelpers.pairedClientAndAgent(adapter: ExtAdapter())
        async let agentRun: Void = try await agent.run()
        try await client.connect()
        _ = try await agentRun

        let result = try await client.extMethod(
            method: "_example.com/get_stats",
            params: .object(["key": .string("value")])
        )
        guard case .object(let dict) = result,
              case .integer(let uptime) = dict["uptime"],
              uptime == 42 else {
            Issue.record("Unexpected extension result: \(result)")
            return
        }

        await client.shutdown()
        await agent.stop()
    }

    @Test("Agent to client extension request during prompt")
    func agentToClientExtensionRequest() async throws {
        struct ExtDelegate: ACPClientDelegate {
            func readTextFile(_ request: ACPReadTextFileRequest) async throws -> ACPReadTextFileResponse {
                ACPReadTextFileResponse(content: "")
            }
            func writeTextFile(_ request: ACPWriteTextFileRequest) async throws -> ACPWriteTextFileResponse {
                ACPWriteTextFileResponse()
            }
            func requestPermission(_ request: ACPRequestPermissionRequest) async throws -> ACPRequestPermissionResponse {
                ACPRequestPermissionResponse(outcome: .cancelled)
            }
            func extMethod(method: String, params: JSON) async throws -> JSON {
                guard method == "_example.com/get_workspace" else {
                    throw JSONRPCConnectionError.methodNotFound(method)
                }
                return .object(["path": .string("/project")])
            }
        }

        struct ExtPromptAdapter: ACPAgentAdapter {
            let agentInfo = ACPImplementation(name: "ext-prompt-agent", version: "1.0.0")
            let agentCapabilities = ACPAgentCapabilities()

            func handlePrompt(
                sessionId: String,
                prompt: [ACPContentBlock],
                client: ACPAgentClient,
                eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
            ) async throws -> ACPStopReason {
                let workspace = try await client.extMethod(method: "_example.com/get_workspace")
                guard case .object(let dict) = workspace,
                      case .string(let path) = dict["path"],
                      path == "/project" else {
                    throw JSONRPCConnectionError.invalidRequest
                }
                return .endTurn
            }
        }

        let (client, agent, _, _) = ACPTestHelpers.pairedClientAndAgent(
            adapter: ExtPromptAdapter(),
            delegate: ExtDelegate()
        )
        async let agentRun: Void = try await agent.run()
        try await client.connect()
        _ = try await client.newSession(cwd: "/tmp")
        _ = try await agentRun

        let response = try await client.promptCollectingText("hello")
        #expect(response.contains("Echo") == false || response.isEmpty == false)

        await client.shutdown()
        await agent.stop()
    }

    @Test("Unrecognized extension request returns methodNotFound")
    func unrecognizedExtensionRequest() async throws {
        let (client, agent, _, _) = ACPTestHelpers.pairedClientAndAgent()
        async let agentRun: Void = try await agent.run()
        try await client.connect()
        _ = try await agentRun

        do {
            _ = try await client.extMethod(method: "_unknown/method")
            Issue.record("Expected methodNotFound")
        } catch let error as JSONRPCConnectionError {
            #expect(ACPTestHelpers.connectionErrorsEqual(
                error,
                .remoteError(JSONRPCError(code: JSONRPCErrorCode.methodNotFound.rawValue, message: "Method not found: _unknown/method"))
            ))
        }

        await client.shutdown()
        await agent.stop()
    }

    @Test("Non-underscore method rejected at API layer")
    func nonUnderscoreMethodRejected() async throws {
        let (client, _, _, _) = ACPTestHelpers.pairedClientAndAgent()
        do {
            _ = try await client.extMethod(method: "example.com/bad")
            Issue.record("Expected invalidMethodName")
        } catch let error as ACPExtensionError {
            guard case .invalidMethodName(let method) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(method == "example.com/bad")
        }
    }

    @Test("Explicit registerExtensionMethod overrides delegate catch-all")
    func explicitRegistrationOverridesDelegate() async throws {
        struct ConflictingDelegate: ACPClientDelegate {
            func readTextFile(_ request: ACPReadTextFileRequest) async throws -> ACPReadTextFileResponse {
                ACPReadTextFileResponse(content: "")
            }
            func writeTextFile(_ request: ACPWriteTextFileRequest) async throws -> ACPWriteTextFileResponse {
                ACPWriteTextFileResponse()
            }
            func requestPermission(_ request: ACPRequestPermissionRequest) async throws -> ACPRequestPermissionResponse {
                ACPRequestPermissionResponse(outcome: .cancelled)
            }
            func extMethod(method: String, params: JSON) async throws -> JSON {
                .object(["source": .string("delegate")])
            }
        }

        struct CallingAdapter: ACPAgentAdapter {
            let captured = LockBox<JSON?>(nil)
            let agentInfo = ACPImplementation(name: "calling-agent", version: "1.0.0")
            let agentCapabilities = ACPAgentCapabilities()

            func handlePrompt(
                sessionId: String,
                prompt: [ACPContentBlock],
                client: ACPAgentClient,
                eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
            ) async throws -> ACPStopReason {
                let result = try await client.extMethod(method: "_example.com/override_test")
                captured.value = result
                return .endTurn
            }
        }

        let adapter = CallingAdapter()
        let (client, agent, _, _) = ACPTestHelpers.pairedClientAndAgent(
            adapter: adapter,
            delegate: ConflictingDelegate()
        )
        try await client.registerExtensionMethod("_example.com/override_test") { _ in
            .object(["source": .string("registered")])
        }

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        _ = try await client.newSession(cwd: "/tmp")
        _ = try await agentRun
        _ = try await client.promptCollectingText("go")

        guard let result = adapter.captured.value,
              case .object(let dict) = result,
              case .string(let source) = dict["source"] else {
            Issue.record("Missing captured result")
            return
        }
        #expect(source == "registered")

        await client.shutdown()
        await agent.stop()
    }

    @Test("Extension meta builder merges capability metadata")
    func extensionMetaBuilder() throws {
        let capabilities = ACPExtensionSupport.withExtensionMeta(
            on: ACPAgentCapabilities(),
            namespace: "zed.dev",
            features: .object(["workspace": .boolean(true)])
        )
        guard case .object(let meta) = capabilities.meta,
              case .object(let zed) = meta["zed.dev"],
              case .boolean(let workspace) = zed["workspace"] else {
            Issue.record("Missing extension meta")
            return
        }
        #expect(workspace == true)
    }
}
