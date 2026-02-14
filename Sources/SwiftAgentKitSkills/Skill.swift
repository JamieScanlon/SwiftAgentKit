//
//  Skill.swift
//  SwiftAgentKitSkills
//
//  Agent Skills spec: https://agentskills.io/specification
//

import Foundation

/// Represents a skill conforming to the [Agent Skills specification](https://agentskills.io/specification).
///
/// A skill is a directory containing at minimum a `SKILL.md` file with YAML frontmatter
/// followed by Markdown body content. Optional directories include `scripts/`,
/// `references/`, and `assets/`.
public struct Skill: Sendable {
    
    /// The parsed frontmatter from the skill's SKILL.md file.
    public let frontmatter: SkillFrontmatter
    
    /// The Markdown body content after the frontmatter (skill instructions).
    public let body: String
    
    /// The URL of the skill directory (parent of SKILL.md).
    public let directoryURL: URL
    
    /// The URL of the SKILL.md file.
    public let skillFileURL: URL
    
    public init(
        frontmatter: SkillFrontmatter,
        body: String,
        directoryURL: URL,
        skillFileURL: URL
    ) {
        self.frontmatter = frontmatter
        self.body = body
        self.directoryURL = directoryURL
        self.skillFileURL = skillFileURL
    }
    
    /// The skill name (convenience accessor).
    public var name: String { frontmatter.name }
    
    /// The skill description (convenience accessor).
    public var description: String { frontmatter.description }
    
    /// Returns the full content (instructions) of the skill, suitable for agent context.
    /// Combines the description with the body for progressive disclosure.
    public var fullInstructions: String {
        var parts: [String] = []
        parts.append("## \(name)\n\n\(description)\n")
        if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(body)
        }
        return parts.joined(separator: "\n\n")
    }
    
    /// Returns the URL for a file within the skill's directory.
    /// - Parameter path: Relative path from the skill root (e.g., "references/REFERENCE.md").
    /// - Returns: The full URL, or nil if the path escapes the skill directory.
    public func url(forRelativePath path: String) -> URL? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/").map(String.init)
        var resolved = directoryURL
        for component in components {
            if component == ".." {
                resolved = resolved.deletingLastPathComponent()
                if !resolved.path.hasPrefix(directoryURL.path) && resolved != directoryURL {
                    return nil
                }
            } else if component != "." {
                resolved = resolved.appendingPathComponent(component)
            }
        }
        return resolved.path.hasPrefix(directoryURL.path) ? resolved : nil
    }
    
    /// Checks if the skill has a `scripts/` directory.
    public var hasScriptsDirectory: Bool {
        let scriptsURL = directoryURL.appendingPathComponent("scripts")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: scriptsURL.path, isDirectory: &isDir) && isDir.boolValue
    }
    
    /// Checks if the skill has a `references/` directory.
    public var hasReferencesDirectory: Bool {
        let refsURL = directoryURL.appendingPathComponent("references")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: refsURL.path, isDirectory: &isDir) && isDir.boolValue
    }
    
    /// Checks if the skill has an `assets/` directory.
    public var hasAssetsDirectory: Bool {
        let assetsURL = directoryURL.appendingPathComponent("assets")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: assetsURL.path, isDirectory: &isDir) && isDir.boolValue
    }
}

/// Frontmatter extracted from a SKILL.md file per the Agent Skills spec.
public struct SkillFrontmatter: Sendable, Codable {
    
    /// Required. Max 64 characters. Lowercase letters, numbers, hyphens only.
    /// Must not start/end with hyphen or contain consecutive hyphens.
    public let name: String
    
    /// Required. Max 1024 characters. Describes what the skill does and when to use it.
    public let description: String
    
    /// Optional. License name or reference to bundled license file.
    public let license: String?
    
    /// Optional. Max 500 characters. Environment requirements.
    public let compatibility: String?
    
    /// Optional. Arbitrary key-value metadata.
    public let metadata: [String: String]?
    
    /// Optional. Space-delimited list of pre-approved tools (experimental).
    public let allowedTools: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case description
        case license
        case compatibility
        case metadata
        case allowedTools = "allowed-tools"
    }
    
    public init(
        name: String,
        description: String,
        license: String? = nil,
        compatibility: String? = nil,
        metadata: [String: String]? = nil,
        allowedTools: String? = nil
    ) {
        self.name = name
        self.description = description
        self.license = license
        self.compatibility = compatibility
        self.metadata = metadata
        self.allowedTools = allowedTools
    }
    
    /// Parsed list of allowed tools (split from space-delimited string).
    public var allowedToolsList: [String] {
        guard let allowedTools else { return [] }
        return allowedTools.split(separator: " ").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
