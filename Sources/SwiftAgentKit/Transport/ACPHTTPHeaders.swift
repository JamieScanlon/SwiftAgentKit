//
//  ACPHTTPHeaders.swift
//  SwiftAgentKit
//

import Foundation

/// HTTP header names used by the ACP Streamable HTTP / WebSocket transport (draft RFD).
public enum ACPHTTPHeaders {
    public static let connectionId = "Acp-Connection-Id"
    public static let sessionId = "Acp-Session-Id"

    public static func validateConnectionId(_ value: String?) throws -> String {
        guard let value, !value.isEmpty else {
            throw ACPRemoteTransportError.missingConnectionId
        }
        return value
    }

    public static func validateSessionId(_ value: String?) throws -> String {
        guard let value, !value.isEmpty else {
            throw ACPRemoteTransportError.missingSessionId
        }
        return value
    }
}
