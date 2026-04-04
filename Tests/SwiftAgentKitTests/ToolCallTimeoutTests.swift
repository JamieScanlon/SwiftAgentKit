import Testing
import SwiftAgentKit

@Suite("Tool call timeout")
struct ToolCallTimeoutTests {
    @Test("returns value when operation finishes before deadline")
    func completesUnderTimeout() async throws {
        let value = try await withToolCallTimeout(2.0, toolName: nil) {
            try await Task.sleep(nanoseconds: 1_000_000)
            return "ok"
        }
        #expect(value == "ok")
    }

    @Test("throws ToolCallTimeoutError when operation exceeds deadline")
    func throwsOnTimeout() async throws {
        await #expect(throws: ToolCallTimeoutError.self) {
            try await withToolCallTimeout(0.05, toolName: "slow_tool") {
                try await Task.sleep(nanoseconds: 500_000_000)
                return 0
            }
        }
    }

    @Test("ToolCallTimeoutError message includes tool name")
    func timeoutMessageIncludesToolName() throws {
        let err = ToolCallTimeoutError(timeout: 300, toolName: "my_tool")
        #expect(err.message.contains("my_tool"))
        #expect(err.message.contains("300"))
    }
}
