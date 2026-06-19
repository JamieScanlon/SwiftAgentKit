//
//  ACPAgentClient.swift
//  SwiftAgentKitACP
//

import Foundation
import SwiftAgentKit
import EasyJSON

/// Typed Agent→Client RPC surface for use inside ``ACPAgentAdapter/handlePrompt(sessionId:prompt:client:eventSink:)``.
public struct ACPAgentClient: Sendable {
    public enum Error: Swift.Error, LocalizedError, Sendable {
        case capabilityUnavailable(String)

        public var errorDescription: String? {
            switch self {
            case .capabilityUnavailable(let method):
                return "Client capability unavailable for \(method)"
            }
        }
    }

    private let connection: JSONRPCConnection
    private let capabilities: ACPClientCapabilities

    init(connection: JSONRPCConnection, capabilities: ACPClientCapabilities) {
        self.connection = connection
        self.capabilities = capabilities
    }

    public func readTextFile(
        sessionId: String,
        path: String,
        line: Int? = nil,
        limit: Int? = nil
    ) async throws -> ACPReadTextFileResponse {
        guard capabilities.fs.readTextFile else {
            throw Error.capabilityUnavailable("fs/read_text_file")
        }
        return try await connection.call(
            "fs/read_text_file",
            params: ACPReadTextFileRequest(sessionId: sessionId, path: path, line: line, limit: limit)
        )
    }

    public func writeTextFile(
        sessionId: String,
        path: String,
        content: String
    ) async throws -> ACPWriteTextFileResponse {
        guard capabilities.fs.writeTextFile else {
            throw Error.capabilityUnavailable("fs/write_text_file")
        }
        return try await connection.call(
            "fs/write_text_file",
            params: ACPWriteTextFileRequest(sessionId: sessionId, path: path, content: content)
        )
    }

    public func requestPermission(
        sessionId: String,
        toolCall: ACPToolCallUpdate,
        options: [ACPPermissionOption]
    ) async throws -> ACPRequestPermissionResponse {
        try await connection.call(
            "session/request_permission",
            params: ACPRequestPermissionRequest(sessionId: sessionId, toolCall: toolCall, options: options)
        )
    }

    public func createTerminal(
        sessionId: String,
        command: String? = nil,
        args: [String]? = nil,
        cwd: String? = nil,
        env: [String: String]? = nil
    ) async throws -> ACPCreateTerminalResponse {
        guard capabilities.terminal else {
            throw Error.capabilityUnavailable("terminal/create")
        }
        return try await connection.call(
            "terminal/create",
            params: ACPCreateTerminalRequest(
                sessionId: sessionId,
                command: command,
                args: args,
                cwd: cwd,
                env: env
            )
        )
    }

    public func terminalOutput(sessionId: String, terminalId: String) async throws -> ACPTerminalOutputResponse {
        guard capabilities.terminal else {
            throw Error.capabilityUnavailable("terminal/output")
        }
        return try await connection.call(
            "terminal/output",
            params: ACPTerminalOutputRequest(sessionId: sessionId, terminalId: terminalId)
        )
    }

    public func waitForTerminalExit(sessionId: String, terminalId: String) async throws -> ACPWaitForExitResponse {
        guard capabilities.terminal else {
            throw Error.capabilityUnavailable("terminal/wait_for_exit")
        }
        return try await connection.call(
            "terminal/wait_for_exit",
            params: ACPWaitForExitRequest(sessionId: sessionId, terminalId: terminalId)
        )
    }

    public func killTerminal(sessionId: String, terminalId: String) async throws -> ACPKillTerminalResponse {
        guard capabilities.terminal else {
            throw Error.capabilityUnavailable("terminal/kill")
        }
        return try await connection.call(
            "terminal/kill",
            params: ACPKillTerminalRequest(sessionId: sessionId, terminalId: terminalId)
        )
    }

    public func releaseTerminal(sessionId: String, terminalId: String) async throws -> ACPReleaseTerminalResponse {
        guard capabilities.terminal else {
            throw Error.capabilityUnavailable("terminal/release")
        }
        return try await connection.call(
            "terminal/release",
            params: ACPReleaseTerminalRequest(sessionId: sessionId, terminalId: terminalId)
        )
    }

    public func extMethod(method: String, params: JSON = .object([:])) async throws -> JSON {
        try ACPExtensionSupport.validateExtensionMethod(method)
        let paramsData = try JSONEncoder().encode(params)
        let resultData = try await connection.callRaw(method, params: paramsData)
        return try JSONDecoder().decode(JSON.self, from: resultData)
    }

    public func extNotification(method: String, params: JSON = .object([:])) async throws {
        try ACPExtensionSupport.validateExtensionMethod(method)
        let paramsData = try JSONEncoder().encode(params)
        try await connection.notifyRaw(method, params: paramsData)
    }
}
