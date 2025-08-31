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
        
        // For piped input, we need to read all available data first
        // then keep the stream open for potential future input
        var hasReadInitialData = false
        
        while isConnected {
            do {
                // Read available data from stdin
                let data = FileHandle.standardInput.availableData
                
                if !data.isEmpty {
                    internalLogger.info("Received data: \(data.count) bytes")
                    
                    // Yield the data to the continuation
                    messageContinuation?.yield(data)
                    internalLogger.debug("Successfully yielded data to continuation")
                    hasReadInitialData = true
                } else {
                    // If we've read some data and now there's none, 
                    // we should keep the stream open but not finish it
                    if hasReadInitialData {
                        internalLogger.debug("No more data available, keeping stream open")
                        // Keep the stream open by not calling finish()
                        // Just wait a bit longer for potential future input
                        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
                    } else {
                        // Small delay to prevent busy waiting
                        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                    }
                }
            } catch {
                internalLogger.error("Error reading from stdin: \(error)")
                break
            }
        }
        
        internalLogger.debug("ReadLoop finished")
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
