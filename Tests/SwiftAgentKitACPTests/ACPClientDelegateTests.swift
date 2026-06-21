//
//  ACPClientDelegateTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import SwiftAgentKit
import Testing
@testable import SwiftAgentKitACP

@Suite("Default ACP Client Delegate")
struct DefaultACPClientDelegateTests {
    @Test("Read text file within allowed root")
    func readTextFile() async throws {
        let url = ACPTestHelpers.tempFileURL(prefix: "acp-read")
        try "line1\nline2\nline3".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let delegate = DefaultACPClientDelegate(allowedRoots: [url.deletingLastPathComponent()])
        let response = try await delegate.readTextFile(ACPReadTextFileRequest(sessionId: "s1", path: url.path))
        #expect(response.content.contains("line1"))
    }

    @Test("Read text file with line and limit")
    func readTextFileWithLineLimit() async throws {
        let url = ACPTestHelpers.tempFileURL(prefix: "acp-read-lines")
        try "a\nb\nc\nd".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let delegate = DefaultACPClientDelegate(allowedRoots: [url.deletingLastPathComponent()])
        let response = try await delegate.readTextFile(
            ACPReadTextFileRequest(sessionId: "s1", path: url.path, line: 2, limit: 2)
        )
        #expect(response.content == "b\nc")
    }

    @Test("Write text file within allowed root")
    func writeTextFile() async throws {
        let url = ACPTestHelpers.tempFileURL(prefix: "acp-write")
        defer { try? FileManager.default.removeItem(at: url) }

        let delegate = DefaultACPClientDelegate(allowedRoots: [url.deletingLastPathComponent()])
        _ = try await delegate.writeTextFile(ACPWriteTextFileRequest(sessionId: "s1", path: url.path, content: "written"))
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content == "written")
    }

    @Test("Read outside allowed root throws")
    func readOutsideRoot() async throws {
        let delegate = DefaultACPClientDelegate(allowedRoots: [URL(fileURLWithPath: "/nonexistent-root")])
        do {
            _ = try await delegate.readTextFile(ACPReadTextFileRequest(sessionId: "s1", path: "/etc/hosts"))
            Issue.record("Expected invalidRequest")
        } catch let error as JSONRPCConnectionError {
            #expect(ACPTestHelpers.connectionErrorsEqual(error, .invalidRequest))
        }
    }

    @Test("Auto-approve permission selects first option")
    func autoApprovePermission() async throws {
        let delegate = DefaultACPClientDelegate(autoApprovePermissions: true)
        let response = try await delegate.requestPermission(
            ACPRequestPermissionRequest(
                sessionId: "s1",
                toolCall: ACPToolCallUpdate(toolCallId: "tc1"),
                options: [
                    ACPPermissionOption(optionId: "allow-once", name: "Allow Once", kind: "allow"),
                    ACPPermissionOption(optionId: "deny", name: "Deny", kind: "deny")
                ]
            )
        )
        if case .selected(let id) = response.outcome {
            #expect(id == "allow-once")
        } else {
            Issue.record("Expected selected outcome")
        }
    }

    @Test("Permission denied when auto-approve disabled")
    func denyPermission() async throws {
        let delegate = DefaultACPClientDelegate(autoApprovePermissions: false)
        let response = try await delegate.requestPermission(
            ACPRequestPermissionRequest(
                sessionId: "s1",
                toolCall: ACPToolCallUpdate(toolCallId: "tc1"),
                options: [ACPPermissionOption(optionId: "allow", name: "Allow", kind: "allow")]
            )
        )
        #expect(response.outcome == .cancelled)
    }
}

@Suite("ACP Client Delegate Terminal Stubs")
struct ACPClientDelegateTerminalStubTests {
    @Test("Default terminal methods throw methodNotFound")
    func terminalStubs() async throws {
        struct StubDelegate: ACPClientDelegate {
            func readTextFile(_ request: ACPReadTextFileRequest) async throws -> ACPReadTextFileResponse {
                ACPReadTextFileResponse(content: "")
            }
            func writeTextFile(_ request: ACPWriteTextFileRequest) async throws -> ACPWriteTextFileResponse {
                ACPWriteTextFileResponse()
            }
            func requestPermission(_ request: ACPRequestPermissionRequest) async throws -> ACPRequestPermissionResponse {
                ACPRequestPermissionResponse(outcome: .cancelled)
            }
        }

        let delegate = StubDelegate()
        do {
            _ = try await delegate.createTerminal(ACPCreateTerminalRequest(sessionId: "s1"))
            Issue.record("Expected methodNotFound")
        } catch let error as JSONRPCConnectionError {
            if case .methodNotFound(let method) = error {
                #expect(method == "terminal/create")
            } else {
                Issue.record("Expected methodNotFound")
            }
        }
    }
}
