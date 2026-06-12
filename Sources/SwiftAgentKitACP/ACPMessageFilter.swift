//
//  ACPMessageFilter.swift
//  SwiftAgentKitACP
//

import Foundation
import Logging
import SwiftAgentKit

/// Filters non-JSON-RPC lines from stdio transport data.
public struct ACPMessageFilter: Sendable {
    public struct Configuration: Sendable {
        public let enabled: Bool
        public let logFilteredMessages: Bool

        public init(enabled: Bool = true, logFilteredMessages: Bool = false) {
            self.enabled = enabled
            self.logFilteredMessages = logFilteredMessages
        }
    }

    private let configuration: Configuration
    private let logger: Logger

    public init(configuration: Configuration = Configuration(), logger: Logger? = nil) {
        self.configuration = configuration
        self.logger = logger ?? SwiftAgentKitLogging.logger(for: .acp("ACPMessageFilter"))
    }

    public func filterMessage(_ data: Data) -> Data? {
        guard configuration.enabled else { return data }
        guard let messageString = String(data: data, encoding: .utf8) else { return nil }

        let lines = messageString.components(separatedBy: .newlines)
        var validMessages: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if isValidJSONRPCMessage(trimmed) {
                validMessages.append(trimmed)
            } else if configuration.logFilteredMessages {
                logger.debug(
                    "Filtered non-JSON-RPC line",
                    metadata: SwiftAgentKitLogging.metadata(("line", .string(trimmed)))
                )
            }
        }

        guard !validMessages.isEmpty else { return nil }
        return (validMessages.joined(separator: "\n") + "\n").data(using: .utf8)
    }

    private func isValidJSONRPCMessage(_ message: String) -> Bool {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jsonrpc = json["jsonrpc"] as? String,
              jsonrpc == "2.0" else {
            return false
        }
        return json["method"] != nil || json["result"] != nil || json["error"] != nil
    }
}
