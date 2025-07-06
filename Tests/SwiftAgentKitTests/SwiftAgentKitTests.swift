import Testing
import Logging
@testable import SwiftAgentKit

@Suite("SwiftAgentKit Tests")
struct SwiftAgentKitTests {
    @Test("Initialization")
    func testSwiftAgentKitInitialization() throws {
        let kit = SwiftAgentKit()
        #expect(kit != nil)
        #expect(SwiftAgentKit.version == "1.0.0")
    }
    
    @Test("Manager Initialization")
    func testSwiftAgentKitManagerInitialization() throws {
        let config = SwiftAgentKitConfig(
            enableLogging: true,
            logLevel: .info,
            enableA2A: false,
            enableMCP: false
        )
        let manager = SwiftAgentKitManager(config: config)
        #expect(manager.getConfig().enableA2A == false)
        #expect(manager.getConfig().enableMCP == false)
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