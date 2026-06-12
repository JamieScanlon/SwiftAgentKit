//
//  ACPStdioTransport.swift
//  SwiftAgentKitACP
//

import Foundation
import Logging
import SwiftAgentKit
import os

/// Newline-delimited JSON-RPC transport over stdin/stdout pipes.
public final class ACPStdioTransport: ACPTransport, @unchecked Sendable {
    private let inPipe: Pipe
    private let outPipe: Pipe
    private let messageFilter: ACPMessageFilter
    private let logger: Logging.Logger
    private let connectedState = OSAllocatedUnfairLock(initialState: false)
    private var messageStream: AsyncThrowingStream<Data, Error>!
    private var messageContinuation: AsyncThrowingStream<Data, Error>.Continuation!

    public init(
        inPipe: Pipe,
        outPipe: Pipe,
        messageFilter: ACPMessageFilter = ACPMessageFilter(),
        logger: Logging.Logger? = nil
    ) {
        self.inPipe = inPipe
        self.outPipe = outPipe
        self.messageFilter = messageFilter
        self.logger = logger ?? SwiftAgentKitLogging.logger(for: .acp("ACPStdioTransport"))
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        self.messageStream = AsyncThrowingStream { continuation = $0 }
        self.messageContinuation = continuation
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
        outPipe.fileHandleForReading.readabilityHandler = nil
        messageContinuation.finish()
    }

    public func send(_ data: Data) async throws {
        guard isConnectedFlag() else { throw ACPConnectionError.notConnected }
        var payload = data
        if payload.last != UInt8(ascii: "\n") {
            payload.append(UInt8(ascii: "\n"))
        }
        try inPipe.fileHandleForWriting.write(contentsOf: payload)
    }

    public func receive() -> AsyncThrowingStream<Data, Error> {
        messageStream
    }

    private func readLoop() async {
        let handle = outPipe.fileHandleForReading
        var buffer = Data()

        while isConnectedFlag() {
            let chunk = handle.availableData
            if chunk.isEmpty {
                try? await Task.sleep(for: .milliseconds(10))
                continue
            }
            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[..<newlineIndex]
                buffer = buffer[(newlineIndex + 1)...]

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
