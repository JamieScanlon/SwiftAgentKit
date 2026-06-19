//
//  ACPAgentClientTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import SwiftAgentKit
import Testing
@testable import SwiftAgentKitACP

@Suite("ACP Agent Client")
struct ACPAgentClientTests {
    @Test("readTextFile round-trip via ACPAgentClient")
    func readTextFileRoundTrip() async throws {
        let url = ACPTestHelpers.tempFileURL(prefix: "acp-agent-read")
        try "agent-read-content".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let delegate = RecordingFSDelegate(
            allowedRoots: [url.deletingLastPathComponent()],
            readContent: "agent-read-content"
        )
        let client = ACPClient(name: "test-client", transport: clientTransport, delegate: delegate)
        let agentConnection = JSONRPCConnection(transport: agentTransport)
        await ACPTestHelpers.registerMinimalAgentStub(on: agentConnection)

        try await agentConnection.connect()
        defer { Task { await agentConnection.disconnect(); await client.shutdown() } }

        try await client.connect()
        try await client.newSession(cwd: "/tmp")
        guard let sessionId = await client.sessionId else {
            Issue.record("Missing sessionId")
            return
        }

        let caps = await clientCapabilitiesFromInitialize(client: client, agentConnection: agentConnection)
        let agentClient = ACPAgentClient(connection: agentConnection, capabilities: caps)
        let response = try await agentClient.readTextFile(sessionId: sessionId, path: url.path)
        #expect(response.content == "agent-read-content")
        #expect(delegate.readCallCount.value == 1)
        #expect(delegate.lastReadSessionId.value == sessionId)
    }

    @Test("writeTextFile round-trip via ACPAgentClient")
    func writeTextFileRoundTrip() async throws {
        let url = ACPTestHelpers.tempFileURL(prefix: "acp-agent-write")
        defer { try? FileManager.default.removeItem(at: url) }

        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let delegate = RecordingFSDelegate(allowedRoots: [url.deletingLastPathComponent()])
        let client = ACPClient(name: "test-client", transport: clientTransport, delegate: delegate)
        let agentConnection = JSONRPCConnection(transport: agentTransport)
        await ACPTestHelpers.registerMinimalAgentStub(on: agentConnection)

        try await agentConnection.connect()
        defer { Task { await agentConnection.disconnect(); await client.shutdown() } }

        try await client.connect()
        try await client.newSession(cwd: "/tmp")
        guard let sessionId = await client.sessionId else {
            Issue.record("Missing sessionId")
            return
        }

        let caps = await clientCapabilitiesFromInitialize(client: client, agentConnection: agentConnection)
        let agentClient = ACPAgentClient(connection: agentConnection, capabilities: caps)
        _ = try await agentClient.writeTextFile(sessionId: sessionId, path: url.path, content: "written-by-agent")
        #expect(delegate.writeCallCount.value == 1)
        #expect(try String(contentsOf: url, encoding: .utf8) == "written-by-agent")
    }

    @Test("fs/read_text_file rejected when readTextFile capability false")
    func readRejectedWhenCapabilityFalse() async throws {
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let delegate = RecordingFSDelegate(allowedRoots: [URL(fileURLWithPath: "/")])
        let client = ACPClient(
            name: "test-client",
            transport: clientTransport,
            delegate: delegate,
            clientCapabilities: ACPClientCapabilities(
                fs: ACPFilesystemCapabilities(readTextFile: false, writeTextFile: true),
                terminal: false
            )
        )
        let agentConnection = JSONRPCConnection(transport: agentTransport)
        await ACPTestHelpers.registerMinimalAgentStub(on: agentConnection)

        try await agentConnection.connect()
        defer { Task { await agentConnection.disconnect(); await client.shutdown() } }

        try await client.connect()
        try await client.newSession(cwd: "/tmp")
        guard let sessionId = await client.sessionId else {
            Issue.record("Missing sessionId")
            return
        }

        do {
            let _: ACPReadTextFileResponse = try await agentConnection.call(
                "fs/read_text_file",
                params: ACPReadTextFileRequest(sessionId: sessionId, path: "/tmp/a.txt")
            )
            Issue.record("Expected methodNotFound")
        } catch let error as JSONRPCConnectionError {
            if case .remoteError(let rpcError) = error {
                #expect(rpcError.code == JSONRPCErrorCode.methodNotFound.rawValue)
            } else {
                Issue.record("Expected remoteError")
            }
        }
        #expect(delegate.readCallCount.value == 0)
    }

    @Test("ACPAgentClient throws capabilityUnavailable without RPC")
    func capabilityGuardOnAgentClient() async throws {
        let agentClient = ACPTestHelpers.dummyAgentClient(
            capabilities: ACPClientCapabilities(
                fs: ACPFilesystemCapabilities(readTextFile: false, writeTextFile: false),
                terminal: false
            )
        )
        do {
            _ = try await agentClient.readTextFile(sessionId: "s1", path: "/tmp/a.txt")
            Issue.record("Expected capabilityUnavailable")
        } catch let error as ACPAgentClient.Error {
            if case .capabilityUnavailable(let method) = error {
                #expect(method == "fs/read_text_file")
            } else {
                Issue.record("Expected capabilityUnavailable")
            }
        }
    }

