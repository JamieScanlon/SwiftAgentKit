//
//  SkillsToolProvider.swift
//  SwiftAgentKitSkills
//
//  ToolProvider that exposes skill activation and deactivation as tools.
//

import Foundation
import Logging
import SwiftAgentKit
import EasyJSON

/// Callback invoked when a skill is activated. Use to inject the skill's instructions into system context.
public typealias OnSkillActivated = @Sendable (Skill) async -> Void

/// Callback invoked when a skill is deactivated. Use to remove the skill's instructions from system context.
public typealias OnSkillDeactivated = @Sendable (String) async -> Void

/// Tool provider that allows LLMs to activate and deactivate Agent Skills via tool calls.
///
/// Exposes three tools:
/// - `agent-skill-activate`: Loads a skill and marks it as activated. Returns the full instructions
///   for injection into context.
/// - `agent-skill-deactivate`: Removes a skill from the activated set.
/// - `agent-skills-list-active`: Returns the names of currently activated skills.
///
/// Provide `onSkillActivated` and `onSkillDeactivated` callbacks to update system context when skills
/// are activated or deactivated; updating context is beyond the scope of this library.
public struct SkillsToolProvider: ToolProvider {
    
    /// Errors thrown by `SkillsToolProvider`.
    public enum Error: Swift.Error, Sendable {
        case unknownTool(String)
        case missingParameter(String)
        case skillNotFound(String)
    }
    
    public static let activateToolName = "agent-skill-activate"
    public static let deactivateToolName = "agent-skill-deactivate"
    public static let listActivatedToolName = "agent-skills-list-active"
    
    private let loader: SkillLoader
    private let logger: Logger
    private let onSkillActivated: OnSkillActivated?
    private let onSkillDeactivated: OnSkillDeactivated?
    
    public var name: String { "Agent Skills" }
    
    /// - Parameters:
    ///   - loader: The skill loader (configured with the root skills directory).
    ///   - logger: Optional logger.
    ///   - onSkillActivated: Callback invoked when a skill is activated. Use to inject the skill's
    ///     instructions into system context. Receives the loaded `Skill`.
    ///   - onSkillDeactivated: Callback invoked when a skill is deactivated. Use to remove the
    ///     skill's instructions from system context. Receives the skill name.
    public init(
        loader: SkillLoader,
        logger: Logger? = nil,
        onSkillActivated: OnSkillActivated? = nil,
        onSkillDeactivated: OnSkillDeactivated? = nil
    ) {
        self.loader = loader
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .custom(subsystem: "swiftagentkit.skills", component: "SkillsToolProvider")
        )
        self.onSkillActivated = onSkillActivated
        self.onSkillDeactivated = onSkillDeactivated
    }
    
    public func availableTools() async -> [ToolDefinition] {
        [
            ToolDefinition(
                name: Self.activateToolName,
                description: "Activate an Agent Skill by name. Loads the skill's full instructions and marks it as active. Use the returned instructions to add the skill to context. Call when the user's task matches an available skill from the system prompt.",
                parameters: [
                    .init(name: "skill_name", description: "The skill name (e.g. pdf-processing, data-analysis). Must match a skill directory name.", type: "string", required: true)
                ],
                type: .function
            ),
            ToolDefinition(
                name: Self.deactivateToolName,
                description: "Deactivate an Agent Skill by name. Removes the skill from the active set. Call when the skill is no longer needed or to free context.",
                parameters: [
                    .init(name: "skill_name", description: "The skill name to deactivate.", type: "string", required: true)
                ],
                type: .function
            ),
            ToolDefinition(
                name: Self.listActivatedToolName,
                description: "List the names of currently activated skills.",
                parameters: [],
                type: .function
            ),
        ]
    }
    
    public func executeTool(_ toolCall: ToolCall) async throws -> ToolResult {
        guard [Self.activateToolName, Self.deactivateToolName, Self.listActivatedToolName].contains(toolCall.name) else {
            throw Error.unknownTool(toolCall.name)
        }
        
        switch toolCall.name {
        case Self.activateToolName:
            return try await executeActivateSkill(toolCall)
        case Self.deactivateToolName:
            return try await executeDeactivateSkill(toolCall)
        case Self.listActivatedToolName:
            return await executeListActivatedSkills(toolCall)
        default:
            throw Error.unknownTool(toolCall.name)
        }
    }
    
    private func executeActivateSkill(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let skillName = extractString(from: toolCall.arguments, key: "skill_name") else {
            throw Error.missingParameter("skill_name")
        }
        
        guard let skill = try await loader.loadAndActivateSkill(named: skillName) else {
            throw Error.skillNotFound(skillName)
        }
        
        logger.info("Activated skill via tool", metadata: SwiftAgentKitLogging.metadata(
            ("skill", .string(skillName)),
            ("toolCallId", .string(toolCall.id ?? "nil"))
        ))
        
        await onSkillActivated?(skill)
        
        return ToolResult(
            success: true,
            content: skill.fullInstructions,
            metadata: .object([
                "source": .string("skills_tool"),
                "skill_name": .string(skillName),
                "action": .string("activated")
            ]),
            toolCallId: toolCall.id
        )
    }
    
    private func executeDeactivateSkill(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let skillName = extractString(from: toolCall.arguments, key: "skill_name") else {
            throw Error.missingParameter("skill_name")
        }
        
        guard await loader.isActivated(name: skillName) else {
            throw Error.skillNotFound(skillName)
        }
        
        await loader.deactivateSkill(named: skillName)
        
        await onSkillDeactivated?(skillName)
        
        logger.info("Deactivated skill via tool", metadata: SwiftAgentKitLogging.metadata(
            ("skill", .string(skillName)),
            ("toolCallId", .string(toolCall.id ?? "nil"))
        ))
        
        return ToolResult(
            success: true,
            content: "Deactivated skill '\(skillName)'.",
            metadata: .object([
                "source": .string("skills_tool"),
                "skill_name": .string(skillName),
                "action": .string("deactivated")
            ]),
            toolCallId: toolCall.id
        )
    }
    
    private func executeListActivatedSkills(_ toolCall: ToolCall) async -> ToolResult {
        let activated = await loader.activatedSkills
        let names = activated.sorted()
        let content = names.isEmpty
            ? "No skills are currently activated."
            : "Activated skills: \(names.joined(separator: ", "))"
        
        return ToolResult(
            success: true,
            content: content,
            metadata: .object([
                "source": .string("skills_tool"),
                "action": .string("list"),
                "count": .integer(names.count)
            ]),
            toolCallId: toolCall.id
        )
    }
    
    private func extractString(from arguments: JSON, key: String) -> String? {
        guard case .object(let dict) = arguments,
              let value = dict[key] else {
            return nil
        }
        if case .string(let s) = value { return s }
        return nil
    }
}
