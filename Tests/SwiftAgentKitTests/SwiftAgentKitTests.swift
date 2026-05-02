import Testing
import Logging
@testable import SwiftAgentKit

@Suite("SwiftAgentKit Tests")
struct SwiftAgentKitTests {
    @Test("Version")
    func testSwiftAgentKitVersion() throws {
        #expect(!swiftAgentKitVersion.isEmpty)
        let parts = swiftAgentKitVersion.split(separator: ".")
        #expect(parts.count >= 2, "Expected semver-style swiftAgentKitVersion (e.g. 0.15.0), got: \(swiftAgentKitVersion)")
    }
} 