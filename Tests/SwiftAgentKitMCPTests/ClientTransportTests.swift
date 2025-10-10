//
//  ClientTransportTests.swift
//  SwiftAgentKit
//
//  Tests for ClientTransport message filtering and chunking
//

import Testing
import Foundation
import Logging
@testable import SwiftAgentKitMCP

@Suite("ClientTransport Tests")
struct ClientTransportTests {
    
    // Helper actor to safely collect messages across tasks
    actor MessageCollector {
        var messages: [String] = []
        var count: Int { messages.count }
        
        func add(_ message: String) {
            messages.append(message)
        }
        
        func getMessages() -> [String] {
            messages
        }
    }
    
    @Test("Log messages are filtered without errors")
    func testLogMessagesFiltered() async throws {
        let inPipe = Pipe()
        let outPipe = Pipe()
        
        let transport = ClientTransport(inPipe: inPipe, outPipe: outPipe)
        try await transport.connect()
        
        // Write some log messages that should be filtered
        let logMessages = """
        Building for debugging...
        [0/1] Planning build
        Compiling module SwiftAgentKit
        Build complete!
        
        """
        
        if let data = logMessages.data(using: .utf8) {
            try outPipe.fileHandleForWriting.write(contentsOf: data)
        }
        
        // Give it a moment to process
        try await Task.sleep(for: .milliseconds(100))
        
        // The receive stream should not yield any messages for log output
        let collector = MessageCollector()
        let stream = await transport.receive()
        let receiveTask = Task {
            for try await messageData in stream {
                if let message = String(data: messageData, encoding: .utf8) {
                    await collector.add(message)
                }
            }
        }
        
        // Wait a bit and then cancel
        try await Task.sleep(for: .milliseconds(200))
        receiveTask.cancel()
        
        // Should not have received any messages (log messages filtered)
        let count = await collector.count
        #expect(count == 0)
        
        await transport.disconnect()
    }
    
    @Test("Valid JSON-RPC messages are processed")
    func testValidJSONRPCMessages() async throws {
        let inPipe = Pipe()
        let outPipe = Pipe()
        
        let transport = ClientTransport(inPipe: inPipe, outPipe: outPipe)
        try await transport.connect()
        
        // Write a valid JSON-RPC message
        let jsonRpcMessage = """
        {"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-client","version":"1.0"}}}
        
        """
        
        if let data = jsonRpcMessage.data(using: .utf8) {
            try outPipe.fileHandleForWriting.write(contentsOf: data)
        }
        
        // Collect received messages
        let collector = MessageCollector()
        let stream = await transport.receive()
        let receiveTask = Task {
            for try await messageData in stream {
                if let message = String(data: messageData, encoding: .utf8) {
                    await collector.add(message)
                }
                break // Only get first message
            }
        }
        
        // Wait for message to be received
        _ = await receiveTask.result
        
        // Should have received exactly one message
        let messages = await collector.getMessages()
        #expect(messages.count == 1)
        #expect(messages[0].contains("initialize"))
        
        await transport.disconnect()
    }
    
