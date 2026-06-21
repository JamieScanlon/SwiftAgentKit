//
//  JSONRPCMemoryTransport.swift
//  SwiftAgentKit
//

import Foundation

/// In-memory transport for tests — paired read/write ends.
public final class JSONRPCMemoryTransport: JSONRPCTransport, @unchecked Sendable {
    private let outbound: AsyncStream<Data>.Continuation
    private let inbound: AsyncThrowingStream<Data, Error>
    private var peer: JSONRPCMemoryTransport?
    private var connected = false
    private var inboundContinuation: AsyncThrowingStream<Data, Error>.Continuation

    public init() {
        var inboundContinuation: AsyncThrowingStream<Data, Error>.Continuation!
        inbound = AsyncThrowingStream { inboundContinuation = $0 }
        var outboundContinuation: AsyncStream<Data>.Continuation!
        _ = AsyncStream<Data> { outboundContinuation = $0 }
        outbound = outboundContinuation
        self.inboundContinuation = inboundContinuation
    }

    public static func paired() -> (JSONRPCMemoryTransport, JSONRPCMemoryTransport) {
        let a = JSONRPCMemoryTransport()
        let b = JSONRPCMemoryTransport()
        a.peer = b
        b.peer = a
        return (a, b)
    }

    public func connect() async throws {
        connected = true
    }

    public func disconnect() async {
        connected = false
        inboundContinuation.finish()
    }

    public func send(_ data: Data) async throws {
        guard connected, let peer else { throw JSONRPCConnectionError.notConnected }
        peer.inboundContinuation.yield(data)
    }

    public func receive() -> AsyncThrowingStream<Data, Error> {
        inbound
    }
}
