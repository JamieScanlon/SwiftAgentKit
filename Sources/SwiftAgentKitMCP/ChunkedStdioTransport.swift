//
//  ChunkedStdioTransport.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon
//

import Foundation
import Logging
import MCP
import System

/// A stdio transport that supports chunking large messages to work around pipe size limits
public actor ChunkedStdioTransport: Transport {
    public nonisolated let logger: Logger
    private let chunker: MessageChunker
    private var stdioTransport: MCP.StdioTransport
    private var isConnected = false
    
    // Stream for incoming messages
    private var messageStream: AsyncThrowingStream<Data, Swift.Error>?
    private var messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation?
    
    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "mcp.transport.chunked-stdio")
        self.chunker = MessageChunker(logger: self.logger)
        self.stdioTransport = MCP.StdioTransport()
    }
    
    /// Establishes connection with the transport
    public func connect() async throws {
        guard !isConnected else { return }
        
        // Create message stream
        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        messageStream = AsyncThrowingStream { continuation = $0 }
        messageContinuation = continuation
        
        // Connect the underlying stdio transport
        try await stdioTransport.connect()
        isConnected = true
        
        // Start reading and reassembling frames
        Task.detached {
            await self.readLoop()
        }
    }
    
    /// Disconnects from the transport
    public func disconnect() async {
        guard isConnected else { return }
        
        isConnected = false
        messageContinuation?.finish()
        await stdioTransport.disconnect()
        await chunker.clearBuffers()
        logger.info("Chunked stdio transport disconnected")
    }
    
    /// Sends data, chunking if necessary
    public func send(_ data: Data) async throws {
        guard isConnected else {
            throw MCPError.transportError(Errno(rawValue: ENOTCONN))
        }
        
        // Chunk the message
        let frames = await chunker.chunkMessage(data)
        
        // Send each frame
        for frame in frames {
            try await stdioTransport.send(frame)
        }
    }
    
    /// Receives data in an async sequence
    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        guard let stream = messageStream else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: MCPError.transportError(Errno(rawValue: ENOTCONN)))
            }
        }
        return stream
    }
    
    // MARK: - Private Methods
    
    /// Continuous loop that reads frames, reassembles them, and yields complete messages
    private func readLoop() async {
        guard let stream = await stdioTransport.receive() as AsyncThrowingStream<Data, Swift.Error>? else {
            logger.error("Failed to get receive stream from stdio transport")
            return
        }
        
        do {
            for try await frameData in stream {
                // Process the frame
                if let completeMessage = try await chunker.processFrame(frameData) {
                    // We have a complete message, yield it
                    await yieldMessage(completeMessage)
                }
                // If nil, we're still waiting for more chunks
            }
        } catch {
            logger.error("Error in read loop: \(error)")
            messageContinuation?.finish(throwing: error)
        }
    }
    
    /// Yield a complete message to the stream
    private func yieldMessage(_ message: Data) async {
        messageContinuation?.yield(message)
    }
}

