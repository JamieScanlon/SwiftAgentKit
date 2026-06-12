//
//  ACPModelsTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import EasyJSON
import Testing
@testable import SwiftAgentKitACP

// MARK: - Shared / Capabilities

@Suite("ACP Shared Models")
struct ACPSharedModelsTests {
    @Test("ACPImplementation round-trip")
    func implementation() throws {
        let original = ACPImplementation(name: "agent", title: "Test Agent", version: "2.0.0")
        let decoded = try ACPTestHelpers.roundTrip(original)
        #expect(decoded == original)
    }

    @Test("ACPMeta encodes _meta key")
    func meta() throws {
        let original = ACPMeta(meta: .object(["key": .string("value")]))
        let data = try JSONEncoder().encode(original)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["_meta"] != nil)
        let decoded = try JSONDecoder().decode(ACPMeta.self, from: data)
        #expect(ACPTestHelpers.jsonEqual(decoded.meta, original.meta))
    }

    @Test("ACPFilesystemCapabilities round-trip")
    func filesystemCapabilities() throws {
        let original = ACPFilesystemCapabilities(readTextFile: true, writeTextFile: true)
        #expect(try ACPTestHelpers.roundTrip(original) == original)
    }

    @Test("ACPPromptCapabilities round-trip")
    func promptCapabilities() throws {
        let original = ACPPromptCapabilities(image: true, audio: false, embeddedContext: true)
        #expect(try ACPTestHelpers.roundTrip(original) == original)
    }

    @Test("ACPMcpCapabilities round-trip")
    func mcpCapabilities() throws {
        let original = ACPMcpCapabilities(http: true, sse: true)
        #expect(try ACPTestHelpers.roundTrip(original) == original)
    }

    @Test("ACPSessionCapabilities round-trip")
    func sessionCapabilities() throws {
        let original = ACPSessionCapabilities(load: true, list: false, resume: true, setMode: true)
        #expect(try ACPTestHelpers.roundTrip(original) == original)
    }

    @Test("ACPAuthCapabilities round-trip")
    func authCapabilities() throws {
        let original = ACPAuthCapabilities(logout: true)
        #expect(try ACPTestHelpers.roundTrip(original) == original)
    }

    @Test("ACPClientCapabilities round-trip")
    func clientCapabilities() throws {
        let original = ACPClientCapabilities(
            fs: ACPFilesystemCapabilities(readTextFile: true, writeTextFile: false),
            terminal: true
        )
        #expect(try ACPTestHelpers.roundTrip(original) == original)
    }

    @Test("ACPAgentCapabilities round-trip")
    func agentCapabilities() throws {
        let original = ACPAgentCapabilities(
            loadSession: true,
            promptCapabilities: ACPPromptCapabilities(image: true),
            mcpCapabilities: ACPMcpCapabilities(http: true),
            sessionCapabilities: ACPSessionCapabilities(load: true),
            auth: ACPAuthCapabilities(logout: true)
        )
        #expect(try ACPTestHelpers.roundTrip(original) == original)
    }

    @Test("ACPAuthMethod round-trip")
    func authMethod() throws {
        let original = ACPAuthMethod(id: "oauth", name: "OAuth", description: "OAuth flow")
        #expect(try ACPTestHelpers.roundTrip(original) == original)
    }
}

// MARK: - Initialize / Authenticate

@Suite("ACP Initialize Models")
struct ACPInitializeModelsTests {
    @Test("ACPInitializeRequest round-trip")
    func initializeRequest() throws {
        let original = ACPInitializeRequest(
            protocolVersion: 1,
            clientCapabilities: ACPClientCapabilities(
                fs: ACPFilesystemCapabilities(readTextFile: true, writeTextFile: true)
            ),
            clientInfo: ACPImplementation(name: "client", version: "1.0.0")
        )
        let decoded = try ACPTestHelpers.roundTripCodable(original)
        #expect(decoded.protocolVersion == 1)
        #expect(decoded.clientCapabilities.fs.readTextFile == true)
    }

