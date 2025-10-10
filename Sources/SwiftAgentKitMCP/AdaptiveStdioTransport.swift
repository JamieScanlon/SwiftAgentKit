//
//  AdaptiveStdioTransport.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon
//

import Foundation
import Logging
import MCP
import System

/// An adaptive stdio transport that automatically handles both plain JSON-RPC and chunked messages
/// 
/// This transport provides transparent support for:
/// - Small messages: Sent as plain JSON-RPC for compatibility
/// - Large messages (>60KB): Automatically chunked to avoid macOS 64KB pipe limit
/// - Mixed receive: Handles both plain and chunked messages from peers
/// - Capability negotiation: Advertises chunking support via MCP experimental capabilities
public actor AdaptiveStdioTransport: Transport {
    public nonisolated let logger: Logger
    private let chunker: MessageChunker
    private var stdioTransport: MCP.StdioTransport
    private var isConnected = false
    
    // Stream for incoming messages
    private var messageStream: AsyncThrowingStream<Data, Swift.Error>?
    private var messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation?
    
    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "mcp.transport.adaptive-stdio")
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
        logger.info("Adaptive stdio transport disconnected")
    }
    
    /// Sends data, chunking only if necessary for large messages
    public func send(_ data: Data) async throws {
        guard isConnected else {
            throw MCPError.transportError(Errno(rawValue: ENOTCONN))
        }
        
        // Only chunk if message is large enough to need it
        // For compatibility, send small messages directly
        let maxDirectSize = MessageChunker.maxChunkSize - 100 // Leave room for overhead
        
        if data.count <= maxDirectSize {
            // Send directly without chunking overhead
            try await stdioTransport.send(data)
        } else {
            // Message is large, use chunking
            let frames = await chunker.chunkMessage(data)
            for frame in frames {
                try await stdioTransport.send(frame)
            }
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
    
    /// Continuous loop that reads messages, handling both plain JSON-RPC and chunked frames
    private func readLoop() async {
        guard let stream = await stdioTransport.receive() as AsyncThrowingStream<Data, Swift.Error>? else {
            logger.error("Failed to get receive stream from stdio transport")
            return
        }
        
        do {
            for try await messageData in stream {
                // Try to determine if this is a chunked frame or plain JSON-RPC
                guard let messageString = String(data: messageData, encoding: .utf8) else {
                    logger.debug("Unable to decode message data")
                    continue
                }
                
                let trimmed = messageString.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                
                // Check if this looks like a frame (has messageId:index:total: format)
                if isFrameFormat(trimmed) {
                    // Process as a chunked frame
                    do {
                        if let completeMessage = try await chunker.processFrame(messageData) {
                            // We have a complete reassembled message, yield it
                            await yieldMessage(completeMessage)
                        }
                        // If nil, we're still waiting for more chunks
                    } catch {
                        logger.debug("Not a valid frame: \(error)")
                    }
                } else {
                    // This is a plain JSON-RPC message (not chunked), yield it directly
                    await yieldMessage(messageData)
                }
            }
        } catch {
            logger.error("Error in read loop: \(error)")
            messageContinuation?.finish(throwing: error)
        }
    }
    
    /// Check if a line matches the frame format (messageId:index:total:...)
    private func isFrameFormat(_ line: String) -> Bool {
        let components = line.components(separatedBy: ":")
        // Frame format: messageId:chunkIndex:totalChunks:data
        // Need at least 4 components, and components 1 and 2 should be numbers
        guard components.count >= 4,
              let _ = Int(components[1]),
              let _ = Int(components[2]) else {
            return false
        }
        return true
    }
    
    /// Yield a complete message to the stream
    private func yieldMessage(_ message: Data) async {
        messageContinuation?.yield(message)
    }
}

