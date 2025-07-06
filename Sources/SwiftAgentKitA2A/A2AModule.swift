import Foundation

/// A2A (Agent-to-Agent) module for SwiftAgentKit
public struct A2AModule {
    private let logger: Logger
    
    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "A2AModule")
        self.logger.info("A2A module initialized")
    }
    
    /// Placeholder for A2A functionality
    public func connect() {
        logger.info("A2A connection placeholder")
    }
}

/// Simple logger implementation for A2A module
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

/// A2A specific error types
public enum A2AError: Error {
    case serverNotInitialized
    case clientNotInitialized
    case connectionFailed
    case invalidMessage
} 