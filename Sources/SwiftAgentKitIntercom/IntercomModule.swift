import Foundation
import os

/// Intercommunication module for SwiftAgentKit
public struct IntercomModule {
    private let logger: Logger
    
    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(subsystem: "com.swiftagentkit", category: "IntercomModule")
        self.logger.info("Intercom module initialized")
    }
    
    /// Placeholder for intercommunication functionality
    public func broadcast(_ message: String) {
        logger.info("Broadcasting message: \(message)")
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