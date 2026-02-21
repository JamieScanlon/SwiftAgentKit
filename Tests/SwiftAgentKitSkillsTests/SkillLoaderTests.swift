//
//  SkillLoaderTests.swift
//  SwiftAgentKitSkillsTests
//

import Testing
import Foundation
@testable import SwiftAgentKitSkills

@Suite("SkillLoader Tests")
struct SkillLoaderTests {
    
    @Test("Discover skills in directory")
    func testDiscoverSkills() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        // Create two valid skills
        for name in ["skill-a", "skill-b"] {
            let skillDir = rootDir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
            let content = """
            ---
            name: \(name)
            description: Test skill \(name).
            ---
            Body.
            """
            try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let urls = try await loader.discoverSkills()
        
        #expect(urls.count == 2)
        #expect(urls.map { $0.lastPathComponent }.sorted() == ["skill-a", "skill-b"])
    }
    
    @Test("Load metadata from directory")
    func testLoadMetadata() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("meta-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: meta-skill
        description: Skill for metadata loading test.
        ---
        Full body here.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let metadata = try await loader.loadMetadata()
        
        #expect(metadata.count == 1)
        #expect(metadata[0].name == "meta-skill")
        #expect(metadata[0].description == "Skill for metadata loading test.")
    }
    
    @Test("Load single skill by name")
    func testLoadSkillByName() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("named-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: named-skill
        description: Single skill load test.
        ---
        Body content.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let skill = try await loader.loadSkill(named: "named-skill")
        
        #expect(skill != nil)
        #expect(skill?.name == "named-skill")
        #expect(skill?.body.contains("Body content") == true)
    }
    
    @Test("Return nil for non-existent skill")
    func testLoadNonExistentSkill() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let skill = try await loader.loadSkill(named: "does-not-exist")
        
        #expect(skill == nil)
    }
    
    // MARK: - Activation Tracking
    
    @Test("Activate and deactivate skill")
    func testActivateDeactivate() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("activate-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: activate-skill
        description: For activation test.
        ---
        Body.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let skill = try await loader.loadSkill(named: "activate-skill")
        #expect(skill != nil)
        
        #expect(await loader.activatedSkills.isEmpty)
        #expect(await loader.isActivated(name: "activate-skill") == false)
        
        await loader.activate(skill!)
        #expect(await loader.activatedSkills == Set(["activate-skill"]))
        #expect(await loader.isActivated(name: "activate-skill") == true)
        
        await loader.deactivateSkill(named: "activate-skill")
        #expect(await loader.activatedSkills.isEmpty)
        #expect(await loader.isActivated(name: "activate-skill") == false)
    }
    
    @Test("Activate skill by name")
    func testActivateSkillByName() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        await loader.activateSkill(named: "by-name-skill")
        #expect(await loader.isActivated(name: "by-name-skill") == true)
        await loader.deactivateSkill(named: "by-name-skill")
        #expect(await loader.activatedSkills.isEmpty)
    }
    
    @Test("Deactivate all skills")
    func testDeactivateAll() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        await loader.activateSkill(named: "skill-1")
        await loader.activateSkill(named: "skill-2")
        #expect(await loader.activatedSkills.count == 2)
        
        await loader.deactivateAllSkills()
        #expect(await loader.activatedSkills.isEmpty)
    }
    
    @Test("loadAndActivateSkill loads and activates in one call")
    func testLoadAndActivate() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("load-activate-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: load-activate-skill
        description: Load and activate test.
        ---
        Body.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let loader = SkillLoader(skillsDirectoryURL: rootDir)
        let skill = try await loader.loadAndActivateSkill(named: "load-activate-skill")
        #expect(skill != nil)
        #expect(await loader.isActivated(name: "load-activate-skill") == true)
    }
}
