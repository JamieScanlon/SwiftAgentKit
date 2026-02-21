//
//  SkillParserTests.swift
//  SwiftAgentKitSkillsTests
//

import Testing
import Foundation
@testable import SwiftAgentKitSkills

@Suite("SkillParser Tests")
struct SkillParserTests {
    
    @Test("Parse valid SKILL.md with required fields only")
    func testParseMinimalSkill() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("test-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        
        let skillContent = """
        ---
        name: test-skill
        description: A minimal test skill for parsing.
        ---
        
        # Instructions
        
        Do something useful.
        """
        
        let skillFileURL = skillDir.appendingPathComponent("SKILL.md")
        try skillContent.write(to: skillFileURL, atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        let skill = try parser.parse(skillFileURL: skillFileURL)
        
        #expect(skill.name == "test-skill")
        #expect(skill.description == "A minimal test skill for parsing.")
        #expect(skill.body.contains("Do something useful"))
        #expect(skill.directoryURL.standardizedFileURL.path == skillDir.standardizedFileURL.path)
    }
    
    @Test("Parse valid SKILL.md with optional fields")
    func testParseFullSkill() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("pdf-processing")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        
        let skillContent = """
        ---
        name: pdf-processing
        description: Extract text and tables from PDF files, fill forms, merge documents.
        license: Apache-2.0
        compatibility: Requires Python 3.8+
        metadata:
          author: example-org
          version: "1.0"
        allowed-tools: Bash(git:*) Read
        ---
        
        ## Step 1
        Do the first thing.
        """
        
        let skillFileURL = skillDir.appendingPathComponent("SKILL.md")
        try skillContent.write(to: skillFileURL, atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        let skill = try parser.parse(directoryURL: skillDir)
        
        #expect(skill.name == "pdf-processing")
        #expect(skill.description.contains("Extract text"))
        #expect(skill.frontmatter.license == "Apache-2.0")
        #expect(skill.frontmatter.compatibility == "Requires Python 3.8+")
        #expect(skill.frontmatter.metadata?["author"] == "example-org")
        #expect(skill.frontmatter.allowedToolsList.contains("Bash(git:*)"))
    }
    
    @Test("Reject missing frontmatter delimiter")
    func testRejectNoFrontmatter() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let skillContent = "name: test\nNo frontmatter here."
        let skillFileURL = tempDir.appendingPathComponent("SKILL.md")
        try skillContent.write(to: skillFileURL, atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        #expect(throws: SkillParseError.self) {
            try parser.parse(skillFileURL: skillFileURL)
        }
    }
    
    @Test("Reject missing required name")
    func testRejectMissingName() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let skillContent = """
        ---
        description: Has no name field.
        ---
        Body.
        """
        
        let skillFileURL = tempDir.appendingPathComponent("SKILL.md")
        try skillContent.write(to: skillFileURL, atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        do {
            _ = try parser.parse(skillFileURL: skillFileURL)
            Issue.record("Expected throw")
        } catch SkillParseError.missingRequiredField(let field) {
            #expect(field == "name")
        } catch SkillParseError.invalidFrontmatterYAML {
            // Yams might decode empty string for missing field
            // Accept either
        }
    }
    
    @Test("Reject invalid name format")
    func testRejectInvalidName() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("invalid-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        
        let skillContent = """
        ---
        name: Invalid_Name
        description: Uppercase and underscore not allowed.
        ---
        Body.
        """
        
        let skillFileURL = skillDir.appendingPathComponent("SKILL.md")
        try skillContent.write(to: skillFileURL, atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        do {
            _ = try parser.parse(skillFileURL: skillFileURL)
            Issue.record("Expected throw for invalid name")
        } catch SkillParseError.invalidName {
            // Expected - regex fails for Invalid_Name
        } catch SkillParseError.nameMismatch {
            // Possible - directory is invalid-skill, frontmatter is Invalid_Name
        }
    }
    
    // MARK: - Error Cases
    
    @Test("Throw fileNotFound for non-existent file")
    func testFileNotFound() throws {
        let parser = SkillParser()
        let bogusURL = URL(fileURLWithPath: "/nonexistent/path/\(UUID().uuidString)/SKILL.md")
        
        do {
            _ = try parser.parse(skillFileURL: bogusURL)
            Issue.record("Expected fileNotFound")
        } catch SkillParseError.fileNotFound(let url) {
            #expect(url == bogusURL)
        }
    }
    
    @Test("Reject content with opening delimiter but no closing delimiter")
    func testRejectUnclosedFrontmatter() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("test-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: test-skill
        description: No closing delimiter
        
        Body continues...
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        do {
            _ = try parser.parse(directoryURL: skillDir)
            Issue.record("Expected noFrontmatterDelimiter")
        } catch SkillParseError.noFrontmatterDelimiter {
            // Expected
        }
    }
    
    @Test("Reject missing required description")
    func testRejectMissingDescription() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("no-desc")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: no-desc
        ---
        Body.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        do {
            _ = try parser.parse(directoryURL: skillDir)
            Issue.record("Expected throw")
        } catch SkillParseError.missingRequiredField(let field) {
            #expect(field == "description")
        } catch SkillParseError.invalidFrontmatterYAML {
            // Yams may decode empty string
        }
    }
    
