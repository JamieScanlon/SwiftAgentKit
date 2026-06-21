//
//  JSONRPCMessageValidator.swift
//  SwiftAgentKit
//

import Foundation

/// Validates JSON-RPC 2.0 message lines.
public enum JSONRPCMessageValidator: Sendable {
    public static func isValidLine(_ message: String) -> Bool {
        isValidMessage(message.data(using: .utf8) ?? Data())
    }

    public static func isValidMessage(_ data: Data) -> Bool {
        guard let message = String(data: data, encoding: .utf8) else { return false }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let jsonData = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let jsonrpc = json["jsonrpc"] as? String,
              jsonrpc == "2.0" else {
            return false
        }
        return json["method"] != nil || json["result"] != nil || json["error"] != nil
    }

    public static func isLogMessage(_ message: String) -> Bool {
        let logPatterns = [
            "\\[DEBUG\\]", "\\[INFO\\]", "\\[WARN\\]", "\\[WARNING\\]", "\\[ERROR\\]",
            "\\[FATAL\\]", "\\[TRACE\\]",
            "\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}",
            "\\d{2}:\\d{2}:\\d{2}",
            "LOG:", "log:", "Log:",
            "\\{\"level\":", "\\{\"timestamp\":", "\\{\"message\":", "\\{\"severity\":"
        ]
        for pattern in logPatterns {
            if message.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }
}
