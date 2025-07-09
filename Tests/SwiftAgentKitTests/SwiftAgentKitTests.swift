import Testing
import Logging
@testable import SwiftAgentKit

@Suite("SwiftAgentKit Tests")
struct SwiftAgentKitTests {
    @Test("Version")
    func testSwiftAgentKitVersion() throws {
        #expect(swiftAgentKitVersion == "0.1.3")
    }
} 