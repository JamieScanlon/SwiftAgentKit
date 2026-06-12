//
//  ACPConfigHelperTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import Testing
@testable import SwiftAgentKitACP

@Suite("ACP Config")
struct ACPConfigHelperTests {
    @Test("Parse agent boot calls")
    func parseConfig() throws {
        let json = """
        {
          "toolCallTimeout": 120,
          "globalEnvironment": {"API_KEY": "test"},
          "agentBootCalls": [
            {
              "name": "demo-agent",
              "command": "echo",
              "arguments": ["acp"],
              "environment": {}
            }
          ]
        }
        """
        let url = ACPTestHelpers.tempFileURL(prefix: "acp-config")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = try ACPConfigHelper.parseACPConfig(fileURL: url)
        #expect(config.toolCallTimeout == 120)
        #expect(config.agentBootCalls.count == 1)
        #expect(config.agentBootCalls[0].name == "demo-agent")
        #expect(config.agentBootCalls[0].command == "echo")
        #expect(config.agentBootCalls[0].useShell == false)
    }

    @Test("Parse useShell and per-server timeout")
    func parseOptionalFields() throws {
        let json = """
        {
          "agentBootCalls": [
            {
              "name": "shell-agent",
              "command": "run.sh",
              "arguments": [],
              "environment": {},
              "useShell": true,
              "toolCallTimeout": 45
            }
          ]
        }
        """
        let url = ACPTestHelpers.tempFileURL(prefix: "acp-config-opts")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = try ACPConfigHelper.parseACPConfig(fileURL: url)
        #expect(config.agentBootCalls[0].useShell == true)
        #expect(config.agentBootCalls[0].toolCallTimeout == 45)
    }

    @Test("Integer toolCallTimeout is accepted")
    func intTimeout() throws {
        let json = #"{"toolCallTimeout": 90}"#
        let url = ACPTestHelpers.tempFileURL(prefix: "acp-config-timeout")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = try ACPConfigHelper.parseACPConfig(fileURL: url)
        #expect(config.toolCallTimeout == 90)
    }

    @Test("Invalid config throws")
    func invalidConfig() {
        let url = ACPTestHelpers.tempFileURL(prefix: "acp-config-bad", extension: "txt")
        try? "not json".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: (any Error).self) {
            _ = try ACPConfigHelper.parseACPConfig(fileURL: url)
        }
    }

    @Test("Non-object root JSON throws invalidACPConfig")
    func nonObjectRoot() throws {
        let url = ACPTestHelpers.tempFileURL(prefix: "acp-config-array")
        try "[1, 2, 3]".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ACPConfigHelper.ConfigError.self) {
            _ = try ACPConfigHelper.parseACPConfig(fileURL: url)
        }
    }

    @Test("Empty config yields defaults")
    func emptyConfig() throws {
        let json = "{}"
        let url = ACPTestHelpers.tempFileURL(prefix: "acp-config-empty")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = try ACPConfigHelper.parseACPConfig(fileURL: url)
        #expect(config.agentBootCalls.isEmpty)
        #expect(config.toolCallTimeout == nil)
    }
}

@Suite("ACP Config Model")
struct ACPConfigModelTests {
    @Test("ServerBootCall initializer")
    func bootCallInit() {
        let boot = ACPConfig.ServerBootCall(
            name: "n",
            command: "cmd",
            arguments: ["a"],
            environment: .object([:]),
            useShell: true,
            toolCallTimeout: 10
        )
        #expect(boot.name == "n")
        #expect(boot.useShell == true)
        #expect(boot.toolCallTimeout == 10)
    }
}