    @Test("requestPermission delivers full ToolCallUpdate to delegate")
    func requestPermissionWithToolCallUpdate() async throws {
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let delegate = RecordingPermissionDelegate()
        let client = ACPClient(
            name: "test-client",
            transport: clientTransport,
            delegate: delegate,
            clientCapabilities: ACPClient.defaultClientCapabilities()
        )
        let agentConnection = JSONRPCConnection(transport: agentTransport)
        await ACPTestHelpers.registerMinimalAgentStub(on: agentConnection)

        try await agentConnection.connect()
        defer { Task { await agentConnection.disconnect(); await client.shutdown() } }

        try await client.connect()
        try await client.newSession(cwd: "/tmp")
        guard let sessionId = await client.sessionId else {
            Issue.record("Missing sessionId")
            return
        }

        let toolCall = ACPToolCallUpdate(
            toolCallId: "tc-perm",
            title: "Delete file",
            kind: .delete,
            status: .pending,
            locations: [ACPToolCallLocation(path: "/tmp/a.txt", line: 1)]
        )
        let agentClient = ACPAgentClient(
            connection: agentConnection,
            capabilities: ACPClient.defaultClientCapabilities()
        )
        let response = try await agentClient.requestPermission(
            sessionId: sessionId,
            toolCall: toolCall,
            options: [ACPPermissionOption(optionId: "allow", name: "Allow", kind: "allow_once")]
        )
        if case .selected(let optionId) = response.outcome {
            #expect(optionId == "allow")
        } else {
            Issue.record("Expected selected outcome")
        }
        #expect(delegate.lastToolCall.value?.toolCallId == "tc-perm")
        #expect(delegate.lastToolCall.value?.kind == .delete)
        #expect(delegate.lastToolCall.value?.locations?.first?.path == "/tmp/a.txt")
    }

    @Test("cancelPrompt resolves pending permission with cancelled")
    func cancelPromptResolvesPendingPermission() async throws {
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let delegate = SlowPermissionDelegate()
        let client = ACPClient(name: "test-client", transport: clientTransport, delegate: delegate)
        let agentConnection = JSONRPCConnection(transport: agentTransport)
        await ACPTestHelpers.registerMinimalAgentStub(on: agentConnection)

        try await agentConnection.connect()
        defer { Task { await agentConnection.disconnect(); await client.shutdown() } }

        try await client.connect()
        try await client.newSession(cwd: "/tmp")
        guard let sessionId = await client.sessionId else {
            Issue.record("Missing sessionId")
            return
        }

        let agentClient = ACPAgentClient(
            connection: agentConnection,
            capabilities: ACPClient.defaultClientCapabilities()
        )

        async let permissionTask = agentClient.requestPermission(
            sessionId: sessionId,
            toolCall: ACPToolCallUpdate(toolCallId: "tc1", title: "Slow op"),
            options: [ACPPermissionOption(optionId: "allow", name: "Allow", kind: "allow_once")]
        )

        for _ in 0..<100 where !delegate.permissionStarted.value {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(delegate.permissionStarted.value)

        try await client.cancelPrompt()

        let response = try await permissionTask
        #expect(response.outcome == .cancelled)
    }

    @Test("terminal/create via ACPAgentClient")
    func terminalCreateViaAgentClient() async throws {
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let delegate = RecordingTerminalDelegate(terminalId: "term-agent-client")
        let client = ACPClient(
            name: "test-client",
            transport: clientTransport,
            delegate: delegate,
            clientCapabilities: ACPClient.defaultClientCapabilities(advertiseTerminal: true)
        )
        let agentConnection = JSONRPCConnection(transport: agentTransport)
        await ACPTestHelpers.registerMinimalAgentStub(on: agentConnection)

        try await agentConnection.connect()
        defer { Task { await agentConnection.disconnect(); await client.shutdown() } }

        try await client.connect()
        try await client.newSession(cwd: "/tmp")
        guard let sessionId = await client.sessionId else {
            Issue.record("Missing sessionId")
            return
        }

        let agentClient = ACPAgentClient(
            connection: agentConnection,
            capabilities: ACPClientCapabilities(
                fs: ACPFilesystemCapabilities(readTextFile: true, writeTextFile: true),
                terminal: true
            )
        )
        let response = try await agentClient.createTerminal(sessionId: sessionId, command: "echo")
        #expect(response.terminalId == "term-agent-client")
        #expect(delegate.createTerminalCallCount.value == 1)
    }

    @Test("Adapter receives ACPAgentClient during handlePrompt")
    func adapterReceivesAgentClient() async throws {
        let adapter = FSUsingTestAdapter()
        let (clientTransport, agentTransport) = JSONRPCMemoryTransport.paired()
        let url = ACPTestHelpers.tempFileURL(prefix: "acp-adapter-fs")
        try "from-adapter".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let delegate = RecordingFSDelegate(
            allowedRoots: [url.deletingLastPathComponent()],
            readContent: "from-adapter"
        )
        let agent = ACPAgent(adapter: adapter, transport: agentTransport)
        let client = ACPClient(name: "test-client", transport: clientTransport, delegate: delegate)

        async let agentRun: Void = try await agent.run()
        try await client.connect()
        try await client.newSession(cwd: "/tmp")
        _ = try await agentRun

        _ = try await client.promptCollectingText("read file at \(url.path)")
        #expect(adapter.readViaClientCount.value == 1)
        #expect(adapter.lastReadPath.value == url.path)

        await client.shutdown()
        await agent.stop()
    }

    private func clientCapabilitiesFromInitialize(
        client: ACPClient,
        agentConnection: JSONRPCConnection
    ) async -> ACPClientCapabilities {
        _ = client
        _ = agentConnection
        return ACPClient.defaultClientCapabilities()
    }
}

private final class RecordingFSDelegate: ACPClientDelegate, @unchecked Sendable {
    let allowedRoots: [URL]
    let readContent: String
    let readCallCount = LockBox(0)
    let writeCallCount = LockBox(0)
    let lastReadSessionId = LockBox<String?>(nil)

