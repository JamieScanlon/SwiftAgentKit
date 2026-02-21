//
//  SkillPromptFormatter.swift
//  SwiftAgentKitSkills
//
//  Formats skill metadata for injection into LLM system prompts.
//

import Foundation

/// Formats skill metadata for inclusion in LLM system prompts.
public enum SkillPromptFormatter {
    
    /// Escapes XML special characters in a string.
    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    /// Escapes a string for JSON (backslashes, quotes, control chars).
    private static func escapeJSON(_ string: String) -> String {
        var result = ""
        for char in string {
            switch char {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if char.unicodeScalars.first.map({ $0.value < 32 }) == true {
                    result += "\\u" + String(format: "%04x", char.unicodeScalars.first!.value)
                } else {
                    result.append(char)
                }
            }
        }
        return result
    }
    
    /// Escapes a string for YAML. Quotes the value if it contains special characters.
    private static func escapeYAML(_ string: String) -> String {
        let needsQuoting = string.contains(where: { ":#{}\n[]\"'*&!|>%@`.".contains($0) }) || string.hasPrefix(" ") || string.hasSuffix(" ")
        if needsQuoting {
            let escaped = string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return "\"\(escaped)\""
        }
        return string
    }
    
    /// Formats skill metadata as XML for injection into a system prompt.
    ///
    /// Produces an `<available_skills>` block with each skill's name, description,
    /// and location (path to SKILL.md). Use this at startup to inform the agent
    /// which skills are available without loading full instructions.
    ///
    /// - Parameter metadata: Array of skill metadata from `SkillLoader.loadMetadata()`.
    /// - Returns: XML string suitable for embedding in a system prompt.
    public static func formatAsXML(_ metadata: [SkillMetadata]) -> String {
        guard !metadata.isEmpty else {
            return "<available_skills></available_skills>"
        }
        
        let skillBlocks = metadata.map { m in
            """
              <skill>
                <name>\(escapeXML(m.name))</name>
                <description>\(escapeXML(m.description))</description>
                <location>\(escapeXML(m.skillFileURL.path))</location>
              </skill>
            """
        }.joined(separator: "\n")
        
        return """
        <available_skills>
        \(skillBlocks)
        </available_skills>
        """
    }
    
    /// Formats skill metadata as YAML for injection into a system prompt.
    ///
    /// Produces an `available_skills` list with each skill's name, description,
    /// and location. Use this at startup to inform the agent which skills are available.
    ///
    /// - Parameter metadata: Array of skill metadata from `SkillLoader.loadMetadata()`.
    /// - Returns: YAML string suitable for embedding in a system prompt.
    public static func formatAsYAML(_ metadata: [SkillMetadata]) -> String {
        guard !metadata.isEmpty else {
            return "available_skills: []"
        }
        
        let skillBlocks = metadata.map { m in
            """
            - name: \(escapeYAML(m.name))
              description: \(escapeYAML(m.description))
              location: \(escapeYAML(m.skillFileURL.path))
            """
        }.joined(separator: "\n")
        
        return "available_skills:\n\(skillBlocks)"
    }
    
    /// Formats skill metadata as JSON for injection into a system prompt.
    ///
    /// Produces an `available_skills` array with each skill's name, description,
    /// and location. Use this at startup to inform the agent which skills are available.
    ///
    /// - Parameter metadata: Array of skill metadata from `SkillLoader.loadMetadata()`.
    /// - Returns: JSON string suitable for embedding in a system prompt.
    public static func formatAsJSON(_ metadata: [SkillMetadata]) -> String {
        guard !metadata.isEmpty else {
            return "{\"available_skills\":[]}"
        }
        
        let skillObjects = metadata.map { m in
            """
            {"name":"\(escapeJSON(m.name))","description":"\(escapeJSON(m.description))","location":"\(escapeJSON(m.skillFileURL.path))"}
            """
        }
        let arrayBody = skillObjects.joined(separator: ",")
        return "{\"available_skills\":[\(arrayBody)]}"
    }
}
