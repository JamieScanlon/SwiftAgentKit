import Foundation
import os

/// SwiftAgentKit - A comprehensive toolkit for building local AI agents in Swift
public struct SwiftAgentKit {
    private let logger: os.Logger
    
    public init(logger: os.Logger? = nil) {
        self.logger = logger ?? os.Logger(subsystem: "com.swiftagentkit", category: "SwiftAgentKit")
    }
    
    /// Get the version of SwiftAgentKit
    public static let version = "1.0.0"
    
    /// Get the logger instance
    public func getLogger() -> os.Logger {
        return logger
    }
    
    /// Log a message with the default logger
    public func log(_ message: String, level: OSLogType = .info) {
        logger.log(level: level, "\(message)")
    }
}

/// Core configuration for SwiftAgentKit
public struct SwiftAgentKitConfig {
    public let enableLogging: Bool
    public let logLevel: OSLogType
    public let enableA2A: Bool
    public let enableMCP: Bool
    public let enableIntercom: Bool
    
    public init(
        enableLogging: Bool = true,
        logLevel: OSLogType = .info,
        enableA2A: Bool = false,
        enableMCP: Bool = false,
        enableIntercom: Bool = false
    ) {
        self.enableLogging = enableLogging
        self.logLevel = logLevel
        self.enableA2A = enableA2A
        self.enableMCP = enableMCP
        self.enableIntercom = enableIntercom
    }
}

/// Main SwiftAgentKit manager class
public class SwiftAgentKitManager {
    private let config: SwiftAgentKitConfig
    private let logger: os.Logger
    private let core: SwiftAgentKit
    
    public init(config: SwiftAgentKitConfig = SwiftAgentKitConfig()) {
        self.config = config
        self.logger = os.Logger(subsystem: "com.swiftagentkit", category: "SwiftAgentKitManager")
        self.core = SwiftAgentKit(logger: logger)
        
        logger.info("SwiftAgentKit initialized with version \(SwiftAgentKit.version)")
        
        if config.enableA2A {
            logger.info("A2A module enabled")
        }
        
        if config.enableMCP {
            logger.info("MCP module enabled")
        }
        
        if config.enableIntercom {
            logger.info("Intercom module enabled")
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
    public func getLogger() -> os.Logger {
        return logger
    }
} 