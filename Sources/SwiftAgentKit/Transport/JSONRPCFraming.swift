//
//  JSONRPCFraming.swift
//  SwiftAgentKit
//

import Foundation

/// How JSON-RPC messages are framed on the wire.
public enum JSONRPCFraming: Sendable {
    /// Newline-delimited messages (stdio transport).
    case newlineDelimited
    /// One JSON-RPC message per frame with no delimiter (WebSocket transport).
    case rawFrame
}

/// Transports that use non-default JSON-RPC framing.
public protocol ACPFramedJSONRPCTransport: JSONRPCTransport {
    var jsonRPCFraming: JSONRPCFraming { get }
}

public extension JSONRPCTransport {
    var jsonRPCFraming: JSONRPCFraming {
        if let framed = self as? any ACPFramedJSONRPCTransport {
            return framed.jsonRPCFraming
        }
        return .newlineDelimited
    }
}
