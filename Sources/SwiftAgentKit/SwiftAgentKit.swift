import Foundation
import Logging

/// SwiftAgentKit - A comprehensive toolkit for building local AI agents in Swift
public struct SwiftAgentKit {
    private let logger: Logger
    
    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "SwiftAgentKit")
    }
    
    /// Get the version of SwiftAgentKit
    public static let version = "1.0.0"
    
    /// Get the logger instance
    public func getLogger() -> Logger {
        return logger
    }
    
    /// Log a message with the default logger
    public func log(_ message: String, level: Logger.Level = .info) {
        logger.log(level: level, "\(message)")
    }
}

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
    private let core: SwiftAgentKit
    
    public init(config: SwiftAgentKitConfig = SwiftAgentKitConfig()) {
        self.config = config
        self.logger = Logger(label: "SwiftAgentKitManager")
        self.core = SwiftAgentKit(logger: logger)
        
        logger.info("SwiftAgentKit initialized with version \(SwiftAgentKit.version)")
        
        if config.enableA2A {
            logger.info("A2A module enabled")
        }
        
        if config.enableMCP {
            logger.info("MCP module enabled")
        }
    }
    
    /// Get the core SwiftAgentKit instance
    public func getCore() -> SwiftAgentKit {
        return core
    }
    
    /// Get the configuration
    public func getConfig() -> SwiftAgentKitConfig {
        return config
    }
    
    /// Get the logger
    public func getLogger() -> Logger {
        return logger
    }
} 