    @Test("ACPInitializeResponse round-trip")
    func initializeResponse() throws {
        let original = ACPInitializeResponse(
            protocolVersion: 1,
            agentCapabilities: ACPAgentCapabilities(loadSession: true),
            agentInfo: ACPImplementation(name: "agent", version: "1.0.0"),
            authMethods: [ACPAuthMethod(id: "none")]
        )
        let decoded = try ACPTestHelpers.roundTripCodable(original)
        #expect(decoded.agentInfo?.name == "agent")
        #expect(decoded.authMethods.count == 1)
    }

    @Test("ACPAuthenticateRequest round-trip")
    func authenticateRequest() throws {
        let original = ACPAuthenticateRequest(methodId: "oauth")
        let decoded = try ACPTestHelpers.roundTripCodable(original)
        #expect(decoded.methodId == "oauth")
    }

    @Test("ACPAuthenticateResponse round-trip")
    func authenticateResponse() throws {
        let original = ACPAuthenticateResponse(meta: .object(["ok": .boolean(true)]))
        let decoded = try ACPTestHelpers.roundTripCodable(original)
        #expect(ACPTestHelpers.jsonEqual(decoded.meta, original.meta))
    }
}

// MARK: - Session

@Suite("ACP Session Models")
struct ACPSessionModelsTests {
    @Test("ACPMcpServer round-trip")
    func mcpServer() throws {
        let original = ACPMcpServer(name: "mcp", command: "mcp-server", args: ["--stdio"], env: ["KEY": "val"])
        #expect(try ACPTestHelpers.roundTrip(original) == original)
    }

    @Test("ACPNewSessionRequest round-trip")
    func newSessionRequest() throws {
        let original = ACPNewSessionRequest(
            cwd: "/project",
            mcpServers: [ACPMcpServer(name: "tools")],
            additionalRoots: ["/extra"]
        )
        let decoded = try ACPTestHelpers.roundTripCodable(original)
        #expect(decoded.cwd == "/project")
        #expect(decoded.mcpServers.count == 1)
    }

    @Test("ACPNewSessionResponse round-trip")
    func newSessionResponse() throws {
        let original = ACPNewSessionResponse(
            sessionId: "sess-1",
            configOptions: [ACPSessionConfigOption(id: "mode", name: "Mode")],
            mode: ACPSessionModeState(currentModeId: "default")
        )
        let decoded = try ACPTestHelpers.roundTripCodable(original)
        #expect(decoded.sessionId == "sess-1")
    }

    @Test("ACPSessionConfigOption round-trip")
    func sessionConfigOption() throws {
        let original = ACPSessionConfigOption(id: "opt", name: "Option", type: "string", value: .string("x"))
        let decoded = try ACPTestHelpers.roundTripCodable(original)
        #expect(decoded.id == "opt")
    }

    @Test("ACPSessionModeState round-trip")
    func sessionModeState() throws {
        let original = ACPSessionModeState(
            currentModeId: "code",
            availableModes: [ACPSessionMode(id: "code", name: "Code")]
        )
        #expect(try ACPTestHelpers.roundTrip(original) == original)
    }

    @Test("ACPPromptRequest round-trip")
    func promptRequest() throws {
        let original = ACPPromptRequest(sessionId: "s1", prompt: [.text("hello")])
        let decoded = try ACPTestHelpers.roundTripCodable(original)
        #expect(decoded.sessionId == "s1")
    }

    @Test("ACPPromptResponse round-trip")
    func promptResponse() throws {
        let original = ACPPromptResponse(stopReason: .endTurn)
        let decoded = try ACPTestHelpers.roundTripCodable(original)
        #expect(decoded.stopReason == .endTurn)
    }

    @Test("All stop reasons round-trip")
    func allStopReasons() throws {
        let reasons: [ACPStopReason] = [.endTurn, .maxTokens, .maxTurnRequests, .refusal, .cancelled]
        for reason in reasons {
            let data = try JSONEncoder().encode(ACPPromptResponse(stopReason: reason))
            let decoded = try JSONDecoder().decode(ACPPromptResponse.self, from: data)
            #expect(decoded.stopReason == reason)
        }
    }

