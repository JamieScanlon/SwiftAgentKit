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
    /// to the message stream. Messages are filtered to remove log output
    /// that might interfere with the MCP protocol.
    private func readLoop() async {
        outPipe.fileHandleForReading.readabilityHandler = { pipeHandle in
            let data = pipeHandle.availableData
            self.logger.debug("Received raw data: \(String(data: data, encoding: .utf8) ?? "")")
            
            // Filter the message to remove log output
            // Note: We need to handle this synchronously since readabilityHandler is not async
            let messageString = String(data: data, encoding: .utf8) ?? ""
            let lines = messageString.components(separatedBy: .newlines)
            var validMessages: [String] = []
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty else { continue }
                
                // Check if this line is a valid JSON-RPC message
                if self.isValidJSONRPCMessage(trimmedLine) {
                    validMessages.append(trimmedLine)
                } else {
                    self.logger.debug("Filtered: \(trimmedLine)")
                }
            }
            
            // Yield valid messages if any
            if !validMessages.isEmpty {
                let filteredMessage = validMessages.joined(separator: "\n") + "\n"
                if let filteredData = filteredMessage.data(using: .utf8) {
                    self.logger.debug("Filtered data: \(String(data: filteredData, encoding: .utf8) ?? "")")
                    self.messageContinuation.yield(filteredData)
                }
            } else {
                self.logger.debug("Message filtered out (likely log output)")
            }
        }
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