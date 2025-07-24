//
//  ClientTransport.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 5/17/25.
//

import Foundation
import Logging
import MCP
import System

actor ClientTransport: Transport {
    
    nonisolated let logger: Logging.Logger
    
    init(inPipe: Pipe, outPipe: Pipe, logger: Logging.Logger? = nil) {
        self.inPipe = inPipe
        self.outPipe = outPipe
        self.logger = logger ?? Logging.Logger(label: "mcp.transport.stdio")
        
        // Create message stream
        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        self.messageStream = AsyncThrowingStream { continuation = $0 }
        self.messageContinuation = continuation
    }
    
    /// Establishes connection with the transport
    func connect() async throws {
        guard !isConnected else { return }
        
        isConnected = true
        
        // Start reading loop in background
        Task.detached {
            await self.readLoop()
        }
    }
    
    /// Disconnects from the transport
    func disconnect() async {
        guard isConnected else { return }
        isConnected = false
        messageContinuation.finish()
        outPipe.fileHandleForReading.readabilityHandler = nil
        logger.info("Transport disconnected")
    }
    
    /// Sends data
    func send(_ data: Data) async throws {
        guard isConnected else {
            throw MCPError.transportError(Errno(rawValue: ENOTCONN))
        }
        
        // Add newline as delimiter
        var messageWithNewline = data
        messageWithNewline.append(UInt8(ascii: "\n"))
        try inPipe.fileHandleForWriting.write(contentsOf: messageWithNewline)
    }
    
    /// Receives data in an async sequence
    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        return messageStream
    }
    
    // MARK: - Private
    
    private var inPipe: Pipe
    private var outPipe: Pipe
    private var isConnected = false
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation
    
    /// Continuous loop that reads and processes incoming messages
    ///
    /// This method runs in the background while the transport is connected,
    /// parsing complete messages delimited by newlines and yielding them
    /// to the message stream.
    private func readLoop() async {
        outPipe.fileHandleForReading.readabilityHandler = { pipeHandle in
            let data = pipeHandle.availableData
            self.logger.debug("Received data: \(String(data: data, encoding: .utf8) ?? "")")
            self.messageContinuation.yield(data)
        }
    }
} 