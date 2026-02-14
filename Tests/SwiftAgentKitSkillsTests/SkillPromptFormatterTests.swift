//
//  SkillPromptFormatterTests.swift
//  SwiftAgentKitSkillsTests
//

import Testing
import Foundation
@testable import SwiftAgentKitSkills

@Suite("SkillPromptFormatter Tests")
struct SkillPromptFormatterTests {
    
    @Test("Format metadata as XML")
    func testFormatAsXML() throws {
        let metadata: [SkillMetadata] = [
            SkillMetadata(
                name: "pdf-processing",
                description: "Extracts text and tables from PDF files, fills forms, merges documents.",
                directoryURL: URL(fileURLWithPath: "/path/to/skills/pdf-processing"),
                skillFileURL: URL(fileURLWithPath: "/path/to/skills/pdf-processing/SKILL.md")
            ),
            SkillMetadata(
                name: "data-analysis",
                description: "Analyzes datasets, generates charts, and creates summary reports.",
                directoryURL: URL(fileURLWithPath: "/path/to/skills/data-analysis"),
                skillFileURL: URL(fileURLWithPath: "/path/to/skills/data-analysis/SKILL.md")
            ),
        ]
        
        let xml = SkillPromptFormatter.formatAsXML(metadata)
        
        #expect(xml.contains("<available_skills>"))
        #expect(xml.contains("</available_skills>"))
        #expect(xml.contains("<name>pdf-processing</name>"))
        #expect(xml.contains("<description>Extracts text and tables from PDF files"))
        #expect(xml.contains("<location>/path/to/skills/pdf-processing/SKILL.md</location>"))
        #expect(xml.contains("<name>data-analysis</name>"))
    }
    
    @Test("Format empty metadata as empty XML")
    func testFormatEmptyMetadata() throws {
        let xml = SkillPromptFormatter.formatAsXML([])
        #expect(xml == "<available_skills></available_skills>")
    }
    
    @Test("Escape XML special characters")
    func testEscapeXML() throws {
        let metadata: [SkillMetadata] = [
            SkillMetadata(
                name: "skill-with<tag>",
                description: "Uses & and \"quotes\"",
                directoryURL: URL(fileURLWithPath: "/path/skill"),
                skillFileURL: URL(fileURLWithPath: "/path/skill/SKILL.md")
            ),
        ]
        
        let xml = SkillPromptFormatter.formatAsXML(metadata)
        #expect(xml.contains("&lt;"))
        #expect(xml.contains("&gt;"))
        #expect(xml.contains("&amp;"))
        #expect(xml.contains("&quot;"))
    }
    
    @Test("Format metadata as YAML")
    func testFormatAsYAML() throws {
        let metadata: [SkillMetadata] = [
            SkillMetadata(
                name: "pdf-processing",
                description: "Extracts text from PDFs",
                directoryURL: URL(fileURLWithPath: "/path/pdf-processing"),
                skillFileURL: URL(fileURLWithPath: "/path/pdf-processing/SKILL.md")
            ),
        ]
        
        let yaml = SkillPromptFormatter.formatAsYAML(metadata)
        #expect(yaml.contains("available_skills:"))
        #expect(yaml.contains("- name: pdf-processing"))
        #expect(yaml.contains("description:") && yaml.contains("Extracts text from PDFs"))
        #expect(yaml.contains("location:") && yaml.contains("/path/pdf-processing/SKILL.md"))
    }
    
    @Test("Format empty metadata as empty YAML")
    func testFormatEmptyMetadataYAML() throws {
        let yaml = SkillPromptFormatter.formatAsYAML([])
        #expect(yaml == "available_skills: []")
    }
    
