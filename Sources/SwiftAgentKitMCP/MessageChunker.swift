//
//  MessageChunker.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon
//

import Foundation
import Logging
import SwiftAgentKit

/// Handles chunking and reassembly of large messages to work around pipe size limits
public actor MessageChunker {
    private let logger: Logger
    
    // Maximum size for a single chunk (conservative limit for macOS pipes)
    // Using 60KB to leave room for framing overhead
    public static let maxChunkSize = 60 * 1024
    
    // Frame format: {messageId}:{chunkIndex}:{totalChunks}:{data}\n
    private struct Frame {
        let messageId: String
        let chunkIndex: Int
        let totalChunks: Int
        let data: Data
        
        func encode() -> Data {
            let header = "\(messageId):\(chunkIndex):\(totalChunks):"
            var frameData = Data(header.utf8)
            frameData.append(data)
            frameData.append(UInt8(ascii: "\n"))
            return frameData
        }
        
        static func decode(_ data: Data) -> Frame? {
            guard let string = String(data: data, encoding: .utf8) else {
                return nil
            }
            
            // Remove trailing newline if present
            let trimmed = string.trimmingCharacters(in: .newlines)
            
            // Parse header: messageId:chunkIndex:totalChunks:data
            let components = trimmed.components(separatedBy: ":")
            guard components.count >= 4 else {
                return nil
            }
            
            let messageId = components[0]
            guard let chunkIndex = Int(components[1]),
                  let totalChunks = Int(components[2]) else {
                return nil
            }
            
            // The data is everything after the third colon
            let headerLength = messageId.utf8.count + 1 + components[1].utf8.count + 1 + components[2].utf8.count + 1
            let dataStartIndex = data.index(data.startIndex, offsetBy: headerLength)
            var payloadData = data[dataStartIndex...]
            
            // Remove trailing newline if present
            if payloadData.last == UInt8(ascii: "\n") {
                payloadData = payloadData.dropLast()
            }
            
            return Frame(
                messageId: messageId,
                chunkIndex: chunkIndex,
                totalChunks: totalChunks,
                data: Data(payloadData)
            )
        }
    }
    
    // Storage for reassembling chunked messages
    private var messageBuffers: [String: [Int: Data]] = [:]
    
    public init(logger: Logger? = nil) {
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .mcp("MessageChunker")
        )
    }
    
    /// Chunk a message into multiple frames if it exceeds the maximum chunk size
    /// - Parameter message: The complete message data to chunk
    /// - Returns: Array of framed data chunks
    public func chunkMessage(_ message: Data) -> [Data] {
        // Check if the message fits in a single frame
        let messageId = UUID().uuidString
        
        // Account for frame overhead in size calculation
        let headerOverhead = messageId.utf8.count + 20 // Rough estimate for ":0:1:" plus newline
        let effectiveMaxSize = Self.maxChunkSize - headerOverhead
        
        if message.count <= effectiveMaxSize {
            // Single frame
            let frame = Frame(messageId: messageId, chunkIndex: 0, totalChunks: 1, data: message)
            return [frame.encode()]
        }
        
        // Split into multiple frames
        let totalChunks = (message.count + effectiveMaxSize - 1) / effectiveMaxSize
        var frames: [Data] = []
        
        for chunkIndex in 0..<totalChunks {
            let start = chunkIndex * effectiveMaxSize
            let end = min(start + effectiveMaxSize, message.count)
            let chunkData = message[start..<end]
            
            let frame = Frame(
                messageId: messageId,
                chunkIndex: chunkIndex,
                totalChunks: totalChunks,
                data: Data(chunkData)
            )
            frames.append(frame.encode())
        }
        
        logger.info(
            "Chunked message",
            metadata: SwiftAgentKitLogging.metadata(
                ("frames", .stringConvertible(totalChunks)),
                ("bytes", .stringConvertible(message.count))
            )
        )
        return frames
    }
    
    /// Process a received frame and return the complete message if all chunks have been received
    /// - Parameter frameData: The frame data to process
    /// - Returns: The complete message if all chunks have been received, nil otherwise
    public func processFrame(_ frameData: Data) throws -> Data? {
        guard let frame = Frame.decode(frameData) else {
            throw ChunkerError.invalidFrame
        }
        
        // Single frame message
        if frame.totalChunks == 1 {
            return frame.data
        }
        
        // Multi-frame message - store the chunk
        var buffer = messageBuffers[frame.messageId] ?? [:]
        buffer[frame.chunkIndex] = frame.data
        messageBuffers[frame.messageId] = buffer
        
        // Check if we have all chunks
        if buffer.count == frame.totalChunks {
            // Reassemble the complete message
            var completeMessage = Data()
            for index in 0..<frame.totalChunks {
                guard let chunkData = buffer[index] else {
                    throw ChunkerError.missingChunk(frame.messageId, index)
                }
                completeMessage.append(chunkData)
            }
            
            // Clean up the buffer
            messageBuffers.removeValue(forKey: frame.messageId)
            
            logger.info(
                "Reassembled message",
                metadata: SwiftAgentKitLogging.metadata(
                    ("frames", .stringConvertible(frame.totalChunks)),
                    ("bytes", .stringConvertible(completeMessage.count)),
                    ("messageId", .string(frame.messageId))
                )
            )
            return completeMessage
        }
        
        // Still waiting for more chunks
        logger.debug(
            "Received chunk",
            metadata: SwiftAgentKitLogging.metadata(
                ("messageId", .string(frame.messageId)),
                ("chunkIndex", .stringConvertible(frame.chunkIndex)),
                ("totalChunks", .stringConvertible(frame.totalChunks))
            )
        )
        return nil
    }
    
    /// Clear any incomplete message buffers (useful for cleanup on error)
    public func clearBuffers() {
        messageBuffers.removeAll()
    }
}

public enum ChunkerError: LocalizedError {
    case invalidFrame
    case missingChunk(String, Int)
    
    public var errorDescription: String? {
        switch self {
        case .invalidFrame:
            return "Invalid frame format"
        case .missingChunk(let messageId, let index):
            return "Missing chunk \(index) for message \(messageId)"
        }
    }
}

