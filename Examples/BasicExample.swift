import Foundation
import SwiftAgentKit

// Example: Basic SwiftAgentKit usage
func basicExample() {
    print("=== SwiftAgentKit Basic Example ===")
    
    // Initialize with default configuration
    let manager = SwiftAgentKitManager()
    let core = manager.getCore()
    
    // Log some messages
    core.log("Hello from SwiftAgentKit!")
    core.log("Version: \(SwiftAgentKit.version)")
    
    // Get configuration
    let config = manager.getConfig()
    print("A2A enabled: \(config.enableA2A)")
    print("MCP enabled: \(config.enableMCP)")
    print("Intercom enabled: \(config.enableIntercom)")
}

// Example: Custom configuration
func customConfigExample() {
    print("\n=== SwiftAgentKit Custom Configuration Example ===")
    
    let config = SwiftAgentKitConfig(
        enableLogging: true,
        logLevel: .debug,
        enableA2A: true,
        enableMCP: false,
        enableIntercom: true
    )
    
    let manager = SwiftAgentKitManager(config: config)
    let logger = manager.getLogger()
    
    logger.info("Custom configuration applied")
    logger.debug("Debug logging is enabled")
}

// Run examples
basicExample()
customConfigExample() 