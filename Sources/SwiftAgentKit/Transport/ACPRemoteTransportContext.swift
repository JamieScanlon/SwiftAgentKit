//
//  ACPRemoteTransportContext.swift
//  SwiftAgentKit
//

import Foundation

/// Remote ACP transports that track connection and session identity headers.
public protocol ACPRemoteTransportContext: JSONRPCTransport {
    func setConnectionId(_ connectionId: String?) async
    func setSessionId(_ sessionId: String?) async
    func connectionId() async -> String?
    func sessionId() async -> String?
}

public extension ACPRemoteTransportContext {
    func setConnectionId(_ connectionId: String?) async {}
    func setSessionId(_ sessionId: String?) async {}
    func connectionId() async -> String? { nil }
    func sessionId() async -> String? { nil }
}