    @Test("Mixed log messages and JSON-RPC are handled correctly")
    func testMixedContent() async throws {
        let inPipe = Pipe()
        let outPipe = Pipe()
        
        let transport = ClientTransport(inPipe: inPipe, outPipe: outPipe)
        try await transport.connect()
        
        // Write mixed content: log messages and JSON-RPC
        let mixedContent = """
        Building for debugging...
        {"jsonrpc":"2.0","result":{"protocolVersion":"2024-11-05"},"id":1}
        [0/1] Planning build
        {"jsonrpc":"2.0","method":"tools/list","id":2}
        Build complete!
        
        """
        
        if let data = mixedContent.data(using: .utf8) {
            try outPipe.fileHandleForWriting.write(contentsOf: data)
        }
        
        // Collect received messages
        let collector = MessageCollector()
        let stream = await transport.receive()
        let receiveTask = Task {
            for try await messageData in stream {
                if let message = String(data: messageData, encoding: .utf8) {
                    await collector.add(message.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                let count = await collector.count
                if count >= 2 {
                    break
                }
            }
        }
        
        // Wait for messages to be received
        _ = await receiveTask.result
        
        // Should have received exactly 2 JSON-RPC messages (log messages filtered)
        let messages = await collector.getMessages()
        #expect(messages.count == 2)
        #expect(messages[0].contains("result"))
        #expect(messages[1].contains("tools/list"))
        
        await transport.disconnect()
    }
    
    @Test("Small messages are not chunked")
    func testSmallMessagesNotChunked() async throws {
        let inPipe = Pipe()
        let outPipe = Pipe()
        
        let transport = ClientTransport(inPipe: inPipe, outPipe: outPipe)
        try await transport.connect()
        
        // Small JSON-RPC message (should not be chunked)
        let smallMessage = """
        {"jsonrpc":"2.0","method":"test","id":1,"params":{"data":"small"}}
        
        """
        
        if let data = smallMessage.data(using: .utf8) {
            try outPipe.fileHandleForWriting.write(contentsOf: data)
        }
        
        // Collect received message
        let collector = MessageCollector()
        let stream = await transport.receive()
        let receiveTask = Task {
            for try await messageData in stream {
                let message = String(data: messageData, encoding: .utf8) ?? ""
                await collector.add(message)
                break
            }
        }
        
        _ = await receiveTask.result
        
        // Should receive the message as-is (not chunked)
        let messages = await collector.getMessages()
        #expect(messages.count == 1)
        #expect(messages[0].contains("small"))
        
        await transport.disconnect()
    }
    
    @Test("Frame format detection works correctly")
    func testFrameFormatDetection() async throws {
        let inPipe = Pipe()
        let outPipe = Pipe()
        
        let transport = ClientTransport(inPipe: inPipe, outPipe: outPipe)
        try await transport.connect()
        
        // Write a properly formatted frame
        let frame = """
        a1b2c3d4-e5f6-7890-abcd-ef1234567890:0:1:{"jsonrpc":"2.0","method":"test"}
        
        """
        
        if let data = frame.data(using: .utf8) {
            try outPipe.fileHandleForWriting.write(contentsOf: data)
        }
        
        // Collect received message
        let collector = MessageCollector()
        let stream = await transport.receive()
        let receiveTask = Task {
            for try await messageData in stream {
                let message = String(data: messageData, encoding: .utf8) ?? ""
                await collector.add(message)
                break
            }
        }
        
        _ = await receiveTask.result
        
        // Should receive the reassembled message
        let messages = await collector.getMessages()
        #expect(messages.count == 1)
        #expect(messages[0].contains("test"))
        // Should NOT contain the frame header
        #expect(!messages[0].contains("a1b2c3d4"))
        
        await transport.disconnect()
    }
    
    @Test("Invalid frame format is filtered as log")
    func testInvalidFrameFormat() async throws {
        let inPipe = Pipe()
        let outPipe = Pipe()
        
        let transport = ClientTransport(inPipe: inPipe, outPipe: outPipe)
        try await transport.connect()
        
        // Write something that looks like it could be a frame but isn't valid
        let invalidFrame = """
        not:a:valid:frame:format
        this:is:not:a:frame
        1234:abc:def:data
        
        """
        
        if let data = invalidFrame.data(using: .utf8) {
            try outPipe.fileHandleForWriting.write(contentsOf: data)
        }
        
        // Give it time to process
        try await Task.sleep(for: .milliseconds(100))
        
        // Should not receive any messages (filtered as log output)
        let collector = MessageCollector()
        let stream = await transport.receive()
        let receiveTask = Task {
            for try await messageData in stream {
                let message = String(data: messageData, encoding: .utf8) ?? ""
                await collector.add(message)
            }
        }
        
        try await Task.sleep(for: .milliseconds(200))
        receiveTask.cancel()
        
        let count = await collector.count
        #expect(count == 0)
        
        await transport.disconnect()
    }
    
    @Test("Multi-chunk messages are reassembled correctly")
    func testMultiChunkReassembly() async throws {
        let inPipe = Pipe()
        let outPipe = Pipe()
        
        let transport = ClientTransport(inPipe: inPipe, outPipe: outPipe)
        try await transport.connect()
        
        // Create a message that will be split into multiple chunks
        let messageId = "test-msg-12345"
        let part1 = "{\"jsonrpc\":\"2.0\",\"method\":\"test\","
        let part2 = "\"params\":{\"data\":\"split\"}}"
        
        let frame1 = "\(messageId):0:2:\(part1)\n"
        let frame2 = "\(messageId):1:2:\(part2)\n"
        
        // Write frames
        if let data1 = frame1.data(using: .utf8) {
            try outPipe.fileHandleForWriting.write(contentsOf: data1)
        }
        
        try await Task.sleep(for: .milliseconds(50))
        
        if let data2 = frame2.data(using: .utf8) {
            try outPipe.fileHandleForWriting.write(contentsOf: data2)
        }
        
        // Collect received message
        let collector = MessageCollector()
        let stream = await transport.receive()
        let receiveTask = Task {
            for try await messageData in stream {
                let message = String(data: messageData, encoding: .utf8) ?? ""
                await collector.add(message)
                break
            }
        }
        
        _ = await receiveTask.result
        
        // Should receive the complete reassembled message
        let messages = await collector.getMessages()
        #expect(messages.count == 1)
        let trimmed = messages[0].trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.contains("jsonrpc"))
        #expect(trimmed.contains("test"))
        #expect(trimmed.contains("split"))
        
        await transport.disconnect()
    }
    
    @Test("Chunking with interleaved log messages")
    func testChunkingWithInterleavedLogs() async throws {
        let inPipe = Pipe()
        let outPipe = Pipe()
        
        let transport = ClientTransport(inPipe: inPipe, outPipe: outPipe)
        try await transport.connect()
        
        // Create chunked message with log messages in between
        let messageId = "test-msg-67890"
        let part1 = "{\"jsonrpc\":\"2.0\","
        let part2 = "\"result\":true}"
        
        let mixedContent = """
        Building...
        \(messageId):0:2:\(part1)
        Compiling...
        \(messageId):1:2:\(part2)
        Done!
        
        """
        
        if let data = mixedContent.data(using: .utf8) {
            try outPipe.fileHandleForWriting.write(contentsOf: data)
        }
        
        // Collect received messages
        let collector = MessageCollector()
        let stream = await transport.receive()
        let receiveTask = Task {
            for try await messageData in stream {
                if let message = String(data: messageData, encoding: .utf8) {
                    await collector.add(message.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                let count = await collector.count
                if count >= 1 {
                    break
                }
            }
        }
        
        _ = await receiveTask.result
        
        // Should receive exactly 1 reassembled JSON-RPC message (logs filtered)
        let messages = await collector.getMessages()
        #expect(messages.count == 1)
        #expect(messages[0].contains("result"))
        #expect(messages[0].contains("true"))
        // Should not contain log messages
        #expect(!messages[0].contains("Building"))
        #expect(!messages[0].contains("Done"))
        
        await transport.disconnect()
    }
}

