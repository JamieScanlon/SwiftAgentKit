//
//  ACPSlashCommandSupport.swift
//  SwiftAgentKitACP
//

import Foundation

/// Client-side helpers for ACP slash commands (invoked via `session/prompt` text).
public enum ACPSlashCommand: Sendable {
    /// Formats a slash command prompt, e.g. `format(name: "web", input: "ACP spec")` → `"/web ACP spec"`.
    public static func format(name: String, input: String? = nil) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let input, !input.isEmpty else {
            return "/\(trimmedName)"
        }
        return "/\(trimmedName) \(input)"
    }

    /// Parses a leading slash command from prompt text.
    /// Returns `nil` when the text is not a slash command.
    public static func parse(text: String) -> (name: String, input: String?)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        let body = String(trimmed.dropFirst())
        guard !body.isEmpty else { return nil }

        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let name = String(parts[0])
        guard !name.isEmpty else { return nil }

        let input = parts.count > 1 ? String(parts[1]) : nil
        return (name: name, input: input)
    }
}

extension ACPAvailableCommand {
    /// Returns whether the prompt text invokes this command.
    public func matches(prompt: String) -> Bool {
        guard let parsed = ACPSlashCommand.parse(text: prompt) else { return false }
        return parsed.name == name
    }
}