    init(allowedRoots: [URL], readContent: String = "") {
        self.allowedRoots = allowedRoots
        self.readContent = readContent
    }

    func readTextFile(_ request: ACPReadTextFileRequest) async throws -> ACPReadTextFileResponse {
        readCallCount.value += 1
        lastReadSessionId.value = request.sessionId
        let url = try resolvePath(request.path)
        let content = readContent.isEmpty ? (try String(contentsOf: url, encoding: .utf8)) : readContent
        return ACPReadTextFileResponse(content: content)
    }

    func writeTextFile(_ request: ACPWriteTextFileRequest) async throws -> ACPWriteTextFileResponse {
        writeCallCount.value += 1
        let url = try resolvePath(request.path)
        try request.content.write(to: url, atomically: true, encoding: .utf8)
        return ACPWriteTextFileResponse()
    }

    func requestPermission(_ request: ACPRequestPermissionRequest) async throws -> ACPRequestPermissionResponse {
        ACPRequestPermissionResponse(outcome: .cancelled)
    }

    private func resolvePath(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard allowedRoots.contains(where: { url.path.hasPrefix($0.standardizedFileURL.path) }) else {
            throw JSONRPCConnectionError.invalidRequest
        }
        return url
    }
}

private final class RecordingPermissionDelegate: ACPClientDelegate, @unchecked Sendable {
    let lastToolCall = LockBox<ACPToolCallUpdate?>(nil)

    func readTextFile(_ request: ACPReadTextFileRequest) async throws -> ACPReadTextFileResponse {
        ACPReadTextFileResponse(content: "")
    }

    func writeTextFile(_ request: ACPWriteTextFileRequest) async throws -> ACPWriteTextFileResponse {
        ACPWriteTextFileResponse()
    }

    func requestPermission(_ request: ACPRequestPermissionRequest) async throws -> ACPRequestPermissionResponse {
        lastToolCall.value = request.toolCall
        return ACPRequestPermissionResponse(outcome: .selected(optionId: request.options.first?.optionId ?? "allow"))
    }
}

private final class SlowPermissionDelegate: ACPClientDelegate, @unchecked Sendable {
    let permissionStarted = LockBox(false)

    func readTextFile(_ request: ACPReadTextFileRequest) async throws -> ACPReadTextFileResponse {
        ACPReadTextFileResponse(content: "")
    }

    func writeTextFile(_ request: ACPWriteTextFileRequest) async throws -> ACPWriteTextFileResponse {
        ACPWriteTextFileResponse()
    }

    func requestPermission(_ request: ACPRequestPermissionRequest) async throws -> ACPRequestPermissionResponse {
        permissionStarted.value = true
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return ACPRequestPermissionResponse(outcome: .selected(optionId: request.options.first?.optionId ?? "allow"))
    }
}

private final class FSUsingTestAdapter: ACPAgentAdapter, @unchecked Sendable {
    let readViaClientCount = LockBox(0)
    let lastReadPath = LockBox<String?>(nil)

    var agentInfo: ACPImplementation {
        ACPImplementation(name: "fs-using-adapter", version: "1.0.0")
    }

    var agentCapabilities: ACPAgentCapabilities { ACPAgentCapabilities() }

    func handlePrompt(
        sessionId: String,
        prompt: [ACPContentBlock],
        client: ACPAgentClient,
        eventSink: @escaping @Sendable (ACPSessionUpdate) async throws -> Void
    ) async throws -> ACPStopReason {
        let path = prompt.compactMap { block -> String? in
            if case .text(let text) = block, text.hasPrefix("read file at ") {
                return String(text.dropFirst("read file at ".count))
            }
            return nil
        }.first

        if let path {
            let response = try await client.readTextFile(sessionId: sessionId, path: path)
            readViaClientCount.value += 1
            lastReadPath.value = path
            try await eventSink(.agentMessageChunk(messageId: nil, content: .text(response.content)))
        }
        return .endTurn
    }
}
