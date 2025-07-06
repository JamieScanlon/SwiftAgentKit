// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftAgentKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .visionOS(.v1)
    ],
    products: [
        // Core library - always included
        .library(
            name: "SwiftAgentKit",
            targets: ["SwiftAgentKit"]),
        
        // Optional sub-packages
        .library(
            name: "SwiftAgentKitA2A",
            targets: ["SwiftAgentKitA2A"]),
        .library(
            name: "SwiftAgentKitMCP",
            targets: ["SwiftAgentKitMCP"]),
        
        // Example executable
        .executable(
            name: "BasicExample",
            targets: ["BasicExample"]),
    ],
    dependencies: [
        // Core dependencies
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(url: "https://github.com/JamieScanlon/EasyJSON.git", from: "1.0.0"),
        
        // Logging dependency
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        
        // Optional dependencies for specific modules
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        
        // MCP dependency
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.9.0"),
    ],
    targets: [
        // Core target - minimal functionality
        .target(
            name: "SwiftAgentKit",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]),
        
        // A2A (Agent-to-Agent) module
        .target(
            name: "SwiftAgentKitA2A",
            dependencies: [
                "SwiftAgentKit",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "EasyJSON", package: "EasyJSON"),
                .product(name: "Logging", package: "swift-log"),
            ]),
        
        // MCP (Model Context Protocol) module
        .target(
            name: "SwiftAgentKitMCP",
            dependencies: [
                "SwiftAgentKit",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "EasyJSON", package: "EasyJSON"),
                .product(name: "Logging", package: "swift-log"),
            ]),
        
        // Example executable
        .executableTarget(
            name: "BasicExample",
            dependencies: [
                "SwiftAgentKit",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Examples"),
        
        // Test targets
        .testTarget(
            name: "SwiftAgentKitTests",
            dependencies: ["SwiftAgentKit"]
        ),
        .testTarget(
            name: "SwiftAgentKitA2ATests",
            dependencies: ["SwiftAgentKitA2A"]
        ),
        .testTarget(
            name: "SwiftAgentKitMCPTests",
            dependencies: ["SwiftAgentKitMCP"]
        ),
    ]
) 