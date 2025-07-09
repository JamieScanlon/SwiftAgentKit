import Foundation
import Logging
import SwiftAgentKit

// Example: Basic SwiftAgentKit usage
func basicExample() {
    let logger = Logger(label: "BasicExample")
    logger.info("=== SwiftAgentKit Basic Example ===")
    
    // Access version
    logger.info("SwiftAgentKit version: \(swiftAgentKitVersion)")
    
    // Demonstrate logging
    logger.info("Hello from SwiftAgentKit!")
    logger.debug("Debug message")
    logger.warning("Warning message")
    logger.error("Error message")
}

// Example: Custom logger configuration
func customLoggerExample() {
    let logger = Logger(label: "CustomLogger")
    logger.info("=== SwiftAgentKit Custom Logger Example ===")
    
    // Configure logging level
    LoggingSystem.bootstrap { label in
        var handler = StreamLogHandler.standardOutput(label: label)
        handler.logLevel = .debug
        return handler
    }
    
    let debugLogger = Logger(label: "DebugLogger")
    debugLogger.debug("This debug message should now be visible")
}

// Run examples
basicExample()
customLoggerExample() 