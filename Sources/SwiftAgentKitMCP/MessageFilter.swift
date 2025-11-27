//
//  MessageFilter.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 5/17/25.
//

import Foundation
import Logging
import SwiftAgentKit

/// Utility for filtering and validating MCP protocol messages
public struct MessageFilter {
    
    /// Configuration for message filtering behavior
    public struct Configuration: Sendable {
        /// Whether to enable message filtering
        public let enabled: Bool
        
        /// Whether to log filtered messages for debugging
        public let logFilteredMessages: Bool
        
        /// Log level for filtered message logging
        public let filteredMessageLogLevel: Logger.Level
        
        public init(
            enabled: Bool = true,
            logFilteredMessages: Bool = false,
            filteredMessageLogLevel: Logger.Level = .debug
        ) {
            self.enabled = enabled
            self.logFilteredMessages = logFilteredMessages
            self.filteredMessageLogLevel = filteredMessageLogLevel
        }
    }
    
    private let configuration: Configuration
    private let logger: Logger
    
    public init(configuration: Configuration = Configuration(), logger: Logger? = nil) {
        self.configuration = configuration
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .mcp("MessageFilter"),
            metadata: SwiftAgentKitLogging.metadata(
                ("filteredLogLevel", .string(String(describing: configuration.filteredMessageLogLevel)))
            )
        )
    }
    
    /// Filters incoming data to extract only valid JSON-RPC protocol messages
    /// - Parameter data: Raw data received from the transport
    /// - Returns: Filtered data containing only valid JSON-RPC messages, or nil if no valid messages found
    public func filterMessage(_ data: Data) -> Data? {
        guard configuration.enabled else {
            return data
        }
        
        guard let messageString = String(data: data, encoding: .utf8) else {
            if configuration.logFilteredMessages {
                logger.log(
                    level: configuration.filteredMessageLogLevel,
                    "Filtered invalid data",
                    metadata: SwiftAgentKitLogging.metadata(("reason", .string("invalid-utf8")))
                )
            }
            return nil
        }
        
        // Split by newlines to handle multiple messages
        let lines = messageString.components(separatedBy: .newlines)
        var validMessages: [String] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines
            guard !trimmedLine.isEmpty else { continue }
            
            // Check if this line is a valid JSON-RPC message
            if isValidJSONRPCMessage(trimmedLine) {
                validMessages.append(trimmedLine)
            } else {
                if configuration.logFilteredMessages {
                    logger.log(
                        level: configuration.filteredMessageLogLevel,
                        "Filtered non-JSON-RPC line",
                        metadata: SwiftAgentKitLogging.metadata(("line", .string(trimmedLine)))
                    )
                }
            }
        }
        
        // Return the valid messages joined with newlines
        guard !validMessages.isEmpty else {
            return nil
        }
        
        let filteredMessage = validMessages.joined(separator: "\n") + "\n"
        return filteredMessage.data(using: .utf8)
    }
    
    /// Validates if a string is a valid JSON-RPC message
    /// - Parameter message: The message string to validate
    /// - Returns: True if the message is valid JSON-RPC, false otherwise
    private func isValidJSONRPCMessage(_ message: String) -> Bool {
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
    
    /// Checks if a message looks like a log message (common patterns)
    /// - Parameter message: The message string to check
    /// - Returns: True if the message appears to be a log message
    private func isLogMessage(_ message: String) -> Bool {
        let logPatterns = [
            // Common log level patterns
            "\\[DEBUG\\]",
            "\\[INFO\\]",
            "\\[WARN\\]",
            "\\[WARNING\\]",
            "\\[ERROR\\]",
            "\\[FATAL\\]",
            "\\[TRACE\\]",
            
            // Timestamp patterns
            "\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}",
            "\\d{2}:\\d{2}:\\d{2}",
            
            // Common log prefixes
            "LOG:",
            "log:",
            "Log:",
            
            // JSON log patterns (but not JSON-RPC)
            "\\{\"level\":",
            "\\{\"timestamp\":",
            "\\{\"message\":",
            "\\{\"severity\":"
        ]
        
        for pattern in logPatterns {
            if message.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        return false
    }
}

/// Extension to provide default configurations
public extension MessageFilter.Configuration {
    
    /// Default configuration with filtering enabled
    static let `default` = MessageFilter.Configuration()
    
    /// Configuration with filtering disabled
    static let disabled = MessageFilter.Configuration(enabled: false)
    
    /// Configuration with verbose logging of filtered messages
    static let verbose = MessageFilter.Configuration(
        enabled: true,
        logFilteredMessages: true,
        filteredMessageLogLevel: Logger.Level.info
    )
}
