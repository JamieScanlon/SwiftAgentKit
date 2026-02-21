//
//  SkillParser.swift
//  SwiftAgentKitSkills
//
//  Parses SKILL.md files according to the Agent Skills spec.
//

import Foundation
import Logging
import SwiftAgentKit
import Yams

/// Errors that can occur when parsing a skill.
public enum SkillParseError: Error, Sendable {
    case fileNotFound(URL)
    case noFrontmatterDelimiter(URL)
    case invalidFrontmatterYAML(URL, underlying: Error)
    case missingRequiredField(String)
    case invalidName(String)
    case nameMismatch(directoryName: String, frontmatterName: String)
}

/// Parses SKILL.md files conforming to the [Agent Skills specification](https://agentskills.io/specification).
public struct SkillParser: Sendable {
    
    private let logger: Logger
    
    public init(logger: Logger? = nil) {
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .custom(subsystem: "swiftagentkit.skills", component: "SkillParser")
        )
    }
    
    /// Parses a SKILL.md file at the given URL.
    /// - Parameter skillFileURL: URL to SKILL.md (e.g. `skill-dir/SKILL.md`).
    /// - Returns: A parsed `Skill` if valid.
    public func parse(skillFileURL: URL) throws -> Skill {
        let data: Data
        do {
            data = try Data(contentsOf: skillFileURL)
        } catch {
            logger.error("Failed to read skill file", metadata: SwiftAgentKitLogging.metadata(
                ("url", .string(skillFileURL.path)),
                ("error", .string(String(describing: error)))
            ))
            throw SkillParseError.fileNotFound(skillFileURL)
        }
        
        guard let content = String(data: data, encoding: .utf8) else {
            throw SkillParseError.invalidFrontmatterYAML(skillFileURL, underlying: NSError(domain: "SkillParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8"]))
        }
        
        let (frontmatter, body) = try extractFrontmatterAndBody(from: content, fileURL: skillFileURL)
        try validateFrontmatter(frontmatter, directoryURL: skillFileURL.deletingLastPathComponent(), fileURL: skillFileURL)
        
        let directoryURL = skillFileURL.deletingLastPathComponent()
        
        return Skill(
            frontmatter: frontmatter,
            body: body,
            directoryURL: directoryURL,
            skillFileURL: skillFileURL
        )
    }
    
    /// Parses a SKILL.md file within a skill directory.
    /// - Parameter directoryURL: URL to the skill directory (must contain SKILL.md).
    /// - Returns: A parsed `Skill` if valid.
    public func parse(directoryURL: URL) throws -> Skill {
        let skillFileURL = directoryURL.appendingPathComponent("SKILL.md")
        return try parse(skillFileURL: skillFileURL)
    }
    
    // MARK: - Private
    
    private func extractFrontmatterAndBody(from content: String, fileURL: URL) throws -> (SkillFrontmatter, String) {
        let openDelimiter = "---"
        guard content.hasPrefix(openDelimiter) else {
            throw SkillParseError.noFrontmatterDelimiter(fileURL)
        }
        
        let afterOpen = content.dropFirst(openDelimiter.count)
        guard let closeRange = afterOpen.range(of: "\n\(openDelimiter)", options: []) else {
            throw SkillParseError.noFrontmatterDelimiter(fileURL)
        }
        
        let frontmatterString = String(afterOpen[..<closeRange.lowerBound])
        let bodyStart = closeRange.upperBound
        let body = String(content[content.index(bodyStart, offsetBy: 0)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        let decoder = YAMLDecoder()
        let frontmatter: SkillFrontmatter
        do {
            frontmatter = try decoder.decode(SkillFrontmatter.self, from: frontmatterString)
        } catch {
            logger.error("Invalid YAML frontmatter", metadata: SwiftAgentKitLogging.metadata(
                ("url", .string(fileURL.path)),
                ("error", .string(String(describing: error)))
            ))
            throw SkillParseError.invalidFrontmatterYAML(fileURL, underlying: error)
        }
        
        return (frontmatter, body)
    }
    
    private func validateFrontmatter(_ frontmatter: SkillFrontmatter, directoryURL: URL, fileURL: URL) throws {
        if frontmatter.name.isEmpty {
            throw SkillParseError.missingRequiredField("name")
        }
        if frontmatter.description.isEmpty {
            throw SkillParseError.missingRequiredField("description")
        }
        
        // Name constraints per spec: 1-64 chars, lowercase alphanumeric and hyphens, no leading/trailing hyphen, no consecutive hyphens
        let namePattern = #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#
        guard frontmatter.name.count <= 64,
              frontmatter.name.range(of: namePattern, options: .regularExpression) != nil else {
            throw SkillParseError.invalidName(frontmatter.name)
        }
        
        // Name must match parent directory name
        let directoryName = directoryURL.lastPathComponent
        if directoryName != frontmatter.name {
            throw SkillParseError.nameMismatch(directoryName: directoryName, frontmatterName: frontmatter.name)
        }
        
        if frontmatter.description.count > 1024 {
            logger.warning("Skill description exceeds 1024 characters", metadata: SwiftAgentKitLogging.metadata(
                ("skill", .string(frontmatter.name)),
                ("length", .stringConvertible(frontmatter.description.count))
            ))
        }
        
        if let compat = frontmatter.compatibility, compat.count > 500 {
            logger.warning("Skill compatibility exceeds 500 characters", metadata: SwiftAgentKitLogging.metadata(
                ("skill", .string(frontmatter.name))
            ))
        }
    }
}
