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
///
/// Tracks which skills have been "activated" (fully loaded into context). Use `activate(_:)` when
/// you've loaded a skill and injected its instructions into the agent context, and `deactivateSkill(named:)`
/// when removing it from context.
public actor SkillLoader {
    
    private let parser: SkillParser
    private let logger: Logger
    
    /// Root directory containing skill subdirectories (each with a SKILL.md file).
    public let skillsDirectoryURL: URL
    
    /// Names of skills that have been activated (fully loaded into context).
    private var activatedSkillNames: Set<String> = []
    
    /// - Parameters:
    ///   - skillsDirectoryURL: Root directory containing skill subdirectories (e.g. `~/.skills` or `./skills`).
    ///   - parser: Parser for SKILL.md files.
    ///   - logger: Optional logger.
    public init(skillsDirectoryURL: URL, parser: SkillParser = SkillParser(), logger: Logger? = nil) {
        self.skillsDirectoryURL = skillsDirectoryURL
        self.parser = parser
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .custom(subsystem: "swiftagentkit.skills", component: "SkillLoader")
        )
    }
    
    // MARK: - Activation Tracking
    
    /// Marks a skill as activated (fully loaded into context).
    /// Call this after loading a skill and injecting its instructions into the agent.
    /// - Parameter skill: The skill that was loaded and injected.
    public func activate(_ skill: Skill) {
        activatedSkillNames.insert(skill.name)
        logger.info("Activated skill", metadata: SwiftAgentKitLogging.metadata(
            ("skill", .string(skill.name))
        ))
    }
    
    /// Marks a skill as activated by name.
    /// Use when you have activated a skill without holding a `Skill` instance.
    /// - Parameter name: The skill name to mark as activated.
    public func activateSkill(named name: String) {
        activatedSkillNames.insert(name)
        logger.info("Activated skill", metadata: SwiftAgentKitLogging.metadata(
            ("skill", .string(name))
        ))
    }
    
    /// Removes a skill from the activated set.
    /// Call when removing the skill's instructions from context.
    /// - Parameter name: The skill name to deactivate.
    public func deactivateSkill(named name: String) {
        if activatedSkillNames.remove(name) != nil {
            logger.info("Deactivated skill", metadata: SwiftAgentKitLogging.metadata(
                ("skill", .string(name))
            ))
        }
    }
    
    /// Removes all skills from the activated set.
    public func deactivateAllSkills() {
        let count = activatedSkillNames.count
        activatedSkillNames.removeAll()
        if count > 0 {
            logger.info("Deactivated all skills", metadata: SwiftAgentKitLogging.metadata(
                ("count", .stringConvertible(count))
            ))
        }
    }
    
    /// Returns the set of skill names currently activated.
    public var activatedSkills: Set<String> {
        activatedSkillNames
    }
    
    /// Returns whether a skill is currently activated.
    /// - Parameter name: The skill name to check.
    public func isActivated(name: String) -> Bool {
        activatedSkillNames.contains(name)
    }
    
    /// Discovers all skills in the root skills directory.
    /// A skill is a subdirectory containing a SKILL.md file.
    /// - Returns: URLs of skill directories (each contains SKILL.md).
    public func discoverSkills() throws -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: skillsDirectoryURL.path, isDirectory: &isDir), isDir.boolValue else {
            logger.warning("Skill directory does not exist or is not a directory", metadata: SwiftAgentKitLogging.metadata(
                ("path", .string(skillsDirectoryURL.path))
            ))
            return []
        }
        
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: skillsDirectoryURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            logger.error("Failed to list skill directory", metadata: SwiftAgentKitLogging.metadata(
                ("path", .string(skillsDirectoryURL.path)),
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
            ("directory", .string(skillsDirectoryURL.path)),
            ("count", .stringConvertible(skillURLs.count))
        ))
        
        return skillURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    
    /// Loads metadata only (name, description) for all skills.
    /// Suitable for startup indexing and skill selection.
    /// - Returns: Array of metadata, or empty if directory doesn't exist.
    public func loadMetadata() throws -> [SkillMetadata] {
        let skillURLs = try discoverSkills()
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
    
    /// Loads full skills (including body content).
    /// - Returns: Array of fully loaded skills.
    public func loadSkills() throws -> [Skill] {
        let skillURLs = try discoverSkills()
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
    
    /// Loads a single skill by name.
    /// - Parameter name: Skill name (must match directory name).
    /// - Returns: The skill if found and valid, nil otherwise.
    public func loadSkill(named name: String) throws -> Skill? {
        let skillDirURL = skillsDirectoryURL.appendingPathComponent(name)
        let skillFileURL = skillDirURL.appendingPathComponent("SKILL.md")
        
        let fm = FileManager.default
        guard fm.fileExists(atPath: skillFileURL.path) else {
            return nil
        }
        
        return try parser.parse(skillFileURL: skillFileURL)
    }
    
    /// Loads a skill and marks it as activated in one call.
    /// Convenience for load-then-activate workflows.
    /// - Parameter name: Skill name (must match directory name).
    /// - Returns: The skill if found and valid, nil otherwise. If non-nil, the skill is also activated.
    public func loadAndActivateSkill(named name: String) throws -> Skill? {
        guard let skill = try loadSkill(named: name) else {
            return nil
        }
        activate(skill)
        return skill
    }
}
