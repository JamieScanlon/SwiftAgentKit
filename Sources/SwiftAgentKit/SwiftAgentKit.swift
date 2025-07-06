import Foundation

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

/// Simple logger implementation
public struct Logger {
    private let label: String
    
    public init(label: String) {
        self.label = label
    }
    
    public enum Level: Int, CaseIterable {
        case trace = 0
        case debug = 1
        case info = 2
        case notice = 3
        case warning = 4
        case error = 5
        case critical = 6
    }
    
    public func log(level: Level, _ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] [\(level)] [\(label)] \(message)")
    }
    
    public func info(_ message: String) {
        log(level: .info, message)
    }
    
    public func debug(_ message: String) {
        log(level: .debug, message)
    }
    
    public func warning(_ message: String) {
        log(level: .warning, message)
    }
    
    public func error(_ message: String) {
        log(level: .error, message)
    }
}

/// Core configuration for SwiftAgentKit
public struct SwiftAgentKitConfig {
    public let enableLogging: Bool
    public let logLevel: Logger.Level
    public let enableA2A: Bool
    public let enableMCP: Bool
    public let enableIntercom: Bool
    
    public init(
        enableLogging: Bool = true,
        logLevel: Logger.Level = .info,
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