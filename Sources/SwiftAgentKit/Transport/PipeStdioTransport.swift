//
//  PipeStdioTransport.swift
//  SwiftAgentKit
//

import Foundation
import Logging
import os

/// Newline-delimited JSON-RPC transport over stdin/stdout pipes.
public final class PipeStdioTransport: JSONRPCTransport, @unchecked Sendable {
    private let inPipe: Pipe
    private let outPipe: Pipe
    private let messageFilter: JSONRPCMessageFilter
    private let outboundProcessor: any OutboundMessageProcessor
    private let inboundLineProcessor: (any InboundLineProcessor)?
    private let logger: Logging.Logger
    private let connectedState = OSAllocatedUnfairLock(initialState: false)
    private var messageStream: AsyncThrowingStream<Data, Error>!
    private var messageContinuation: AsyncThrowingStream<Data, Error>.Continuation!

    public init(
        inPipe: Pipe,
        outPipe: Pipe,
        messageFilter: JSONRPCMessageFilter = JSONRPCMessageFilter(),
        outboundProcessor: (any OutboundMessageProcessor)? = nil,
        inboundLineProcessor: (any InboundLineProcessor)? = nil,
        logger: Logging.Logger? = nil
    ) {
        self.inPipe = inPipe
        self.outPipe = outPipe
        self.messageFilter = messageFilter
        self.outboundProcessor = outboundProcessor ?? IdentityOutboundMessageProcessor()
        self.inboundLineProcessor = inboundLineProcessor
        self.logger = logger ?? SwiftAgentKitLogging.logger(for: .core("PipeStdioTransport"))
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
        guard isConnectedFlag() else { throw JSONRPCConnectionError.notConnected }
        let frames = try await outboundProcessor.processOutbound(data)
        for frame in frames {
            try inPipe.fileHandleForWriting.write(contentsOf: frame)
        }
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

            for lineData in NewlineDelimitedFraming.splitLines(from: &buffer) {
                await processLine(Data(lineData))
            }
        }
    }

    private func processLine(_ lineData: Data) async {
        guard let lineString = String(data: lineData, encoding: .utf8) else { return }
        let trimmed = lineString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let inboundLineProcessor {
            do {
                if let messages = try await inboundLineProcessor.processInboundLine(trimmed) {
                    for message in messages {
                        if let filtered = messageFilter.filterMessage(message) {
                            messageContinuation.yield(filtered)
                        }
                    }
                }
            } catch {
                logger.debug(
                    "Inbound line processor rejected line",
                    metadata: SwiftAgentKitLogging.metadata(("line", .string(trimmed)))
                )
            }
            return
        }

        if let filtered = messageFilter.filterMessage(lineData) {
            messageContinuation.yield(filtered)
        }
    }

    private func isConnectedFlag() -> Bool {
        connectedState.withLock { $0 }
    }
}
