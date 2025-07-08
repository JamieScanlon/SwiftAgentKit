import Foundation
import Logging
import SwiftAgentKit

// Example: Basic SwiftAgentKit usage
func basicExample() {
    let logger = Logger(label: "BasicExample")
    logger.info("=== SwiftAgentKit Basic Example ===")
    
    // Initialize with default configuration
    let manager = SwiftAgentKitManager()
    
    // Log some messages
    manager.log("Hello from SwiftAgentKit!")
    manager.log("Version: \(swiftAgentKitVersion)")
    
    // Get configuration
    let config = manager.getConfig()
    logger.info("A2A enabled: \(config.enableA2A)")
    logger.info("MCP enabled: \(config.enableMCP)")
}

// Example: Custom configuration
func customConfigExample() {
    let logger = Logger(label: "CustomConfigExample")
    logger.info("=== SwiftAgentKit Custom Configuration Example ===")
    
    let config = SwiftAgentKitConfig(
        enableLogging: true,
        logLevel: .debug,
        enableA2A: true,
        enableMCP: false
    )
    
    let manager = SwiftAgentKitManager(config: config)
    let managerLogger = manager.getLogger()
    
    managerLogger.info("Custom configuration applied")
    managerLogger.debug("Debug logging is enabled")
}

// Run examples
basicExample()
customConfigExample() 