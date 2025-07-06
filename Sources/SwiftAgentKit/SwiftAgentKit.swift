import Foundation
import os

/// SwiftAgentKit - A comprehensive toolkit for building local AI agents in Swift
public struct SwiftAgentKit {
    private let logger: Logger
    
    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(subsystem: "com.swiftagentkit", category: "SwiftAgentKit")
    }
    
    /// Get the version of SwiftAgentKit
    public static let version = "1.0.0"
    
    /// Get the logger instance
    public func getLogger() -> Logger {
        return logger
    }
    
    /// Log a message with the default logger
    public func log(_ message: String, level: OSLogType = .info) {
        logger.log(level: level, "\(message)")
    }
}

/// Logger wrapper using os.Logger for better system integration
public struct Logger {
    private let osLogger: os.Logger
    
    public init(subsystem: String, category: String) {
        self.osLogger = os.Logger(subsystem: subsystem, category: category)
    }
    
    public init(label: String) {
        // For backward compatibility, create a logger with a default subsystem
        self.osLogger = os.Logger(subsystem: "com.swiftagentkit", category: label)
    }
    
    public func log(level: OSLogType, _ message: String) {
        osLogger.log(level: level, "\(message)")
    }
    
    public func info(_ message: String) {
        osLogger.info("\(message)")
    }
    
    public func debug(_ message: String) {
        osLogger.debug("\(message)")
    }
    
    public func warning(_ message: String) {
        osLogger.warning("\(message)")
    }
    
    public func error(_ message: String) {
        osLogger.error("\(message)")
    }
    
    public func notice(_ message: String) {
        osLogger.notice("\(message)")
    }
    
    public func critical(_ message: String) {
        osLogger.critical("\(message)")
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
    public func getLogger() -> Logger {
        return logger
    }
} 