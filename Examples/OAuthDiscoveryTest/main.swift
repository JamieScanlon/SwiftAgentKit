/**
 OAuthDiscoveryTest: Connects to a local test server that returns 401 with
 WWW-Authenticate resource_metadata (Todoist-style) using the same code path
 as production: MCPManager.initialize(configFileURL:) → createClients →
 connectToRemoteServer(serverURL:authProvider:).
 Run with verbose logging to see exactly what happens.
 Usage:
   swift run OAuthDiscoveryTest [config-path]   # config defaults to Scripts/mcp-config-todoist-style.json
   SWIFT_LOG_LEVEL=debug swift run OAuthDiscoveryTest
 */
import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitMCP
import EasyJSON

@main
struct OAuthDiscoveryTest {
    static func main() async {
        // Verbose logging so we can see the full flow
        SwiftAgentKitLogging.bootstrap(
            logger: Logger(label: "com.swiftagentkit.oauth-discovery-test"),
            level: .debug,
            metadata: SwiftAgentKitLogging.metadata(("test", .string("OAuthDiscovery")))
        )
        let logger = SwiftAgentKitLogging.logger(for: .mcp("OAuthDiscoveryTest"))
        logger.info("=== OAuth Discovery test (Todoist-style 401) ===")

        let configPath: String
        if CommandLine.arguments.count > 1 {
            configPath = CommandLine.arguments[1]
        } else {
            // Default: config in Scripts folder
            let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            configPath = scriptDir.appendingPathComponent("Scripts").appendingPathComponent("mcp-config-todoist-style.json").path
        }
        let configURL = URL(fileURLWithPath: configPath)
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            logger.error("Config file not found: \(configURL.path)")
            print("Usage: swift run OAuthDiscoveryTest [path-to-config.json]")
            print("Create Scripts/mcp-config-todoist-style.json or pass a config with remoteServers.todoist.url = http://127.0.0.1:8765/mcp")
            exit(1)
        }
        logger.info("Using config: \(configURL.path)")

        let manager = MCPManager(connectionTimeout: 10.0)
        do {
            try await manager.initialize(configFileURL: configURL)
            let clients = await manager.clients
            logger.info("Result: connected to \(clients.count) server(s)")
        } catch {
            logger.error("Result: error: \(String(describing: error))")
            print("Error type: \(type(of: error))")
            print("Error: \(error)")
        }
    }
}
