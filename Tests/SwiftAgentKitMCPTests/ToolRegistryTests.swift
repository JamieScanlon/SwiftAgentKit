import Testing
import Foundation
import SwiftAgentKitMCP
import EasyJSON

@Suite struct ToolRegistryTests {
    @Test("ToolRegistry applies per-tool server-side timeout")
    func testPerToolTimeout() async throws {
        let registry = ToolRegistry()
        await registry.registerTool(
            name: "slow_tool",
            description: "Sleeps longer than cap",
            inputSchema: .object([:]),
            toolCallTimeout: 0.05,
            handler: { _ in
                try await Task.sleep(nanoseconds: 200_000_000)
                return .success("ok")
            }
        )
        let result = try await registry.executeTool(name: "slow_tool", arguments: [:])
        guard case .error(let code, let message) = result else {
            Issue.record("Expected .error, got \(result)")
            return
        }
        #expect(code == "TOOL_CALL_TIMEOUT")
        #expect(message.contains("timed out"))
    }

    @Test("ToolRegistry ignores non-positive toolCallTimeout")
    func testNonPositiveTimeoutMeansNoCap() async throws {
        let registry = ToolRegistry()
        await registry.registerTool(
            name: "fast",
            description: "x",
            inputSchema: .object([:]),
            toolCallTimeout: 0,
            handler: { _ in .success("done") }
        )
        let result = try await registry.executeTool(name: "fast", arguments: [:])
        guard case .success(let text) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(text == "done")
    }
}
