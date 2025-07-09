import Testing
import Logging
@testable import SwiftAgentKit

@Suite("SwiftAgentKit Tests")
struct SwiftAgentKitTests {
    @Test("Version")
    func testSwiftAgentKitVersion() throws {
        #expect(swiftAgentKitVersion == "0.1.3")
    }
    
    @Test("Logger Functionality")
    func testLoggerFunctionality() throws {
        let logger = Logger(label: "TestLogger")
        // Logging output is not checked, just ensure no crash
        logger.info("Test info message")
        logger.debug("Test debug message")
        logger.warning("Test warning message")
        logger.error("Test error message")
    }
} 