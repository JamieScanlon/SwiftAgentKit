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
        
        let loader = SkillLoader()
        let urls = try await loader.discoverSkills(in: rootDir)
        
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
        
        let loader = SkillLoader()
        let metadata = try await loader.loadMetadata(from: rootDir)
        
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
        
        let loader = SkillLoader()
        let skill = try await loader.loadSkill(named: "named-skill", from: rootDir)
        
        #expect(skill != nil)
        #expect(skill?.name == "named-skill")
        #expect(skill?.body.contains("Body content") == true)
    }
    
    @Test("Return nil for non-existent skill")
    func testLoadNonExistentSkill() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let loader = SkillLoader()
        let skill = try await loader.loadSkill(named: "does-not-exist", from: rootDir)
        
        #expect(skill == nil)
    }
}
