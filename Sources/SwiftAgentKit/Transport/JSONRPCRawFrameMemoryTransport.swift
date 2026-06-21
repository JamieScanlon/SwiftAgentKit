//
//  JSONRPCRawFrameMemoryTransport.swift
//  SwiftAgentKit
//

import Foundation

/// In-process paired transport using raw JSON-RPC frames (WebSocket-style, no newlines).
public final class JSONRPCRawFrameMemoryTransport: JSONRPCTransport, ACPFramedJSONRPCTransport, @unchecked Sendable {
    public let jsonRPCFraming: JSONRPCFraming = .rawFrame

    private weak var peer: JSONRPCRawFrameMemoryTransport?
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private let stream: AsyncThrowingStream<Data, Error>
    private var connected = false

    private init(peer: JSONRPCRawFrameMemoryTransport?) {
        self.peer = peer
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        self.stream = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    public static func paired() -> (JSONRPCRawFrameMemoryTransport, JSONRPCRawFrameMemoryTransport) {
        let left = JSONRPCRawFrameMemoryTransport(peer: nil)
        let right = JSONRPCRawFrameMemoryTransport(peer: nil)
        left.peer = right
        right.peer = left
        return (left, right)
    }

    public func connect() async throws {
        connected = true
    }

    public func disconnect() async {
        connected = false
        continuation?.finish()
        continuation = nil
    }

    public func send(_ data: Data) async throws {
        guard connected, let peer else { throw JSONRPCConnectionError.notConnected }
        let frame = data.last == UInt8(ascii: "\n") ? Data(data.dropLast()) : data
        peer.continuation?.yield(frame)
    }

    public func receive() -> AsyncThrowingStream<Data, Error> {
        stream
    }
}
