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
        .library(
            name: "SwiftAgentKitAdapters",
            targets: ["SwiftAgentKitAdapters"]),
        .library(
            name: "SwiftAgentKitOrchestrator",
            targets: ["SwiftAgentKitOrchestrator"]),
        .library(
            name: "SwiftAgentKitSkills",
            targets: ["SwiftAgentKitSkills"]),
        
        // Example executables
        .executable(
            name: "BasicExample",
            targets: ["BasicExample"]),
        .executable(
            name: "MCPExample",
            targets: ["MCPExample"]),
        .executable(
            name: "A2AExample",
            targets: ["A2AExample"]),
        .executable(
            name: "AdaptersExample",
            targets: ["AdaptersExample"]),
        .executable(
            name: "ToolAwareExample",
            targets: ["ToolAwareExample"]),
        .executable(
            name: "OpenAIAdapterExample",
            targets: ["OpenAIAdapterExample"]),
        .executable(
            name: "OrchestratorExample",
            targets: ["OrchestratorExample"]),
        .executable(
            name: "AgentCardConfigExample",
            targets: ["AgentCardConfigExample"]),
        .executable(
            name: "LLMProtocolAdapterExample",
            targets: ["LLMProtocolAdapterExample"]),
        .executable(
            name: "MCPServerExample",
            targets: ["MCPServerExample"]),
        .executable(
            name: "DynamicClientRegistrationExample",
            targets: ["DynamicClientRegistrationExample"]),

    ],
    dependencies: [
        // Core dependencies
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
//        .package(url: "https://github.com/vapor/vapor.git", revision: "4014016aad591a120f244f9b9e8a57252b7e62b4"),
        .package(url: "https://github.com/JamieScanlon/EasyJSON.git", from: "1.0.0"),
        
        // Logging dependency
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        
        // Optional dependencies for specific modules
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        
        // MCP dependency (0.11+ for Tool.Content API)
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        
        // OpenAI dependency
        .package(url: "https://github.com/MacPaw/OpenAI.git", from: "0.4.5"),
        
        // YAML parsing for Agent Skills
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
    ],
    targets: [
        // Core target - minimal functionality
        .target(
            name: "SwiftAgentKit",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "EasyJSON", package: "EasyJSON"),
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
            ],
            exclude: ["README.md"]),
        
        // Adapters module - Standard agent adapters
        .target(
            name: "SwiftAgentKitAdapters",
            dependencies: [
                "SwiftAgentKit",
                "SwiftAgentKitA2A",
                "SwiftAgentKitMCP",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "OpenAI", package: "OpenAI"),
            ],
            path: "Sources/SwiftAgentKitAdapters",
            exclude: ["README.md"]),
        
        // Orchestrator module - LLM orchestrator building blocks
        .target(
            name: "SwiftAgentKitOrchestrator",
            dependencies: [
                "SwiftAgentKit",
                "SwiftAgentKitA2A",
                "SwiftAgentKitMCP",
                "SwiftAgentKitAdapters",
                .product(name: "Logging", package: "swift-log"),
            ],
            exclude: ["README.md"]),
        
        // Skills module - Agent Skills spec support (https://agentskills.io/specification)
        .target(
            name: "SwiftAgentKitSkills",
            dependencies: [
                "SwiftAgentKit",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "EasyJSON", package: "EasyJSON"),
            ],
            exclude: ["README.md"]),
        
        // Example executables
        .executableTarget(
            name: "BasicExample",
            dependencies: [
                "SwiftAgentKit",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Examples/BasicExample"),
        
        .executableTarget(
            name: "MCPExample",
            dependencies: [
                "SwiftAgentKit",
                "SwiftAgentKitMCP",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Examples/MCPExample"),
        
        .executableTarget(
            name: "PKCEOAuthExample",
            dependencies: [
                "SwiftAgentKit",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Examples/PKCEOAuthExample"),
        
        .executableTarget(
            name: "A2AExample",
            dependencies: [
                "SwiftAgentKit",
                "SwiftAgentKitA2A",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Examples/A2AExample"),
        
        .executableTarget(
            name: "AdaptersExample",
            dependencies: [
                "SwiftAgentKit",
                "SwiftAgentKitA2A",
                "SwiftAgentKitAdapters",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Examples/AdaptersExample"),
        
        .executableTarget(
            name: "ToolAwareExample",
            dependencies: [
                "SwiftAgentKit",
                "SwiftAgentKitAdapters",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Examples/ToolAwareExample"),
        
        .executableTarget(
            name: "OpenAIAdapterExample",
            dependencies: [
                "SwiftAgentKit",
                "SwiftAgentKitAdapters",
                "SwiftAgentKitA2A",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Examples/OpenAIAdapterExample"),
        
        .executableTarget(
            name: "OrchestratorExample",
            dependencies: [
                "SwiftAgentKitOrchestrator",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Examples/OrchestratorExample"),
        
        .executableTarget(
            name: "AgentCardConfigExample",
            dependencies: [
                "SwiftAgentKitA2A",
                "SwiftAgentKitAdapters",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Examples/AgentCardConfigExample"),
        
        .executableTarget(
            name: "LLMProtocolAdapterExample",
            dependencies: [
                "SwiftAgentKit",
                "SwiftAgentKitA2A",
                "SwiftAgentKitAdapters",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Examples/LLMProtocolAdapterExample"),
        
        .executableTarget(
            name: "MCPServerExample",
            dependencies: [
                "SwiftAgentKit",
                "SwiftAgentKitMCP",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Examples/MCPServerExample"),
        
        .executableTarget(
            name: "DynamicClientRegistrationExample",
            dependencies: [
                "SwiftAgentKit",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Examples/DynamicClientRegistrationExample"),

        
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
        .testTarget(
            name: "SwiftAgentKitAdaptersTests",
            dependencies: ["SwiftAgentKitAdapters"]
        ),
        .testTarget(
            name: "SwiftAgentKitOrchestratorTests",
            dependencies: ["SwiftAgentKitOrchestrator"]
        ),
        .testTarget(
            name: "SwiftAgentKitSkillsTests",
            dependencies: ["SwiftAgentKitSkills"]
        ),
    ]
) 
