import Foundation
import SwiftAgentKit
import Logging

/// Example demonstrating SwiftAgentKit logging filter capabilities
func loggingFilterExample() {
    print("=== SwiftAgentKit Logging Filter Example ===\n")
    
    // Setup logging with a capturing handler to see filtered results
    let recorder = LogRecorder()
    let capturingLogger = Logger(label: "com.example.swiftagentkit.filtering") { _ in
        CapturingLogHandler(recorder: recorder)
    }
    
    // Example 1: Filter by minimum log level
    print("1. Filtering by minimum log level (.warning):")
    let levelFilter = SwiftAgentKitLogging.LogFilter(
        level: .minimum(.warning)
    )
    SwiftAgentKitLogging.bootstrap(
        logger: capturingLogger,
        level: .debug,
        filter: levelFilter
    )
    
    let logger1 = SwiftAgentKitLogging.logger(for: .core("LevelFilter"))
    logger1.debug("This debug message will be filtered")
    logger1.info("This info message will be filtered")
    logger1.warning("This warning message will pass")
    logger1.error("This error message will pass")
    
    let levelLogs = recorder.drain()
    print("   Captured \(levelLogs.count) log entries:")
    for log in levelLogs {
        print("   - [\(log.level)] \(log.message)")
    }
    print()
    
    // Example 2: Filter by scope (subsystem/component)
    print("2. Filtering by scope (only authentication subsystem):")
    let scopeFilter = SwiftAgentKitLogging.LogFilter(
        allowedScopes: [.authentication("OAuth"), .authentication("PKCE")]
    )
    SwiftAgentKitLogging.setFilter(scopeFilter)
    
    let authLogger = SwiftAgentKitLogging.logger(for: .authentication("OAuth"))
    let coreLogger = SwiftAgentKitLogging.logger(for: .core("Message"))
    let mcpLogger = SwiftAgentKitLogging.logger(for: .mcp("Client"))
    
    authLogger.info("Authentication log - will pass")
    coreLogger.info("Core log - will be filtered")
    mcpLogger.info("MCP log - will be filtered")
    
    let scopeLogs = recorder.drain()
    print("   Captured \(scopeLogs.count) log entries:")
    for log in scopeLogs {
        print("   - [\(log.level)] \(log.message)")
    }
    print()
    
    // Example 3: Filter by required metadata keys
    print("3. Filtering by required metadata keys (requestId and userId):")
    let metadataFilter = SwiftAgentKitLogging.LogFilter(
        requiredMetadataKeys: ["requestId", "userId"]
    )
    SwiftAgentKitLogging.setFilter(metadataFilter)
    
    let logger3 = SwiftAgentKitLogging.logger(for: .core("MetadataFilter"))
    logger3.info("Message without required keys - will be filtered")
    logger3.info("Message with requestId", metadata: ["requestId": .string("123")])
    logger3.info("Message with both keys", metadata: [
        "requestId": .string("123"),
        "userId": .string("456")
    ])
    
    let metadataLogs = recorder.drain()
    print("   Captured \(metadataLogs.count) log entry:")
    for log in metadataLogs {
        print("   - [\(log.level)] \(log.message)")
        print("     Metadata: requestId=\(log.metadata["requestId"] ?? "nil"), userId=\(log.metadata["userId"] ?? "nil")")
    }
    print()
    
    // Example 4: Filter by keywords
    print("4. Filtering by keywords (must contain 'error' or 'failed'):")
    let keywordFilter = SwiftAgentKitLogging.LogFilter(
        keywords: ["error"]
    )
    SwiftAgentKitLogging.setFilter(keywordFilter)
    
    let logger4 = SwiftAgentKitLogging.logger(for: .core("KeywordFilter"))
    logger4.info("Success message - will be filtered")
    logger4.info("An error occurred - will pass")
    logger4.info("Operation status", metadata: ["status": .string("error occurred")])
    
    let keywordLogs = recorder.drain()
    print("   Captured \(keywordLogs.count) log entries:")
    for log in keywordLogs {
        print("   - [\(log.level)] \(log.message)")
    }
    print()
    
    // Example 5: Combined filters (AND logic)
    print("5. Combined filters (level + scope + keyword):")
    let combinedFilter = SwiftAgentKitLogging.LogFilter(
        level: .minimum(.info),
        allowedScopes: [.authentication("OAuth")],
        keywords: ["token"]
    )
    SwiftAgentKitLogging.setFilter(combinedFilter)
    
    let authLogger5 = SwiftAgentKitLogging.logger(for: .authentication("OAuth"))
    let coreLogger5 = SwiftAgentKitLogging.logger(for: .core("Test"))
    
    // Wrong level - filtered
    authLogger5.debug("token debug message")
    // Wrong scope - filtered
    coreLogger5.info("token message")
    // Missing keyword - filtered
    authLogger5.info("other message")
    // All criteria met - passes
    authLogger5.info("token message")
    
    let combinedLogs = recorder.drain()
    print("   Captured \(combinedLogs.count) log entry:")
    for log in combinedLogs {
        print("   - [\(log.level)] \(log.message)")
    }
    print()
    
    // Example 6: Dynamic filter updates
    print("6. Dynamic filter updates:")
    SwiftAgentKitLogging.setFilter(nil)  // Clear any existing filter
    
    let logger6 = SwiftAgentKitLogging.logger(for: .core("DynamicFilter"))
    logger6.info("Message before filter")
    _ = recorder.drain()
    
    // Apply filter dynamically
    let dynamicFilter = SwiftAgentKitLogging.LogFilter(keywords: ["important"])
    SwiftAgentKitLogging.setFilter(dynamicFilter)
    
    // Create new logger after filter is set
    let logger6Filtered = SwiftAgentKitLogging.logger(for: .core("DynamicFilter"))
    logger6Filtered.info("Regular message - will be filtered")
    logger6Filtered.info("Important message - will pass")
    
    let dynamicLogs = recorder.drain()
    print("   Captured \(dynamicLogs.count) log entry:")
    for log in dynamicLogs {
        print("   - [\(log.level)] \(log.message)")
    }
    
    // Clear filter
    SwiftAgentKitLogging.setFilter(nil)
    let logger6Cleared = SwiftAgentKitLogging.logger(for: .core("DynamicFilter"))
    logger6Cleared.info("Message after filter cleared")
    let clearedLogs = recorder.drain()
    print("   After clearing filter, captured \(clearedLogs.count) log entry")
    print()
    
    print("✅ Logging filter examples completed!")
    print("\nKey takeaways:")
    print("- Filters apply globally to all loggers")
    print("- Multiple filter criteria use AND logic (all must match)")
    print("- Filters can be set at bootstrap or updated dynamically")
    print("- New loggers created after filter changes will respect the new filter")
}

// MARK: - Helper Types

private struct LogRecord: Sendable {
    let level: Logger.Level
    let message: String
    let metadata: Logger.Metadata
}

private final class LogRecorder {
    private let lock = NSLock()
    private var records: [LogRecord] = []
    
    func append(_ record: LogRecord) {
        lock.withLock {
            records.append(record)
        }
    }
    
    func drain() -> [LogRecord] {
        lock.withLock {
            let snapshot = records
            records.removeAll()
            return snapshot
        }
    }
}

extension LogRecorder: @unchecked Sendable {}

private struct CapturingLogHandler: LogHandler {
    private let recorder: LogRecorder
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .debug
    
    init(recorder: LogRecorder) {
        self.recorder = recorder
    }
    
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }
    
    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata additionalMetadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        var combined = metadata
        if let additionalMetadata {
            for (key, value) in additionalMetadata {
                combined[key] = value
            }
        }
        recorder.append(LogRecord(level: level, message: message.description, metadata: combined))
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

