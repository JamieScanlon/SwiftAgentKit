//
//  ServerTransport.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 4/12/25.
//

import Foundation
import Logging
import MCP
import System

/// Transport layer for MCP servers using stdio
/// Based on the successful ClientTransport approach using Pipes and readabilityHandler
public actor ServerTransport: MCP.Transport {
    private let internalLogger = Logger(label: "ServerTransport")
    
    // MARK: - State
    private var isConnected = false
    private var messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation?
    
    // MARK: - Pipes (like ClientTransport)
    private let inPipe: Pipe
    private let outPipe: Pipe
    
    public init() {
        // Create pipes for stdin/stdout communication
        // For server mode, we'll read from stdin and write to stdout directly
        self.inPipe = Pipe()
        self.outPipe = Pipe()
    }
    
    // MARK: - MCP Transport Implementation
    
    public var logger: Logger {
        return internalLogger
    }
    
    public func connect() async throws {
        guard !isConnected else {
            throw ServerTransportError.alreadyConnected
        }
        
        internalLogger.info("ServerTransport connecting...")
        isConnected = true
        
        // Start reading loop in background
        Task.detached {
            await self.readLoop()
        }
        
        internalLogger.info("ServerTransport connected and reading loop started")
    }
    
    public func disconnect() async {
        guard isConnected else { return }
        
        internalLogger.info("ServerTransport disconnecting...")
        isConnected = false
        
        // Stop the readability handler
        outPipe.fileHandleForReading.readabilityHandler = nil
        
        // Finish the message continuation
        messageContinuation?.finish()
        
        internalLogger.info("ServerTransport disconnected")
    }
    
    public func send(_ data: Data) async throws {
        guard isConnected else {
            throw ServerTransportError.notConnected
        }
        
        internalLogger.debug("ServerTransport sending \(data.count) bytes")
        
        // Write directly to stdout
        try FileHandle.standardOutput.write(contentsOf: data)
        try FileHandle.standardOutput.synchronize()
        
        internalLogger.debug("ServerTransport sent data successfully")
    }
    
    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        internalLogger.debug("ServerTransport creating receive stream")
        
        return AsyncThrowingStream { continuation in
            self.messageContinuation = continuation
            internalLogger.debug("ServerTransport receive stream created")
        }
    }
    
    // MARK: - Private Methods
    
    /// Continuous loop that reads and processes incoming messages
    private func readLoop() async {
        internalLogger.debug("Starting readLoop in background")
        
        // Use readabilityHandler approach like ClientTransport for better reliability
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            
            let data = handle.availableData
            if !data.isEmpty {
                self.internalLogger.info("Received data: \(data.count) bytes")
                
                // Try to parse as JSON to detect message type
                if let jsonString = String(data: data, encoding: .utf8) {
                    self.internalLogger.debug("Raw message: \(jsonString)")
                    
                    // Check if this looks like a JSON-RPC message
                    if jsonString.contains("\"jsonrpc\"") {
                        self.internalLogger.info("Detected JSON-RPC message")
                        
                        // Try to extract method name for better logging
                        if let methodRange = jsonString.range(of: "\"method\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
                            let methodString = String(jsonString[methodRange])
                            self.internalLogger.info("Message method: \(methodString)")
                        }
                    }
                }
                
                // Yield the data to the continuation - use async task to handle actor isolation
                Task.detached {
                    await self.yieldData(data)
                }
            }
        }
        
        // Keep the loop alive while connected
        while isConnected {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        internalLogger.debug("ReadLoop finished")
    }
    
    /// Helper method to yield data to the continuation (actor-isolated)
    private func yieldData(_ data: Data) {
        messageContinuation?.yield(data)
        internalLogger.debug("Successfully yielded data to continuation")
    }
}

// MARK: - Error Types

public enum ServerTransportError: LocalizedError {
    case alreadyConnected
    case notConnected
    case encodingError
    case decodingError
    
    public var errorDescription: String? {
        switch self {
        case .alreadyConnected:
            return "ServerTransport is already connected"
        case .notConnected:
            return "ServerTransport is not connected"
        case .encodingError:
            return "Failed to encode message"
        case .decodingError:
            return "Failed to decode message from stdin"
        }
    }
}