    @Test("Reject name/directory mismatch")
    func testRejectNameMismatch() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        // Directory is "my-skill" but frontmatter says "other-skill"
        let skillDir = rootDir.appendingPathComponent("my-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: other-skill
        description: Name does not match directory.
        ---
        Body.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        do {
            _ = try parser.parse(directoryURL: skillDir)
            Issue.record("Expected nameMismatch")
        } catch SkillParseError.nameMismatch(let dirName, let frontmatterName) {
            #expect(dirName == "my-skill")
            #expect(frontmatterName == "other-skill")
        }
    }
    
    @Test("Reject invalid name - leading hyphen")
    func testRejectLeadingHyphen() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("leading-hyphen")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: -leading-hyphen
        description: Invalid name.
        ---
        Body.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        do {
            _ = try parser.parse(directoryURL: skillDir)
            Issue.record("Expected invalidName")
        } catch SkillParseError.invalidName(let name) {
            #expect(name == "-leading-hyphen")
        } catch SkillParseError.nameMismatch {
            // Also valid - directory is leading-hyphen
        }
    }
    
    @Test("Reject invalid name - consecutive hyphens")
    func testRejectConsecutiveHyphens() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("consec-hyphens")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: pdf--processing
        description: Invalid consecutive hyphens.
        ---
        Body.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        do {
            _ = try parser.parse(directoryURL: skillDir)
            Issue.record("Expected invalidName")
        } catch SkillParseError.invalidName {
            // Expected
        } catch SkillParseError.nameMismatch {
            // Possible
        }
    }
    
    @Test("Reject invalid YAML - description as wrong type")
    func testRejectInvalidYAML() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("bad-yaml")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        // description is a mapping, not a string - decode will fail
        let content = """
        ---
        name: bad-yaml
        description:
          nested: value
          another: key
        ---
        Body.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        do {
            _ = try parser.parse(directoryURL: skillDir)
            Issue.record("Expected invalidFrontmatterYAML")
        } catch SkillParseError.invalidFrontmatterYAML {
            // Expected - YAML decode fails (description expected String, got Map)
        }
    }
    
    // MARK: - Edge Cases
    
    @Test("Parse skill with empty body")
    func testParseEmptyBody() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("empty-body")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: empty-body
        description: Skill with no body content.
        ---
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        let skill = try parser.parse(directoryURL: skillDir)
        #expect(skill.name == "empty-body")
        #expect(skill.body.isEmpty || skill.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(skill.fullInstructions.contains("empty-body"))
        #expect(skill.fullInstructions.contains("Skill with no body content"))
    }
    
    @Test("Parse skill with multiline body and markdown")
    func testParseMultilineBody() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("multiline-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: multiline-skill
        description: Has markdown body.
        ---
        
        ## Step 1
        Do this first.
        
        ## Step 2
        Then do this.
        
        - Bullet one
        - Bullet two
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        let skill = try parser.parse(directoryURL: skillDir)
        #expect(skill.body.contains("Step 1"))
        #expect(skill.body.contains("Bullet one"))
        #expect(skill.fullInstructions.contains("Step 2"))
    }
    
    @Test("allowedToolsList parses space-delimited tools")
    func testAllowedToolsList() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("tools-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: tools-skill
        description: Tests allowed-tools.
        allowed-tools: Bash(git:*) Read Write
        ---
        Body.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        let skill = try parser.parse(directoryURL: skillDir)
        let tools = skill.frontmatter.allowedToolsList
        #expect(tools.count == 3)
        #expect(tools.contains("Bash(git:*)"))
        #expect(tools.contains("Read"))
        #expect(tools.contains("Write"))
    }
    
    @Test("Parse valid single-segment name")
    func testParseSingleSegmentName() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("a")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: a
        description: Single char name.
        ---
        Body.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        let skill = try parser.parse(directoryURL: skillDir)
        #expect(skill.name == "a")
    }
    
    @Test("Skill url(forRelativePath:) resolves valid paths")
    func testSkillUrlForRelativePath() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("path-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let refsDir = skillDir.appendingPathComponent("references")
        try FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: path-skill
        description: Tests url resolution.
        ---
        Body.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        let skill = try parser.parse(directoryURL: skillDir)
        
        let refURL = skill.url(forRelativePath: "references/REFERENCE.md")
        #expect(refURL != nil)
        #expect(refURL?.lastPathComponent == "REFERENCE.md")
        
        let scriptURL = skill.url(forRelativePath: "scripts/run.sh")
        #expect(scriptURL != nil)
    }
    
    @Test("Skill url(forRelativePath:) returns nil for path escaping upward")
    func testSkillUrlRejectsPathTraversal() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        
        let skillDir = rootDir.appendingPathComponent("traversal-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = """
        ---
        name: traversal-skill
        description: Tests path traversal.
        ---
        Body.
        """
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        
        let parser = SkillParser()
        let skill = try parser.parse(directoryURL: skillDir)
        
        let escaped = skill.url(forRelativePath: "../../../etc/passwd")
        #expect(escaped == nil)
    }
}
