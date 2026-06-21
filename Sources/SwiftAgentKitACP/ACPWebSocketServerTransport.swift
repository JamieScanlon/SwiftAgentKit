//
//  ACPWebSocketServerTransport.swift
//  SwiftAgentKitACP
//

import Foundation
import Logging
import SwiftAgentKit
import Vapor
import os

/// Bridges a Vapor WebSocket to ``JSONRPCTransport`` for the ACP agent server role.
public final class ACPWebSocketServerTransport: @unchecked Sendable, ACPFramedJSONRPCTransport, ACPRemoteTransportContext {
    public let jsonRPCFraming: JSONRPCFraming = .rawFrame
    public let connectionId: String

    private let socket: WebSocket
    private let inboundStream: AsyncThrowingStream<Data, Error>
    private let inboundContinuation: AsyncThrowingStream<Data, Error>.Continuation
    private let stateLock = OSAllocatedUnfairLock(initialState: TransportState())

    private struct TransportState: Sendable {
        var connected = false
        var sessionId: String?
    }

    public init(socket: WebSocket, connectionId: String) {
        self.socket = socket
        self.connectionId = connectionId
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        self.inboundStream = AsyncThrowingStream { continuation = $0 }
        self.inboundContinuation = continuation

        socket.onText { _, text in
            if let data = text.data(using: .utf8) {
                continuation.yield(data)
            }
        }
        socket.onClose.whenComplete { _ in
            continuation.finish()
        }
    }

    public func connect() async throws {
        stateLock.withLock { $0.connected = true }
    }

    public func disconnect() async {
        stateLock.withLock { $0.connected = false }
        socket.close(promise: nil)
        inboundContinuation.finish()
    }

    public func send(_ data: Data) async throws {
        let isConnected = stateLock.withLock { $0.connected }
        guard isConnected else { throw ACPRemoteTransportError.notConnected }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
        try await socket.send(text)
    }

    public func receive() -> AsyncThrowingStream<Data, Error> {
        inboundStream
    }

    public func setConnectionId(_ connectionId: String?) async {}

    public func setSessionId(_ sessionId: String?) async {
        stateLock.withLock { $0.sessionId = sessionId }
    }

    public func connectionId() async -> String? {
        connectionId
    }

    public func sessionId() async -> String? {
        stateLock.withLock { $0.sessionId }
    }
}
