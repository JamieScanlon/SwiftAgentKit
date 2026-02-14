//
//  SwiftAgentKitSkills.swift
//  SwiftAgentKitSkills
//
//  Add-on library for the Agent Skills specification.
//  https://agentskills.io/specification
//

import Foundation

/// SwiftAgentKitSkills - Support for the Agent Skills specification.
///
/// This module provides parsing and loading of skills conforming to the
/// [Agent Skills spec](https://agentskills.io/specification):
///
/// - **Skill**: Model representing a skill with frontmatter and body content
/// - **SkillParser**: Parses SKILL.md files with YAML frontmatter
/// - **SkillLoader**: Discovers and loads skills from directories
///
/// ## Usage
///
/// ```swift
/// import SwiftAgentKitSkills
///
/// let loader = SkillLoader()
/// let skills = try await loader.loadSkills(from: URL(fileURLWithPath: "./skills"))
///
/// for skill in skills {
///     print("\(skill.name): \(skill.description)")
///     print(skill.fullInstructions)
/// }
/// ```
///
/// ## Progressive Disclosure
///
/// For efficient context usage, load metadata first at startup, then full skills on demand:
///
/// ```swift
/// let metadata = try await loader.loadMetadata(from: skillsDirectory)
/// // Use metadata for skill selection...
/// let skill = try await loader.loadSkill(named: "pdf-processing", from: skillsDirectory)
/// ```
public enum SwiftAgentKitSkills {}
