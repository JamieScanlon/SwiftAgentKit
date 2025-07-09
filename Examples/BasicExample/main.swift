import Foundation
import SwiftAgentKit

// Example: Basic SwiftAgentKit usage
func basicExample() {
    print("=== SwiftAgentKit Basic Example ===")
    
    // Access version
    print("SwiftAgentKit version: \(swiftAgentKitVersion)")
    
    // Demonstrate basic functionality
    print("Hello from SwiftAgentKit!")
    print("SwiftAgentKit provides cross-platform logging capabilities for debugging and monitoring.")
}

// Example: Simple networking demonstration
func networkingExample() {
    print("=== SwiftAgentKit Networking Example ===")
    
    let baseURL = URL(string: "https://api.example.com")!
    let _ = RestAPIManager(baseURL: baseURL)
    print("RestAPIManager initialized successfully")
    print("Ready to make HTTP requests and handle streaming responses")
}

// Run examples
basicExample()
networkingExample() 