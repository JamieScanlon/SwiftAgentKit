//
//  JSONRPCMessageFilter.swift
//  SwiftAgentKit
//

import Foundation
import Logging

/// Filters non-JSON-RPC lines from stdio transport data.
public struct JSONRPCMessageFilter: Sendable {
    public struct Configuration: Sendable {
        public let enabled: Bool
        public let logFilteredMessages: Bool
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
    private let logger: Logging.Logger

    public init(configuration: Configuration = Configuration(), logger: Logging.Logger? = nil) {
        self.configuration = configuration
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .core("JSONRPCMessageFilter"),
            metadata: SwiftAgentKitLogging.metadata(
                ("filteredLogLevel", .string(String(describing: configuration.filteredMessageLogLevel)))
            )
        )
    }

    public func filterMessage(_ data: Data) -> Data? {
        guard configuration.enabled else { return data }

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

        let lines = messageString.components(separatedBy: .newlines)
        var validMessages: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if JSONRPCMessageValidator.isValidLine(trimmed) {
                validMessages.append(trimmed)
            } else if configuration.logFilteredMessages {
                logger.log(
                    level: configuration.filteredMessageLogLevel,
                    "Filtered non-JSON-RPC line",
                    metadata: SwiftAgentKitLogging.metadata(("line", .string(trimmed)))
                )
            }
        }

        guard !validMessages.isEmpty else { return nil }
        return (validMessages.joined(separator: "\n") + "\n").data(using: .utf8)
    }
}

public extension JSONRPCMessageFilter.Configuration {
    static let `default` = JSONRPCMessageFilter.Configuration()
    static let disabled = JSONRPCMessageFilter.Configuration(enabled: false)
    static let verbose = JSONRPCMessageFilter.Configuration(
        enabled: true,
        logFilteredMessages: true,
        filteredMessageLogLevel: .info
    )
}
