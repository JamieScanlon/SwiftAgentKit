//
//  MessageProcessor.swift
//  SwiftAgentKit
//

import Foundation

/// Processes outbound JSON-RPC payloads before sending (e.g. chunking for large messages).
public protocol OutboundMessageProcessor: Sendable {
    func processOutbound(_ data: Data) async throws -> [Data]
}

/// Processes inbound line data before JSON-RPC filtering (e.g. chunk reassembly).
public protocol InboundLineProcessor: Sendable {
    func processInboundLine(_ line: String) async throws -> [Data]?
}

/// Identity processor — passes messages through unchanged.
public struct IdentityOutboundMessageProcessor: OutboundMessageProcessor, Sendable {
    public init() {}

    public func processOutbound(_ data: Data) async throws -> [Data] {
        [NewlineDelimitedFraming.appendNewlineIfNeeded(data)]
    }
}
