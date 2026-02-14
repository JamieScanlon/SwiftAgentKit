//
//  SkillLoader.swift
//  SwiftAgentKitSkills
//
//  Discovers and loads skills from directories per the Agent Skills spec.
//

import Foundation
import Logging
import SwiftAgentKit

/// Lightweight skill metadata for discovery/indexing without loading full instructions.
///
/// Use this for progressive disclosure: load metadata for all skills at startup (~100 tokens),
/// then load full SKILL.md body only when a skill is activated.
public struct SkillMetadata: Sendable {
    public let name: String
    public let description: String
    public let directoryURL: URL
    public let skillFileURL: URL
    
    public init(name: String, description: String, directoryURL: URL, skillFileURL: URL) {
        self.name = name
        self.description = description
        self.directoryURL = directoryURL
        self.skillFileURL = skillFileURL
    }
}

/// Loads and manages skills from directories conforming to the [Agent Skills specification](https://agentskills.io/specification).
public actor SkillLoader {
    
    private let parser: SkillParser
    private let logger: Logger
    
    public init(parser: SkillParser = SkillParser(), logger: Logger? = nil) {
        self.parser = parser
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .custom(subsystem: "swiftagentkit.skills", component: "SkillLoader")
        )
    }
    
    /// Discovers all skills in a directory.
    /// A skill is a subdirectory containing a SKILL.md file.
    /// - Parameter directoryURL: Root directory to scan (e.g. `~/.skills` or `./skills`).
    /// - Returns: URLs of skill directories (each contains SKILL.md).
    public func discoverSkills(in directoryURL: URL) throws -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directoryURL.path, isDirectory: &isDir), isDir.boolValue else {
            logger.warning("Skill directory does not exist or is not a directory", metadata: SwiftAgentKitLogging.metadata(
                ("path", .string(directoryURL.path))
            ))
            return []
        }
        
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            logger.error("Failed to list skill directory", metadata: SwiftAgentKitLogging.metadata(
                ("path", .string(directoryURL.path)),
                ("error", .string(String(describing: error)))
            ))
            throw error
        }
        
        var skillURLs: [URL] = []
        for url in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            
            let skillFileURL = url.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillFileURL.path) else { continue }
            
            skillURLs.append(url)
        }
        
        logger.info("Discovered \(skillURLs.count) skills", metadata: SwiftAgentKitLogging.metadata(
            ("directory", .string(directoryURL.path)),
            ("count", .stringConvertible(skillURLs.count))
        ))
        
        return skillURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    
    /// Loads metadata only (name, description) for all skills in a directory.
    /// Suitable for startup indexing and skill selection.
    /// - Parameter directoryURL: Root directory containing skill subdirectories.
    /// - Returns: Array of metadata, or empty if directory doesn't exist.
    public func loadMetadata(from directoryURL: URL) throws -> [SkillMetadata] {
        let skillURLs = try discoverSkills(in: directoryURL)
        var results: [SkillMetadata] = []
        
        for skillDirURL in skillURLs {
            do {
                let skill = try parser.parse(directoryURL: skillDirURL)
                results.append(SkillMetadata(
                    name: skill.name,
                    description: skill.description,
                    directoryURL: skill.directoryURL,
                    skillFileURL: skill.skillFileURL
                ))
            } catch {
                logger.warning("Skipping invalid skill", metadata: SwiftAgentKitLogging.metadata(
                    ("path", .string(skillDirURL.path)),
                    ("error", .string(String(describing: error)))
                ))
            }
        }
        
        return results
    }
    
    /// Loads full skills (including body content) from a directory.
    /// - Parameter directoryURL: Root directory containing skill subdirectories.
    /// - Returns: Array of fully loaded skills.
    public func loadSkills(from directoryURL: URL) throws -> [Skill] {
        let skillURLs = try discoverSkills(in: directoryURL)
        var results: [Skill] = []
        
        for skillDirURL in skillURLs {
            do {
                let skill = try parser.parse(directoryURL: skillDirURL)
                results.append(skill)
            } catch {
                logger.warning("Skipping invalid skill", metadata: SwiftAgentKitLogging.metadata(
                    ("path", .string(skillDirURL.path)),
                    ("error", .string(String(describing: error)))
                ))
            }
        }
        
        return results
    }
    
    /// Loads a single skill by name from a directory.
    /// - Parameters:
    ///   - name: Skill name (must match directory name).
    ///   - directoryURL: Root directory containing skill subdirectories.
    /// - Returns: The skill if found and valid, nil otherwise.
    public func loadSkill(named name: String, from directoryURL: URL) throws -> Skill? {
        let skillDirURL = directoryURL.appendingPathComponent(name)
        let skillFileURL = skillDirURL.appendingPathComponent("SKILL.md")
        
        let fm = FileManager.default
        guard fm.fileExists(atPath: skillFileURL.path) else {
            return nil
        }
        
        return try parser.parse(skillFileURL: skillFileURL)
    }
}
