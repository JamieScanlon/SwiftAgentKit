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
public actor ServerTransport: MCP.Transport {
    private let internalLogger = Logger(label: "ServerTransport")
    
    // MARK: - State
    private var isListening = false
    private var messageHandler: ((String) async -> Void)?
    
    // MARK: - Stdio
    private let stdin = FileHandle.standardInput
    private let stdout = FileHandle.standardOutput
    
    public init() {}
    
    // MARK: - MCP Transport Implementation
    
    public var logger: Logger {
        return internalLogger
    }
    
    public func connect() async throws {
        guard !isListening else {
            throw ServerTransportError.alreadyListening
        }
        
        internalLogger.info("Starting to listen for messages on stdin")
        isListening = true
    }
    
    public func disconnect() async {
        guard isListening else { return }
        
        internalLogger.info("Stopping message listening")
        isListening = false
    }
    
    public func send(_ data: Data) async throws {
        guard isListening else {
            throw ServerTransportError.notListening
        }
        
        try stdout.write(contentsOf: data)
        try stdout.synchronize()
        
        internalLogger.debug("Sent data: \(data.count) bytes")
    }
    
    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        return AsyncThrowingStream { continuation in
            Task {
                while isListening {
                    do {
                        let data = try await readDataFromStdin()
                        continuation.yield(data)
                    } catch {
                        continuation.finish(throwing: error)
                        break
                    }
                }
                continuation.finish()
            }
        }
    }
    
    // MARK: - Legacy Interface (for backward compatibility)
    
    /// Start listening for incoming messages on stdin
    /// - Parameter handler: Closure called when a message is received
    public func startListening(handler: @escaping (String) async -> Void) async throws {
        guard !isListening else {
            throw ServerTransportError.alreadyListening
        }
        
        internalLogger.info("Starting to listen for messages on stdin")
        
        messageHandler = handler
        isListening = true
        
        // Start reading from stdin in a background task
        Task {
            await readFromStdin()
        }
    }
    
    /// Stop listening for messages
    public func stop() {
        guard isListening else { return }
        
        internalLogger.info("Stopping message listening")
        isListening = false
        messageHandler = nil
    }
    
    /// Send a message to stdout
    /// - Parameter message: The message to send
    public func sendMessage(_ message: String) async throws {
        guard isListening else {
            throw ServerTransportError.notListening
        }
        
        // Ensure message ends with newline for proper stdio handling
        let messageWithNewline = message.hasSuffix("\n") ? message : message + "\n"
        
        guard let data = messageWithNewline.data(using: .utf8) else {
            throw ServerTransportError.encodingError
        }
        
        try stdout.write(contentsOf: data)
        try stdout.synchronize()
        
        internalLogger.debug("Sent message: \(message)")
    }
    
    // MARK: - Private Methods
    
    private func readFromStdin() async {
        internalLogger.info("Started reading from stdin")
        
        while isListening {
            do {
                // Read a line from stdin
                let line = try await readLineFromStdin()
                
                guard !line.isEmpty else { continue }
                
                internalLogger.debug("Received message: \(line)")
                
                // Call the message handler
                if let handler = messageHandler {
                    await handler(line)
                }
                
            } catch {
                internalLogger.error("Error reading from stdin: \(error)")
                
                // If we can't read from stdin, we should probably stop
                if isListening {
                    internalLogger.error("Stopping due to stdin read error")
                    isListening = false
                }
                break
            }
        }
        
        internalLogger.info("Stopped reading from stdin")
    }
    
    private func readLineFromStdin() async throws -> String {
        // Read data from stdin
        let data = try stdin.readToEnd() ?? Data()
        
        guard let string = String(data: data, encoding: .utf8) else {
            throw ServerTransportError.decodingError
        }
        
        // Split by newlines and return the first non-empty line
        let lines = string.components(separatedBy: .newlines)
        return lines.first { !$0.isEmpty } ?? ""
    }
    
    private func readDataFromStdin() async throws -> Data {
        // Read data from stdin
        let data = try stdin.readToEnd() ?? Data()
        return data
    }
}

// MARK: - Error Types

public enum ServerTransportError: LocalizedError {
    case alreadyListening
    case notListening
    case encodingError
    case decodingError
    
    public var errorDescription: String? {
        switch self {
        case .alreadyListening:
            return "Transport is already listening"
        case .notListening:
            return "Transport is not listening"
        case .encodingError:
            return "Failed to encode message"
        case .decodingError:
            return "Failed to decode message from stdin"
        }
    }
}
