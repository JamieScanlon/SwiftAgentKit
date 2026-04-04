import Foundation
import Testing
@testable import SwiftAgentKitA2A

@Suite("A2AConfigHelper")
struct A2AConfigHelperTests {
    @Test("parseA2AConfig reads root toolCallTimeout and timeout alias")
    func testParseToolCallTimeout() throws {
        let json = """
        {
            "a2aServers": {},
            "toolCallTimeout": 200
        }
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("a2a-timeout-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let cfg = try A2AConfigHelper.parseA2AConfig(fileURL: url)
        #expect(cfg.toolCallTimeout == 200)
        
        let json2 = """
        {
            "a2aServers": {},
            "timeout": 75
        }
        """
        let url2 = FileManager.default.temporaryDirectory.appendingPathComponent("a2a-timeout2-\(UUID().uuidString).json")
        try json2.write(to: url2, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url2) }
        let cfg2 = try A2AConfigHelper.parseA2AConfig(fileURL: url2)
        #expect(cfg2.toolCallTimeout == 75)
        
        let json3 = """
        {
            "a2aServers": {},
            "toolCallTimeout": 5,
            "timeout": 99
        }
        """
        let url3 = FileManager.default.temporaryDirectory.appendingPathComponent("a2a-timeout3-\(UUID().uuidString).json")
        try json3.write(to: url3, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url3) }
        let cfg3 = try A2AConfigHelper.parseA2AConfig(fileURL: url3)
        #expect(cfg3.toolCallTimeout == 5)
    }
    
    @Test("parseA2AConfig reads per-server toolCallTimeout")
    func testParsePerServerTimeout() throws {
        let json = """
        {
            "a2aServers": {
                "my-agent": {
                    "run": { "url": "https://example.com/a2a" },
                    "timeout": 42
                }
            }
        }
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("a2a-per-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let cfg = try A2AConfigHelper.parseA2AConfig(fileURL: url)
        #expect(cfg.servers.count == 1)
        #expect(cfg.servers[0].toolCallTimeout == 42)
    }
}
