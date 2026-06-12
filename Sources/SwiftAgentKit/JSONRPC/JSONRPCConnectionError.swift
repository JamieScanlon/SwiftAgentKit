//
//  JSONRPCConnectionError.swift
//  SwiftAgentKit
//

import Foundation

public enum JSONRPCConnectionError: Error, LocalizedError, Sendable {
    case notConnected
    case parseError
    case invalidRequest
    case methodNotFound(String)
    case remoteError(JSONRPCError)
    case encodingFailed
    case disconnected

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "JSON-RPC connection is not connected"
        case .parseError: return "Failed to parse JSON-RPC message"
        case .invalidRequest: return "Invalid JSON-RPC request"
        case .methodNotFound(let method): return "Method not found: \(method)"
        case .remoteError(let error): return "Remote error \(error.code): \(error.message)"
        case .encodingFailed: return "Failed to encode JSON-RPC message"
        case .disconnected: return "JSON-RPC connection disconnected"
        }
    }
}
