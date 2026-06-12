//
//  ProcessStdioTransport.swift
//  SwiftAgentKit
//

import Foundation
import os

/// Stdio transport for agent process — reads stdin, writes stdout.
public final class ProcessStdioTransport: JSONRPCTransport, @unchecked Sendable {
    private let connectedState = OSAllocatedUnfairLock(initialState: false)
    private var messageStream: AsyncThrowingStream<Data, Error>!
    private var messageContinuation: AsyncThrowingStream<Data, Error>.Continuation!
    private let messageFilter: JSONRPCMessageFilter

    public init(messageFilter: JSONRPCMessageFilter = JSONRPCMessageFilter()) {
        self.messageFilter = messageFilter
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        messageStream = AsyncThrowingStream { continuation = $0 }
        messageContinuation = continuation
    }

    public func connect() async throws {
        let alreadyConnected = connectedState.withLock { state -> Bool in
            if state { return true }
            state = true
            return false
        }
        guard !alreadyConnected else { return }
        Task.detached { [weak self] in
            await self?.readLoop()
        }
    }

    public func disconnect() async {
        connectedState.withLock { $0 = false }
        messageContinuation.finish()
    }

    public func send(_ data: Data) async throws {
        guard isConnectedFlag() else { throw JSONRPCConnectionError.notConnected }
        let payload = NewlineDelimitedFraming.appendNewlineIfNeeded(data)
        FileHandle.standardOutput.write(payload)
    }

    public func receive() -> AsyncThrowingStream<Data, Error> {
        messageStream
    }

    private func readLoop() async {
        let handle = FileHandle.standardInput
        var buffer = Data()
        while isConnectedFlag() {
            let chunk = handle.availableData
            if chunk.isEmpty {
                try? await Task.sleep(for: .milliseconds(10))
                continue
            }
            buffer.append(chunk)
            for lineData in NewlineDelimitedFraming.splitLines(from: &buffer) {
                if let filtered = messageFilter.filterMessage(Data(lineData)) {
                    messageContinuation.yield(filtered)
                }
            }
        }
    }

    private func isConnectedFlag() -> Bool {
        connectedState.withLock { $0 }
    }
}
