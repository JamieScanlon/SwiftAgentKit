import Foundation
import SwiftAgentKit
import Logging

private func configureLogging() {
    // Example: Bootstrap with optional filter
    // You can filter logs by level, scope, metadata keys, or keywords
    // Uncomment the filter parameter to enable filtering:
    
    // let filter = SwiftAgentKitLogging.LogFilter(
    //     level: .minimum(.info),  // Only show info and above
    //     keywords: ["error", "warning"]  // Only show logs containing these keywords
    // )
    
    SwiftAgentKitLogging.bootstrap(
        logger: Logger(label: "com.example.swiftagentkit.basic"),
        level: .info,
        metadata: SwiftAgentKitLogging.metadata(("example", .string("Basic")))
        // filter: filter  // Uncomment to enable filtering
    )
}

// Example: Basic SwiftAgentKit usage
func basicExample() {
    configureLogging()
    let logger = SwiftAgentKitLogging.logger(for: .examples("BasicExample"))
    print("=== SwiftAgentKit Basic Example ===")
    
    // Access version
    print("SwiftAgentKit version: \(swiftAgentKitVersion)")
    
    // Demonstrate basic functionality
    print("Hello from SwiftAgentKit!")
    print("SwiftAgentKit provides cross-platform logging capabilities for debugging and monitoring.")
    logger.info("Basic example completed")
}

// Example: Simple networking demonstration
func networkingExample() {
    configureLogging()
    let logger = SwiftAgentKitLogging.logger(for: .examples("NetworkingExample"))
    print("=== SwiftAgentKit Networking Example ===")
    
    let baseURL = URL(string: "https://api.example.com")!
    let _ = RestAPIManager(baseURL: baseURL)
    print("RestAPIManager initialized successfully")
    print("Ready to make HTTP requests and handle streaming responses")
    logger.info("RestAPIManager initialized for \(baseURL.absoluteString)")
}

// Run examples
basicExample()
networkingExample() 