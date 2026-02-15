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
/// let skillsDirectory = URL(fileURLWithPath: "./skills")
/// let loader = SkillLoader(skillsDirectoryURL: skillsDirectory)
/// let skills = try loader.loadSkills()
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
/// let metadata = try loader.loadMetadata()
/// // Use metadata for skill selection...
/// let skill = try loader.loadSkill(named: "pdf-processing")
/// ```
public enum SwiftAgentKitSkills {}
