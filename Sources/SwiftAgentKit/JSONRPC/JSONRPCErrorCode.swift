//
//  JSONRPCErrorCode.swift
//  SwiftAgentKit
//

import Foundation

/// Standard JSON-RPC 2.0 error codes.
public enum JSONRPCErrorCode: Int, Sendable {
    case parseError = -32700
    case invalidRequest = -32600
    case methodNotFound = -32601
    case invalidParams = -32602
    case internalError = -32603
}
