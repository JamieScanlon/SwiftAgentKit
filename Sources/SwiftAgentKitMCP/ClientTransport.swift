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
    private let chunker: MessageChunker
    
    init(inPipe: Pipe, outPipe: Pipe, logger: Logging.Logger? = nil) {
        self.inPipe = inPipe
        self.outPipe = outPipe
        self.logger = logger ?? Logging.Logger(label: "mcp.transport.stdio")
        self.chunker = MessageChunker(logger: self.logger)
        
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
        await chunker.clearBuffers()
        logger.info("Transport disconnected")
    }
    
    /// Sends data, chunking if necessary
    func send(_ data: Data) async throws {
        guard isConnected else {
            throw MCPError.transportError(Errno(rawValue: ENOTCONN))
        }
        
        // Chunk the message
        let frames = await chunker.chunkMessage(data)
        
        // Send each frame
        for frame in frames {
            try inPipe.fileHandleForWriting.write(contentsOf: frame)
        }
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
    private var buffer = Data() // Buffer for incoming data
    
    /// Continuous loop that reads and processes incoming frames
    ///
    /// This method runs in the background while the transport is connected,
    /// reading frames, reassembling chunked messages, and yielding complete
    /// messages to the stream. Messages are filtered to remove log output
    /// that might interfere with the MCP protocol.
    private func readLoop() async {
        outPipe.fileHandleForReading.readabilityHandler = { pipeHandle in
            let data = pipeHandle.availableData
            guard !data.isEmpty else { return }
            
            // Process the received data in an actor-isolated context
            Task {
                await self.processReceivedData(data)
            }
        }
    }
    
    /// Process received data in an actor-isolated context
    private func processReceivedData(_ data: Data) async {
        buffer.append(data)
        
        // Process complete lines (delimited by newlines)
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            
            guard let lineString = String(data: lineData, encoding: .utf8) else {
                logger.debug("Unable to decode line data")
                continue
            }
            
            let trimmedLine = lineString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            
            // First check if this is a valid JSON-RPC message (non-chunked)
            if isValidJSONRPCMessage(trimmedLine) {
                // This is a complete JSON-RPC message, yield it directly
                let messageWithNewline = trimmedLine + "\n"
                if let messageData = messageWithNewline.data(using: .utf8) {
                    logger.debug("Yielding non-chunked message: \(trimmedLine)")
                    messageContinuation.yield(messageData)
                }
                continue
            }
            
            // Check if this looks like a frame (has the messageId:index:total: format)
            if isFrameFormat(trimmedLine) {
                // Try to process as a chunked frame
                do {
                    let frameData = Data(lineData) + Data([UInt8(ascii: "\n")])
                    if let completeMessage = try await chunker.processFrame(frameData) {
                        // We have a complete reassembled message
                        // Filter it to ensure it's valid JSON-RPC
                        let messageString = String(data: completeMessage, encoding: .utf8) ?? ""
                        let lines = messageString.components(separatedBy: .newlines)
                        var validMessages: [String] = []
                        
                        for line in lines {
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { continue }
                            
                            if isValidJSONRPCMessage(trimmed) {
                                validMessages.append(trimmed)
                            } else {
                                logger.debug("Filtered from reassembled message: \(trimmed)")
                            }
                        }
                        
                        // Yield valid messages if any
                        if !validMessages.isEmpty {
                            let filteredMessage = validMessages.joined(separator: "\n") + "\n"
                            if let filteredData = filteredMessage.data(using: .utf8) {
                                logger.debug("Yielding reassembled message: \(validMessages.count) line(s)")
                                messageContinuation.yield(filteredData)
                            }
                        }
                    }
                    // If nil, we're still waiting for more chunks
                } catch {
                    logger.debug("Not a valid frame, likely log output: \(trimmedLine)")
                }
            } else {
                // Not a JSON-RPC message and not a frame format - filter as log output
                logger.debug("Filtered log message: \(trimmedLine)")
            }
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
    
    /// Validates if a string is a valid JSON-RPC message
    /// - Parameter message: The message string to validate
    /// - Returns: True if the message is valid JSON-RPC, false otherwise
    nonisolated private func isValidJSONRPCMessage(_ message: String) -> Bool {
        // First, check if it's valid JSON
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        
        // Check for required JSON-RPC fields
        guard let jsonrpc = json["jsonrpc"] as? String,
              jsonrpc == "2.0" else {
            return false
        }
        
        // Check if it has either method (request) or result/error (response)
        let hasMethod = json["method"] != nil
        let hasResult = json["result"] != nil
        let hasError = json["error"] != nil
        
        // Must have either method (for requests) or result/error (for responses)
        return hasMethod || hasResult || hasError
    }
} 