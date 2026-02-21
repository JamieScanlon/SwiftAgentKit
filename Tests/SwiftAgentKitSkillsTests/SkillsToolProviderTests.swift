//
//  SkillsToolProviderTests.swift
//  SwiftAgentKitSkillsTests
//

import Testing
import Foundation
import SwiftAgentKit
import EasyJSON
@testable import SwiftAgentKitSkills

private actor CallbackCapture {
    var activatedSkill: Skill?
    var deactivatedSkillName: String?
    func setActivated(_ skill: Skill) { activatedSkill = skill }
    func setDeactivated(_ name: String) { deactivatedSkillName = name }
}

@Suite("SkillsToolProvider Tests")
struct SkillsToolProviderTests {
    
    @Test("Expose agent-skill-activate, agent-skill-deactivate, agent-skills-list-active tools")
    func testAvailableTools() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let provider = SkillsToolProvider(loader: loader)
        let tools = await provider.availableTools()
        
        let names = tools.map { $0.name }.sorted()
        #expect(names == ["agent-skill-activate", "agent-skill-deactivate", "agent-skills-list-active"])
        
        let activate = tools.first { $0.name == "agent-skill-activate" }!
        #expect(activate.parameters.count == 1)
        #expect(activate.parameters[0].name == "skill_name")
        #expect(activate.parameters[0].required == true)
    }
    
    @Test("onSkillActivated callback is invoked when skill is activated")
    func testOnSkillActivatedCallback() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("callback-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: callback-skill
        description: For callback test.
        ---
        Body.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let capture = CallbackCapture()
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let provider = SkillsToolProvider(
            loader: loader,
            onSkillActivated: { skill in await capture.setActivated(skill) }
        )
        
        let toolCall = ToolCall(
            name: SkillsToolProvider.activateToolName,
            arguments: .object(["skill_name": .string("callback-skill")]),
            id: "test-callback"
        )
        _ = try await provider.executeTool(toolCall)
        
        let captured = await capture.activatedSkill
        #expect(captured != nil)
        #expect(captured?.name == "callback-skill")
    }
    
    @Test("onSkillDeactivated callback is invoked when skill is deactivated")
    func testOnSkillDeactivatedCallback() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("deactivate-callback-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: deactivate-callback-skill
        description: For deactivate callback test.
        ---
        Body.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let capture = CallbackCapture()
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let provider = SkillsToolProvider(
            loader: loader,
            onSkillDeactivated: { name in await capture.setDeactivated(name) }
        )
        
        _ = try await loader.loadAndActivateSkill(named: "deactivate-callback-skill")
        
        let toolCall = ToolCall(
            name: SkillsToolProvider.deactivateToolName,
            arguments: .object(["skill_name": .string("deactivate-callback-skill")]),
            id: "test-dcallback"
        )
        _ = try await provider.executeTool(toolCall)
        
        let captured = await capture.deactivatedSkillName
        #expect(captured == "deactivate-callback-skill")
    }
    
    @Test("agent-skill-activate loads and activates skill, returns instructions")
    func testActivateSkill() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("activate-tool-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: activate-tool-skill
        description: For tool activation test.
        ---
        # Steps
        1. Do step one.
        2. Do step two.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let provider = SkillsToolProvider(loader: loader)
        
        let toolCall = ToolCall(
            name: SkillsToolProvider.activateToolName,
            arguments: .object(["skill_name": .string("activate-tool-skill")]),
            id: "test-1"
        )
        
        let result = try await provider.executeTool(toolCall)
        
        #expect(result.success == true)
        #expect(result.content.contains("activate-tool-skill"))
        #expect(result.content.contains("For tool activation test"))
        #expect(result.content.contains("Do step one"))
        #expect(await loader.isActivated(name: "activate-tool-skill") == true)
    }
    
    @Test("agent-skill-activate throws for missing skill")
    func testActivateSkillNotFound() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let provider = SkillsToolProvider(loader: loader)
        
        let toolCall = ToolCall(
            name: SkillsToolProvider.activateToolName,
            arguments: .object(["skill_name": .string("nonexistent-skill")]),
            id: "test-2"
        )
        
        do {
            _ = try await provider.executeTool(toolCall)
            Issue.record("Expected SkillsToolProvider.Error.skillNotFound")
        } catch SkillsToolProvider.Error.skillNotFound(let name) {
            #expect(name == "nonexistent-skill")
        }
    }
    
    @Test("agent-skill-activate throws for missing skill_name param")
    func testActivateSkillMissingParam() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let provider = SkillsToolProvider(loader: loader)
        
        let toolCall = ToolCall(
            name: SkillsToolProvider.activateToolName,
            arguments: .object([:]),
            id: "test-3"
        )
        
        do {
            _ = try await provider.executeTool(toolCall)
            Issue.record("Expected SkillsToolProvider.Error.missingParameter")
        } catch SkillsToolProvider.Error.missingParameter(let param) {
            #expect(param == "skill_name")
        }
    }
    
    @Test("agent-skill-deactivate throws when skill not activated")
    func testDeactivateSkillNotActivated() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let provider = SkillsToolProvider(loader: loader)
        
        // Try to deactivate a skill that was never activated
        let toolCall = ToolCall(
            name: SkillsToolProvider.deactivateToolName,
            arguments: .object(["skill_name": .string("never-activated")]),
            id: "test-deactivate-not-active"
        )
        
        do {
            _ = try await provider.executeTool(toolCall)
            Issue.record("Expected SkillsToolProvider.Error.skillNotFound")
        } catch SkillsToolProvider.Error.skillNotFound(let name) {
            #expect(name == "never-activated")
        }
    }
    
    @Test("agent-skill-deactivate removes skill from activated set")
    func testDeactivateSkill() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("deactivate-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: deactivate-skill
        description: For deactivate test.
        ---
        Body.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let provider = SkillsToolProvider(loader: loader)
        
        // Activate first
        let skill = try await loader.loadAndActivateSkill(named: "deactivate-skill")
        #expect(skill != nil)
        #expect(await loader.isActivated(name: "deactivate-skill") == true)
        
        // Deactivate via tool
        let toolCall = ToolCall(
            name: SkillsToolProvider.deactivateToolName,
            arguments: .object(["skill_name": .string("deactivate-skill")]),
            id: "test-4"
        )
        let result = try await provider.executeTool(toolCall)
        
        #expect(result.success == true)
        #expect(result.content.contains("Deactivated"))
        #expect(await loader.isActivated(name: "deactivate-skill") == false)
    }
    
    @Test("agent-skills-list-active returns empty when none activated")
    func testListActivatedEmpty() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let provider = SkillsToolProvider(loader: loader)
        
        let toolCall = ToolCall(
            name: SkillsToolProvider.listActivatedToolName,
            arguments: .object([:]),
            id: "test-5"
        )
        
        let result = try await provider.executeTool(toolCall)
        
        #expect(result.success == true)
        #expect(result.content.contains("No skills") || result.content.contains("activated"))
    }
    
    @Test("agent-skills-list-active returns activated skill names")
    func testListActivatedWithSkills() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        await Task.yield()
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        await loader.activateSkill(named: "skill-a")
        await loader.activateSkill(named: "skill-b")
        
        let provider = SkillsToolProvider(loader: loader)
        let toolCall = ToolCall(
            name: SkillsToolProvider.listActivatedToolName,
            arguments: .object([:]),
            id: "test-6"
        )
        
        let result = try await provider.executeTool(toolCall)
        
        #expect(result.success == true)
        #expect(result.content.contains("skill-a"))
        #expect(result.content.contains("skill-b"))
    }
    
    @Test("Unknown tool throws")
    func testUnknownTool() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let provider = SkillsToolProvider(loader: loader)
        
        let toolCall = ToolCall(
            name: "unknown_tool",
            arguments: .object([:]),
            id: "test-7"
        )
        
        do {
            _ = try await provider.executeTool(toolCall)
            Issue.record("Expected SkillsToolProvider.Error.unknownTool")
        } catch SkillsToolProvider.Error.unknownTool(let name) {
            #expect(name == "unknown_tool")
        }
    }
}