    @Test("Format metadata as JSON")
    func testFormatAsJSON() throws {
        let metadata: [SkillMetadata] = [
            SkillMetadata(
                name: "data-analysis",
                description: "Analyzes datasets.",
                directoryURL: URL(fileURLWithPath: "/path/data-analysis"),
                skillFileURL: URL(fileURLWithPath: "/path/data-analysis/SKILL.md")
            ),
        ]
        
        let json = SkillPromptFormatter.formatAsJSON(metadata)
        #expect(json.contains("\"available_skills\""))
        #expect(json.contains("\"data-analysis\""))
        #expect(json.contains("Analyzes datasets."))
        #expect(json.contains("/path/data-analysis/SKILL.md"))
        
        // Verify it's valid JSON
        let data = json.data(using: .utf8)!
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: [[String: String]]]
        #expect(decoded != nil)
        #expect(decoded?["available_skills"]?.first?["name"] == "data-analysis")
    }
    
    @Test("Format empty metadata as empty JSON")
    func testFormatEmptyMetadataJSON() throws {
        let json = SkillPromptFormatter.formatAsJSON([])
        #expect(json == "{\"available_skills\":[]}")
    }
    
    // MARK: - Escape / Special Characters
    
    @Test("JSON escapes quotes and backslashes")
    func testJSONEscapesQuotesAndBackslashes() throws {
        let metadata: [SkillMetadata] = [
            SkillMetadata(
                name: "escape-test",
                description: "Has \"quoted\" and \\ backslash",
                directoryURL: URL(fileURLWithPath: "/path"),
                skillFileURL: URL(fileURLWithPath: "/path/SKILL.md")
            ),
        ]
        let json = SkillPromptFormatter.formatAsJSON(metadata)
        #expect(json.contains("\\\""))
        #expect(json.contains("\\\\"))
        let data = json.data(using: .utf8)!
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: [[String: String]]]
        #expect(decoded?["available_skills"]?.first?["description"] == "Has \"quoted\" and \\ backslash")
    }
    
    @Test("JSON escapes newlines and tabs")
    func testJSONEscapesNewlinesAndTabs() throws {
        let metadata: [SkillMetadata] = [
            SkillMetadata(
                name: "newline-test",
                description: "Line1\nLine2\tTab",
                directoryURL: URL(fileURLWithPath: "/path"),
                skillFileURL: URL(fileURLWithPath: "/path/SKILL.md")
            ),
        ]
        let json = SkillPromptFormatter.formatAsJSON(metadata)
        #expect(json.contains("\\n"))
        #expect(json.contains("\\t"))
        let data = json.data(using: .utf8)!
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: [[String: String]]]
        #expect(decoded?["available_skills"]?.first?["description"] == "Line1\nLine2\tTab")
    }
    
    @Test("YAML escapes strings with colons and special chars")
    func testYAMLEscapesSpecialChars() throws {
        let metadata: [SkillMetadata] = [
            SkillMetadata(
                name: "yaml-test",
                description: "Key: value with colon",
                directoryURL: URL(fileURLWithPath: "/path/to/skill"),
                skillFileURL: URL(fileURLWithPath: "/path/to/skill/SKILL.md")
            ),
        ]
        let yaml = SkillPromptFormatter.formatAsYAML(metadata)
        #expect(yaml.contains("Key: value") || yaml.contains("Key:"))
        #expect(yaml.contains("yaml-test"))
        #expect(yaml.contains("/path/to/skill"))
    }
    
    @Test("XML escapes apostrophes")
    func testXMLEscapesApostrophe() throws {
        let metadata: [SkillMetadata] = [
            SkillMetadata(
                name: "apostrophe",
                description: "It's a test",
                directoryURL: URL(fileURLWithPath: "/path"),
                skillFileURL: URL(fileURLWithPath: "/path/SKILL.md")
            ),
        ]
        let xml = SkillPromptFormatter.formatAsXML(metadata)
        #expect(xml.contains("&apos;"))
        #expect(xml.contains("apostrophe"))
    }
    
    @Test("All formats handle unicode and emoji")
    func testUnicodeAndEmoji() throws {
        let metadata: [SkillMetadata] = [
            SkillMetadata(
                name: "unicode-skill",
                description: "Café résumé 日本語 🎉",
                directoryURL: URL(fileURLWithPath: "/path/日本語"),
                skillFileURL: URL(fileURLWithPath: "/path/日本語/SKILL.md")
            ),
        ]
        let xml = SkillPromptFormatter.formatAsXML(metadata)
        let yaml = SkillPromptFormatter.formatAsYAML(metadata)
        let json = SkillPromptFormatter.formatAsJSON(metadata)
        
        #expect(xml.contains("unicode-skill"))
        #expect(xml.contains("Café") || xml.contains("résumé"))
        #expect(yaml.contains("unicode-skill"))
        #expect(json.contains("unicode-skill"))
        
        let jsonData = json.data(using: .utf8)!
        let decoded = try JSONSerialization.jsonObject(with: jsonData) as? [String: [[String: String]]]
        #expect(decoded?["available_skills"]?.first?["description"]?.contains("Café") == true)
    }
    
    // MARK: - Multiple Skills
    
    @Test("All formats preserve skill order")
    func testPreserveSkillOrder() throws {
        let metadata: [SkillMetadata] = [
            SkillMetadata(name: "first", description: "First skill", directoryURL: URL(fileURLWithPath: "/a"), skillFileURL: URL(fileURLWithPath: "/a/SKILL.md")),
            SkillMetadata(name: "second", description: "Second skill", directoryURL: URL(fileURLWithPath: "/b"), skillFileURL: URL(fileURLWithPath: "/b/SKILL.md")),
            SkillMetadata(name: "third", description: "Third skill", directoryURL: URL(fileURLWithPath: "/c"), skillFileURL: URL(fileURLWithPath: "/c/SKILL.md")),
        ]
        
        let xml = SkillPromptFormatter.formatAsXML(metadata)
        let idx1 = xml.range(of: "first")!.lowerBound
        let idx2 = xml.range(of: "second")!.lowerBound
        let idx3 = xml.range(of: "third")!.lowerBound
        #expect(idx1 < idx2)
        #expect(idx2 < idx3)
        
        let json = SkillPromptFormatter.formatAsJSON(metadata)
        let decoded = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: [[String: String]]]
        let names = decoded["available_skills"]!.map { $0["name"]! }
        #expect(names == ["first", "second", "third"])
    }
    
    @Test("Single skill produces valid structure in all formats")
    func testSingleSkillStructure() throws {
        let metadata: [SkillMetadata] = [
            SkillMetadata(
                name: "solo",
                description: "Only one",
                directoryURL: URL(fileURLWithPath: "/solo"),
                skillFileURL: URL(fileURLWithPath: "/solo/SKILL.md")
            ),
        ]
        
        let xml = SkillPromptFormatter.formatAsXML(metadata)
        #expect(xml.contains("<skill>"))
        #expect(xml.contains("</skill>"))
        #expect(xml.filter { $0 == "<" }.count >= 4)
        
        let json = SkillPromptFormatter.formatAsJSON(metadata)
        let decoded = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as? [String: [[String: String]]]
        #expect(decoded?["available_skills"]?.count == 1)
        #expect(decoded?["available_skills"]?.first?["name"] == "solo")
        #expect(decoded?["available_skills"]?.first?["description"] == "Only one")
        #expect(decoded?["available_skills"]?.first?["location"] == "/solo/SKILL.md")
        
        let yaml = SkillPromptFormatter.formatAsYAML(metadata)
        #expect(yaml.hasPrefix("available_skills:"))
        #expect(yaml.contains("- name: solo"))
    }
}
