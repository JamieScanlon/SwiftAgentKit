//
//  ACPErrorCode.swift
//  SwiftAgentKitACP
//

import Foundation

/// ACP-specific JSON-RPC error codes beyond the standard JSON-RPC 2.0 set.
public enum ACPErrorCode: Int, Sendable {
    case authRequired = -32001
    case sessionNotFound = -32002
}
