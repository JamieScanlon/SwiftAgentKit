import Foundation
import Logging

/// SwiftAgentKit - A comprehensive toolkit for building local AI agents in Swift

/// Get the version of SwiftAgentKit
public let swiftAgentKitVersion = "1.0.0"

/// Core configuration for SwiftAgentKit
public struct SwiftAgentKitConfig {
    public let enableLogging: Bool
    public let logLevel: Logger.Level
    public let enableA2A: Bool
    public let enableMCP: Bool
    
    public init(
        enableLogging: Bool = true,
        logLevel: Logger.Level = .info,
        enableA2A: Bool = false,
        enableMCP: Bool = false
    ) {
        self.enableLogging = enableLogging
        self.logLevel = logLevel
        self.enableA2A = enableA2A
        self.enableMCP = enableMCP
    }
}

/// Main SwiftAgentKit manager class
public class SwiftAgentKitManager {
    private let config: SwiftAgentKitConfig
    private let logger: Logger
    
    public init(config: SwiftAgentKitConfig = SwiftAgentKitConfig()) {
        self.config = config
        self.logger = Logger(label: "SwiftAgentKitManager")
        
        logger.info("SwiftAgentKit initialized with version \(swiftAgentKitVersion)")
        
        if config.enableA2A {
            logger.info("A2A module enabled")
        }
        
        if config.enableMCP {
            logger.info("MCP module enabled")
        }
    }
    
    /// Get the configuration
    public func getConfig() -> SwiftAgentKitConfig {
        return config
    }
    
    /// Get the logger
    public func getLogger() -> Logger {
        return logger
    }
    
    /// Log a message with the default logger
    public func log(_ message: String, level: Logger.Level = .info) {
        logger.log(level: level, "\(message)")
    }
} 