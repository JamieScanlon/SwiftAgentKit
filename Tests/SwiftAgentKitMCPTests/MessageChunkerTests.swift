//
//  MessageChunkerTests.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon
//

import Testing
import Foundation
import Logging
@testable import SwiftAgentKitMCP

@Suite("MessageChunker Tests")
struct MessageChunkerTests {
    
    @Test("Small message doesn't get chunked")
    func testSmallMessage() async throws {
        let chunker = MessageChunker()
        let message = "Hello, World!".data(using: .utf8)!
        
        let frames = await chunker.chunkMessage(message)
        #expect(frames.count == 1)
    }
    
    @Test("Large message gets chunked")
    func testLargeMessage() async throws {
        let chunker = MessageChunker()
        
        // Create a message larger than the max chunk size
        let largeString = String(repeating: "A", count: MessageChunker.maxChunkSize * 2)
        let message = largeString.data(using: .utf8)!
        
        let frames = await chunker.chunkMessage(message)
        #expect(frames.count > 1)
    }
    
    @Test("Message reassembly works correctly")
    func testMessageReassembly() async throws {
        let chunker = MessageChunker()
        
        // Create a test message
        let originalMessage = "Test message content".data(using: .utf8)!
        
        // Chunk it
        let frames = await chunker.chunkMessage(originalMessage)
        
        // Process each frame and reassemble
        var reassembledMessage: Data?
        for frame in frames {
            if let message = try await chunker.processFrame(frame) {
                reassembledMessage = message
            }
        }
        
        #expect(reassembledMessage != nil)
        #expect(reassembledMessage == originalMessage)
    }
    
    @Test("Large message reassembly works correctly")
    func testLargeMessageReassembly() async throws {
        let chunker = MessageChunker()
        
        // Create a large message
        let largeString = String(repeating: "B", count: MessageChunker.maxChunkSize * 3)
        let originalMessage = largeString.data(using: .utf8)!
        
        // Chunk it
        let frames = await chunker.chunkMessage(originalMessage)
        #expect(frames.count > 1)
        
        // Process each frame and reassemble
        var reassembledMessage: Data?
        for frame in frames {
            if let message = try await chunker.processFrame(frame) {
                reassembledMessage = message
            }
        }
        
        #expect(reassembledMessage != nil)
        #expect(reassembledMessage == originalMessage)
    }
    
    @Test("Multiple messages can be processed independently")
    func testMultipleMessages() async throws {
        let chunker = MessageChunker()
        
        let message1 = "Message 1".data(using: .utf8)!
        let message2 = "Message 2".data(using: .utf8)!
        
        let frames1 = await chunker.chunkMessage(message1)
        let frames2 = await chunker.chunkMessage(message2)
        
        // Process frames from both messages (they should have different IDs)
        let result1 = try await chunker.processFrame(frames1[0])
        let result2 = try await chunker.processFrame(frames2[0])
        
        #expect(result1 == message1)
        #expect(result2 == message2)
    }
    
    @Test("Frame encoding and decoding")
    func testFrameEncoding() async throws {
        let chunker = MessageChunker()
        
        // Create a JSON-RPC message (typical use case)
        let jsonMessage = """
        {"jsonrpc":"2.0","method":"tools/list","id":1}
        """.data(using: .utf8)!
        
        let frames = await chunker.chunkMessage(jsonMessage)
        #expect(frames.count == 1)
        
        // Decode and verify
        let result = try await chunker.processFrame(frames[0])
        #expect(result == jsonMessage)
    }
}

