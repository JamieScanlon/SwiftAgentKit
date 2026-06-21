//
//  ACPHTTPBridgeTransport.swift
//  SwiftAgentKitACP
//

import Foundation
import SwiftAgentKit
import os

/// Internal bidirectional transport bridging HTTP POST ingress and SSE egress for one ACP connection.
final class ACPHTTPBridgeTransport: @unchecked Sendable, JSONRPCTransport {
    private let inboundStream: AsyncThrowingStream<Data, Error>
    private let inboundContinuation: AsyncThrowingStream<Data, Error>.Continuation
    private let outboundHandler: @Sendable (Data) async -> Void
    private let stateLock = OSAllocatedUnfairLock(initialState: false)

    init(outboundHandler: @escaping @Sendable (Data) async -> Void) {
        self.outboundHandler = outboundHandler
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        self.inboundStream = AsyncThrowingStream { continuation = $0 }
        self.inboundContinuation = continuation
    }

    func connect() async throws {
        stateLock.withLock { $0 = true }
    }

    func disconnect() async {
        stateLock.withLock { $0 = false }
        inboundContinuation.finish()
    }

    func send(_ data: Data) async throws {
        let connected = stateLock.withLock { $0 }
        guard connected else { throw ACPRemoteTransportError.notConnected }
        await outboundHandler(data)
    }

    func receive() -> AsyncThrowingStream<Data, Error> {
        inboundStream
    }

    func ingest(_ data: Data) {
        inboundContinuation.yield(data)
    }
}
