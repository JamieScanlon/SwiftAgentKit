//
//  ACPClientDelegate.swift
//  SwiftAgentKitACP
//

import Foundation
import SwiftAgentKit
import EasyJSON

/// Handles Client-side ACP methods invoked by an Agent.
public protocol ACPClientDelegate: Sendable {
    func readTextFile(_ request: ACPReadTextFileRequest) async throws -> ACPReadTextFileResponse
    func writeTextFile(_ request: ACPWriteTextFileRequest) async throws -> ACPWriteTextFileResponse
    func requestPermission(_ request: ACPRequestPermissionRequest) async throws -> ACPRequestPermissionResponse

    func createTerminal(_ request: ACPCreateTerminalRequest) async throws -> ACPCreateTerminalResponse
    func terminalOutput(_ request: ACPTerminalOutputRequest) async throws -> ACPTerminalOutputResponse
    func waitForTerminalExit(_ request: ACPWaitForExitRequest) async throws -> ACPWaitForExitResponse
    func killTerminal(_ request: ACPKillTerminalRequest) async throws -> ACPKillTerminalResponse
    func releaseTerminal(_ request: ACPReleaseTerminalRequest) async throws -> ACPReleaseTerminalResponse

    /// Handles custom `_`-prefixed extension requests from the agent.
    func extMethod(method: String, params: JSON) async throws -> JSON

    /// Handles custom `_`-prefixed extension notifications from the agent.
    func extNotification(method: String, params: JSON) async
}

public extension ACPClientDelegate {
    func createTerminal(_ request: ACPCreateTerminalRequest) async throws -> ACPCreateTerminalResponse {
        throw JSONRPCConnectionError.methodNotFound("terminal/create")
    }
    func terminalOutput(_ request: ACPTerminalOutputRequest) async throws -> ACPTerminalOutputResponse {
        throw JSONRPCConnectionError.methodNotFound("terminal/output")
    }
    func waitForTerminalExit(_ request: ACPWaitForExitRequest) async throws -> ACPWaitForExitResponse {
        throw JSONRPCConnectionError.methodNotFound("terminal/wait_for_exit")
    }
    func killTerminal(_ request: ACPKillTerminalRequest) async throws -> ACPKillTerminalResponse {
        throw JSONRPCConnectionError.methodNotFound("terminal/kill")
    }
    func releaseTerminal(_ request: ACPReleaseTerminalRequest) async throws -> ACPReleaseTerminalResponse {
        throw JSONRPCConnectionError.methodNotFound("terminal/release")
    }

    func extMethod(method: String, params: JSON) async throws -> JSON {
        throw JSONRPCConnectionError.methodNotFound(method)
    }

    func extNotification(method: String, params: JSON) async {}
}

/// Default delegate with filesystem access and auto-approve permissions.
public struct DefaultACPClientDelegate: ACPClientDelegate {
    public let allowedRoots: [URL]
    public let autoApprovePermissions: Bool

    public init(allowedRoots: [URL] = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath)], autoApprovePermissions: Bool = true) {
        self.allowedRoots = allowedRoots
        self.autoApprovePermissions = autoApprovePermissions
    }

    public func readTextFile(_ request: ACPReadTextFileRequest) async throws -> ACPReadTextFileResponse {
        let url = try resolvePath(request.path)
        var content = try String(contentsOf: url, encoding: .utf8)
        if let line = request.line, line > 0 {
            let lines = content.components(separatedBy: .newlines)
            let start = line - 1
            let end = min(lines.count, start + (request.limit ?? lines.count))
            content = lines[start..<end].joined(separator: "\n")
        }
        return ACPReadTextFileResponse(content: content)
    }

    public func writeTextFile(_ request: ACPWriteTextFileRequest) async throws -> ACPWriteTextFileResponse {
        let url = try resolvePath(request.path)
        try request.content.write(to: url, atomically: true, encoding: .utf8)
        return ACPWriteTextFileResponse()
    }

    public func requestPermission(_ request: ACPRequestPermissionRequest) async throws -> ACPRequestPermissionResponse {
        if autoApprovePermissions, let first = request.options.first {
            return ACPRequestPermissionResponse(outcome: .selected(optionId: first.optionId))
        }
        return ACPRequestPermissionResponse(outcome: .cancelled)
    }

    private func resolvePath(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard allowedRoots.contains(where: { url.path.hasPrefix($0.standardizedFileURL.path) }) else {
            throw JSONRPCConnectionError.invalidRequest
        }
        return url
    }
}