    @Test("ACPSessionCancelParams round-trip")
    func sessionCancelParams() throws {
        let original = ACPSessionCancelParams(sessionId: "sess-1")
        let decoded = try ACPTestHelpers.roundTripCodable(original)
        #expect(decoded.sessionId == "sess-1")
    }
}

// MARK: - Content Blocks

@Suite("ACP Content Block Models")
struct ACPContentBlockModelsTests {
    @Test("Text content block")
    func textBlock() throws {
        let block = ACPContentBlock.text("hello")
        let decoded = try ACPTestHelpers.roundTrip(block)
        #expect(decoded == block)
    }

    @Test("Resource content block")
    func resourceBlock() throws {
        let block = ACPContentBlock.resource(ACPResourceContent(uri: "file:///a.txt", mimeType: "text/plain", text: "data"))
        #expect(try ACPTestHelpers.roundTrip(block) == block)
    }

    @Test("Resource link content block")
    func resourceLinkBlock() throws {
        let block = ACPContentBlock.resourceLink(ACPResourceLink(uri: "file:///b.txt", name: "b.txt"))
        #expect(try ACPTestHelpers.roundTrip(block) == block)
    }

    @Test("Image content block")
    func imageBlock() throws {
        let block = ACPContentBlock.image(ACPImageContent(mimeType: "image/png", data: "base64"))
        #expect(try ACPTestHelpers.roundTrip(block) == block)
    }

    @Test("Audio content block")
    func audioBlock() throws {
        let block = ACPContentBlock.audio(ACPAudioContent(mimeType: "audio/wav", data: "base64"))
        #expect(try ACPTestHelpers.roundTrip(block) == block)
    }

    @Test("Unknown content block type throws")
    func unknownContentBlock() {
        let json = #"{"type":"unknown","text":"x"}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ACPContentBlock.self, from: json)
        }
    }
}

// MARK: - Session Updates

@Suite("ACP Session Update Models")
struct ACPSessionUpdateModelsTests {
    @Test("Agent message chunk update")
    func agentMessageChunk() throws {
        let update = ACPSessionUpdate.agentMessageChunk(messageId: "m1", content: .text("hi"))
        #expect(try ACPTestHelpers.roundTrip(update) == update)
    }

    @Test("Plan update")
    func planUpdate() throws {
        let update = ACPSessionUpdate.plan(entries: [ACPPlanEntry(content: "step", priority: "high", status: "pending")])
        #expect(try ACPTestHelpers.roundTrip(update) == update)
    }

    @Test("Tool call update")
    func toolCallUpdate() throws {
        let update = ACPSessionUpdate.toolCall(toolCallId: "tc1", title: "Run", kind: "other", status: "pending")
        #expect(try ACPTestHelpers.roundTrip(update) == update)
    }

    @Test("Tool call status update")
    func toolCallStatusUpdate() throws {
        let update = ACPSessionUpdate.toolCallUpdate(toolCallId: "tc1", status: "completed", content: [.text("done")])
        #expect(try ACPTestHelpers.roundTrip(update) == update)
    }

    @Test("Usage update")
    func usageUpdate() throws {
        let update = ACPSessionUpdate.usageUpdate(used: 100, size: 200, cost: ACPUsageCost(amount: 0.01, currency: "USD"))
        #expect(try ACPTestHelpers.roundTrip(update) == update)
    }

    @Test("Session update notification round-trip")
    func sessionUpdateNotification() throws {
        let notification = ACPSessionUpdateNotification(
            sessionId: "s1",
            update: .agentMessageChunk(messageId: "m1", content: .text("chunk"))
        )
        let decoded = try ACPTestHelpers.roundTripCodable(notification)
        #expect(decoded.sessionId == "s1")
    }

    @Test("Unknown session update throws")
    func unknownSessionUpdate() {
        let json = #"{"sessionUpdate":"unknown"}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ACPSessionUpdate.self, from: json)
        }
    }
}

// MARK: - Client-side methods

@Suite("ACP Client Method Models")
struct ACPClientMethodModelsTests {
    @Test("Read text file request/response")
    func readTextFile() throws {
        let request = ACPReadTextFileRequest(path: "/tmp/a.txt", line: 1, limit: 10)
        let decodedReq = try ACPTestHelpers.roundTripCodable(request)
        #expect(decodedReq.path == "/tmp/a.txt")

        let response = ACPReadTextFileResponse(content: "file contents")
        let decodedResp = try ACPTestHelpers.roundTripCodable(response)
        #expect(decodedResp.content == "file contents")
    }

