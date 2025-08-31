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
    private var isReady = false
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
        
        // Don't start reading loop yet - wait for ready signal
        internalLogger.info("ServerTransport connected, waiting for ready signal before reading messages")
    }
    
    /// Signal that the server is ready to process messages
    /// This should be called after the MCP server is fully initialized
    public func setReady() {
        guard isConnected else {
            internalLogger.warning("Cannot set ready state - transport not connected")
            return
        }
        
        guard !isReady else {
            internalLogger.debug("Transport already ready")
            return
        }
        
        internalLogger.info("ServerTransport setting ready state - starting message processing")
        isReady = true
        
        // Start reading loop now that server is ready
        Task.detached {
            await self.readLoop()
        }
    }
    
    public func disconnect() async {
        guard isConnected else { return }
        
        internalLogger.info("ServerTransport disconnecting...")
        isConnected = false
        isReady = false
        
        // Stop the readability handler
        FileHandle.standardInput.readabilityHandler = nil
        
        // Finish the message continuation
        messageContinuation?.finish()
        
        internalLogger.info("ServerTransport disconnected")
    }
    
    public func send(_ data: Data) async throws {
        guard isConnected else {
            throw ServerTransportError.notConnected
        }
        
        internalLogger.info("ServerTransport sending response: \(data.count) bytes")
        
        // Log the response content for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            internalLogger.debug("Response content: \(responseString)")
            
            // Check if this looks like a JSON-RPC response
            if responseString.contains("\"jsonrpc\"") {
                internalLogger.info("Detected JSON-RPC response")
                
                // Try to extract response ID for tracking
                if let idRange = responseString.range(of: "\"id\"\\s*:\\s*(\\d+)", options: .regularExpression) {
                    let idString = String(responseString[idRange])
                    internalLogger.info("Response ID: \(idString)")
                }
                
                // Check if it's an error response
                if responseString.contains("\"error\"") {
                    internalLogger.warning("JSON-RPC error response detected")
                } else if responseString.contains("\"result\"") {
                    internalLogger.info("JSON-RPC success response detected")
                }
            }
        }
        
        // Write directly to stdout
        try FileHandle.standardOutput.write(contentsOf: data)
        try FileHandle.standardOutput.synchronize()
        
        internalLogger.info("Response sent successfully to stdout")
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
        internalLogger.info("Setting up readabilityHandler for stdin...")
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            
            internalLogger.debug("readabilityHandler triggered - data available")
            let data = handle.availableData
            if !data.isEmpty {
                internalLogger.info("readabilityHandler: Received \(data.count) bytes")
                // Check ready state and process message asynchronously
                Task.detached {
                    await self.processIncomingData(data)
                }
            } else {
                internalLogger.debug("readabilityHandler: No data available")
            }
        }
        
        internalLogger.info("readabilityHandler set up successfully")
        
        // Keep the loop alive while connected
        while isConnected {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        internalLogger.debug("ReadLoop finished")
    }
    
    /// Process incoming data - checks ready state and handles message processing
    private func processIncomingData(_ data: Data) {
        // Only process messages if we're ready
        guard isReady else {
            internalLogger.debug("Received data but not ready to process - buffering")
            return
        }
        
        internalLogger.info("Received data: \(data.count) bytes")
        
        // Try to parse as JSON to detect message type
        if let jsonString = String(data: data, encoding: .utf8) {
            internalLogger.debug("Raw message: \(jsonString)")
            
            // Check if this looks like a JSON-RPC message
            if jsonString.contains("\"jsonrpc\"") {
                internalLogger.info("Detected JSON-RPC message")
                
                // Try to extract method name for better logging
                if let methodRange = jsonString.range(of: "\"method\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
                    let methodString = String(jsonString[methodRange])
                    internalLogger.info("Message method: \(methodString)")
                }
            }
        }
        
        // Yield the data to the continuation - this should trigger MCP library processing
        internalLogger.info("Yielding data to MCP library for processing...")
        yieldData(data)
        internalLogger.info("Data yielded successfully - MCP library should now process the message")
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