    @Test("Write text file request/response")
    func writeTextFile() throws {
        let request = ACPWriteTextFileRequest(path: "/tmp/b.txt", content: "new content")
        let decodedReq = try ACPTestHelpers.roundTripCodable(request)
        #expect(decodedReq.content == "new content")

        let response = ACPWriteTextFileResponse()
        _ = try ACPTestHelpers.roundTripCodable(response)
    }

    @Test("Request permission models")
    func requestPermission() throws {
        let request = ACPRequestPermissionRequest(
            sessionId: "s1",
            toolCall: ACPToolCallInfo(toolCallId: "tc1", title: "Delete file"),
            options: [ACPPermissionOption(optionId: "allow", name: "Allow", kind: "allow")]
        )
        let decodedReq = try ACPTestHelpers.roundTripCodable(request)
        #expect(decodedReq.toolCall.toolCallId == "tc1")

        let selected = ACPRequestPermissionResponse(outcome: .selected(optionId: "allow"))
        let decodedSelected = try ACPTestHelpers.roundTripCodable(selected)
        if case .selected(let id) = decodedSelected.outcome {
            #expect(id == "allow")
        } else {
            Issue.record("Expected selected outcome")
        }

        let cancelled = ACPRequestPermissionResponse(outcome: .cancelled)
        let decodedCancelled = try ACPTestHelpers.roundTripCodable(cancelled)
        #expect(decodedCancelled.outcome == .cancelled)
    }
}

// MARK: - Terminal models

@Suite("ACP Terminal Models")
struct ACPTerminalModelsTests {
    @Test("Create terminal request/response")
    func createTerminal() throws {
        let request = ACPCreateTerminalRequest(sessionId: "s1", command: "ls", args: ["-la"], cwd: "/tmp")
        let decoded = try ACPTestHelpers.roundTripCodable(request)
        #expect(decoded.command == "ls")

        let response = ACPCreateTerminalResponse(terminalId: "term-1")
        #expect(try ACPTestHelpers.roundTripCodable(response).terminalId == "term-1")
    }

    @Test("Terminal output request/response")
    func terminalOutput() throws {
        let request = ACPTerminalOutputRequest(sessionId: "s1", terminalId: "term-1")
        let response = ACPTerminalOutputResponse(
            output: "hello\n",
            truncated: false,
            exitStatus: ACPTerminalExitStatus(exitCode: 0)
        )
        #expect(try ACPTestHelpers.roundTripCodable(request).terminalId == "term-1")
        #expect(try ACPTestHelpers.roundTripCodable(response).output == "hello\n")
    }

    @Test("Wait for exit request/response")
    func waitForExit() throws {
        let request = ACPWaitForExitRequest(sessionId: "s1", terminalId: "term-1")
        let response = ACPWaitForExitResponse(exitStatus: ACPTerminalExitStatus(exitCode: 0))
        #expect(try ACPTestHelpers.roundTripCodable(response).exitStatus.exitCode == 0)
        _ = try ACPTestHelpers.roundTripCodable(request)
    }

    @Test("Kill and release terminal models")
    func killAndRelease() throws {
        _ = try ACPTestHelpers.roundTripCodable(ACPKillTerminalRequest(sessionId: "s1", terminalId: "term-1"))
        _ = try ACPTestHelpers.roundTripCodable(ACPReleaseTerminalRequest(sessionId: "s1", terminalId: "term-1"))
        _ = try ACPTestHelpers.roundTripCodable(ACPKillTerminalResponse())
        _ = try ACPTestHelpers.roundTripCodable(ACPReleaseTerminalResponse())
    }

    @Test("Terminal exit status round-trip")
    func exitStatus() throws {
        let status = ACPTerminalExitStatus(exitCode: 1, signal: "SIGTERM")
        #expect(try ACPTestHelpers.roundTrip(status) == status)
    }
}
