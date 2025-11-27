import Foundation
import Logging
import Testing
@testable import SwiftAgentKit

@Suite("SwiftAgentKitLoggingTests", .serialized)
struct SwiftAgentKitLoggingTests {
    @Test
    func injectedLoggerReceivesMetadata() {
        SwiftAgentKitLogging.resetForTesting()
        
        let recorder = LogRecorder()
        let capturingLogger = Logger(label: "TestCapture") { _ in
            CapturingLogHandler(recorder: recorder)
        }
        
        SwiftAgentKitLogging.bootstrap(
            logger: capturingLogger,
            level: .debug,
            metadata: ["environment": .string("unit")]
        )
        _ = recorder.drain()
        
        let logger = SwiftAgentKitLogging.logger(
            for: .authentication("OAuthAuthProvider"),
            metadata: ["requestId": .string("123")]
        )
        logger.debug("payload")
        
        let payloadLogs = recorder.drain().filter { $0.message.contains("payload") }
        #expect(payloadLogs.count == 1)
        let payloadLog = payloadLogs[0]
        #expect(payloadLog.level == .debug)
        #expect(payloadLog.metadata["subsystem"] == .string("swiftagentkit.authentication"))
        #expect(payloadLog.metadata["component"] == .string("OAuthAuthProvider"))
        #expect(payloadLog.metadata["environment"] == .string("unit"))
        #expect(payloadLog.metadata["requestId"] == .string("123"))
    }
    
    @Test
    func levelUpdatesPropagateToLoggers() {
        SwiftAgentKitLogging.resetForTesting()
        
        let recorder = LogRecorder()
        let capturingLogger = Logger(label: "LevelCapture") { _ in
            CapturingLogHandler(recorder: recorder)
        }
        
        SwiftAgentKitLogging.bootstrap(logger: capturingLogger, level: .info)
        _ = recorder.drain()
        
        let infoLogger = SwiftAgentKitLogging.logger(for: .core("Message"))
        infoLogger.debug("hidden")
        #expect(recorder.drain().isEmpty)
        
        SwiftAgentKitLogging.setLevel(.debug)
        _ = recorder.drain()
        let debugLogger = SwiftAgentKitLogging.logger(for: .core("Message"))
        debugLogger.debug("visible")
        
        let logs = recorder.drain()
        let messageLogs = logs.filter { $0.metadata["component"] == .string("Message") && $0.message.contains("visible") }
        #expect(messageLogs.count == 1)
        #expect(messageLogs.first?.level == .debug)
        #expect(messageLogs.first?.metadata["component"] == .string("Message"))
    }
    
    @Test
    func levelAccessorReflectsConfiguration() {
        SwiftAgentKitLogging.resetForTesting()
        SwiftAgentKitLogging.bootstrap(logger: nil, level: .warning)
        #expect(SwiftAgentKitLogging.level() == .warning)
        
        SwiftAgentKitLogging.setLevel(.error)
        #expect(SwiftAgentKitLogging.level() == .error)
    }
    
    @Test
    func levelFilterMinimum() {
        SwiftAgentKitLogging.resetForTesting()
        
        let recorder = LogRecorder()
        let capturingLogger = Logger(label: "LevelFilter") { _ in
            CapturingLogHandler(recorder: recorder)
        }
        
        let filter = SwiftAgentKitLogging.LogFilter(
            level: .minimum(.warning)
        )
        SwiftAgentKitLogging.bootstrap(logger: capturingLogger, level: .debug, filter: filter)
        _ = recorder.drain()
        
        let logger = SwiftAgentKitLogging.logger(for: .core("Test"))
        logger.debug("debug message")
        logger.info("info message")
        logger.warning("warning message")
        logger.error("error message")
        
        let logs = recorder.drain()
        #expect(logs.count == 2)
        #expect(logs.contains { $0.message.contains("warning") })
        #expect(logs.contains { $0.message.contains("error") })
        #expect(!logs.contains { $0.message.contains("debug") })
        #expect(!logs.contains { $0.message.contains("info") })
    }
    
    @Test
    func levelFilterAllowed() {
        SwiftAgentKitLogging.resetForTesting()
        
        let recorder = LogRecorder()
        let capturingLogger = Logger(label: "LevelFilterAllowed") { _ in
            CapturingLogHandler(recorder: recorder)
        }
        
        let filter = SwiftAgentKitLogging.LogFilter(
            level: .allowed([.info, .error])
        )
        SwiftAgentKitLogging.bootstrap(logger: capturingLogger, level: .debug, filter: filter)
        _ = recorder.drain()
        
        let logger = SwiftAgentKitLogging.logger(for: .core("Test"))
        logger.debug("debug message")
        logger.info("info message")
        logger.warning("warning message")
        logger.error("error message")
        
        let logs = recorder.drain()
        #expect(logs.count == 2)
        #expect(logs.contains { $0.message.contains("info") })
        #expect(logs.contains { $0.message.contains("error") })
        #expect(!logs.contains { $0.message.contains("debug") })
        #expect(!logs.contains { $0.message.contains("warning") })
    }
    
    @Test
    func scopeFilter() {
        SwiftAgentKitLogging.resetForTesting()
        
        let recorder = LogRecorder()
        let capturingLogger = Logger(label: "ScopeFilter") { _ in
            CapturingLogHandler(recorder: recorder)
        }
        
        let filter = SwiftAgentKitLogging.LogFilter(
            allowedScopes: [.authentication("OAuth"), .mcp("Client")]
        )
        SwiftAgentKitLogging.bootstrap(logger: capturingLogger, level: .debug, filter: filter)
        _ = recorder.drain()
        
        let authLogger = SwiftAgentKitLogging.logger(for: .authentication("OAuth"))
        let mcpLogger = SwiftAgentKitLogging.logger(for: .mcp("Client"))
        let coreLogger = SwiftAgentKitLogging.logger(for: .core("Test"))
        
        authLogger.info("auth message")
        mcpLogger.info("mcp message")
        coreLogger.info("core message")
        
        let logs = recorder.drain()
        #expect(logs.count == 2)
        #expect(logs.contains { $0.message.contains("auth") })
        #expect(logs.contains { $0.message.contains("mcp") })
        #expect(!logs.contains { $0.message.contains("core") })
    }
    
    @Test
    func metadataKeyFilter() {
        SwiftAgentKitLogging.resetForTesting()
        
        let recorder = LogRecorder()
        let capturingLogger = Logger(label: "MetadataKeyFilter") { _ in
            CapturingLogHandler(recorder: recorder)
        }
        
        let filter = SwiftAgentKitLogging.LogFilter(
            requiredMetadataKeys: ["requestId", "userId"]
        )
        SwiftAgentKitLogging.bootstrap(logger: capturingLogger, level: .debug, filter: filter)
        _ = recorder.drain()
        
        let logger = SwiftAgentKitLogging.logger(for: .core("Test"))
        
        // Missing required keys - should be filtered
        logger.info("message without keys")
        
        // Has requestId but missing userId - should be filtered
        logger.info("message with requestId", metadata: ["requestId": .string("123")])
        
        // Has both keys - should pass
        logger.info("message with both keys", metadata: [
            "requestId": .string("123"),
            "userId": .string("456")
        ])
        
        let logs = recorder.drain()
        #expect(logs.count == 1)
        #expect(logs.first?.message.contains("both keys") == true)
    }
    
    @Test
    func keywordFilter() {
        SwiftAgentKitLogging.resetForTesting()
        
        let recorder = LogRecorder()
        let capturingLogger = Logger(label: "KeywordFilter") { _ in
            CapturingLogHandler(recorder: recorder)
        }
        
        let filter = SwiftAgentKitLogging.LogFilter(
            keywords: ["error"]
        )
        SwiftAgentKitLogging.bootstrap(logger: capturingLogger, level: .debug, filter: filter)
        _ = recorder.drain()
        
        let logger = SwiftAgentKitLogging.logger(for: .core("Test"))
        
        // Message contains "error" - should pass
        logger.info("An error occurred")
        
        // Metadata contains "error" - should pass
        logger.info("Operation status", metadata: ["status": .string("error occurred")])
        
        // Keyword not present - should be filtered
        logger.info("Success message")
        
        let logs = recorder.drain()
        #expect(logs.count == 2)
        #expect(logs.contains { $0.message.contains("error") })
        #expect(logs.contains { $0.message.contains("status") })
        #expect(!logs.contains { $0.message.contains("Success") })
    }
    
    @Test
    func keywordFilterMultiple() {
        SwiftAgentKitLogging.resetForTesting()
        
        let recorder = LogRecorder()
        let capturingLogger = Logger(label: "KeywordFilterMultiple") { _ in
            CapturingLogHandler(recorder: recorder)
        }
        
        // All keywords must be present (AND logic)
        let filter = SwiftAgentKitLogging.LogFilter(
            keywords: ["error", "failed"]
        )
        SwiftAgentKitLogging.bootstrap(logger: capturingLogger, level: .debug, filter: filter)
        _ = recorder.drain()
        
        let logger = SwiftAgentKitLogging.logger(for: .core("Test"))
        
        // Only "error" - filtered (missing "failed")
        logger.info("An error occurred")
        
        // Only "failed" - filtered (missing "error")
        logger.info("Operation failed", metadata: ["status": .string("failed")])
        
        // Both keywords in message - passes
        logger.info("An error occurred and the operation failed")
        
        // Both keywords split between message and metadata - passes
        logger.info("An error occurred", metadata: ["result": .string("failed")])
        
        // Neither keyword - filtered
        logger.info("Success message")
        
        let logs = recorder.drain()
        #expect(logs.count == 2)
        #expect(logs.allSatisfy { log in
            log.message.lowercased().contains("error") || 
            (log.metadata.values.contains { value in
                if case .string(let str) = value {
                    return str.lowercased().contains("error")
                }
                return false
            })
        })
    }
    
    @Test
    func keywordFilterCaseInsensitive() {
        SwiftAgentKitLogging.resetForTesting()
        
        let recorder = LogRecorder()
        let capturingLogger = Logger(label: "KeywordFilterCase") { _ in
            CapturingLogHandler(recorder: recorder)
        }
        
        let filter = SwiftAgentKitLogging.LogFilter(
            keywords: ["ERROR"]
        )
        SwiftAgentKitLogging.bootstrap(logger: capturingLogger, level: .debug, filter: filter)
        _ = recorder.drain()
        
        let logger = SwiftAgentKitLogging.logger(for: .core("Test"))
        
        // Lowercase "error" should match uppercase "ERROR"
        logger.info("An error occurred")
        
        // Uppercase "ERROR" should match
        logger.info("An ERROR occurred")
        
        // No match - should be filtered
        logger.info("Success message")
        
        let logs = recorder.drain()
        #expect(logs.count == 2)
        #expect(!logs.contains { $0.message.contains("Success") })
    }
    
    @Test
    func combinedFilters() {
        SwiftAgentKitLogging.resetForTesting()
        
        let recorder = LogRecorder()
        let capturingLogger = Logger(label: "CombinedFilters") { _ in
            CapturingLogHandler(recorder: recorder)
        }
        
        let filter = SwiftAgentKitLogging.LogFilter(
            level: .minimum(.info),
            allowedScopes: [.authentication("OAuth")],
            requiredMetadataKeys: ["requestId"],
            keywords: ["token"]
        )
        SwiftAgentKitLogging.bootstrap(logger: capturingLogger, level: .debug, filter: filter)
        _ = recorder.drain()
        
        let authLogger = SwiftAgentKitLogging.logger(for: .authentication("OAuth"))
        let coreLogger = SwiftAgentKitLogging.logger(for: .core("Test"))
        
        // Wrong scope - filtered
        coreLogger.info("token message", metadata: ["requestId": .string("123")])
        
        // Wrong level - filtered
        authLogger.debug("token debug", metadata: ["requestId": .string("123")])
        
        // Missing metadata key - filtered
        authLogger.info("token message")
        
        // Missing keyword - filtered
        authLogger.info("other message", metadata: ["requestId": .string("123")])
        
        // All criteria met - passes
        authLogger.info("token message", metadata: ["requestId": .string("123")])
        
        let logs = recorder.drain()
        #expect(logs.count == 1)
        #expect(logs.first?.message.contains("token") == true)
        #expect(logs.first?.metadata["requestId"] == .string("123"))
    }
    
    @Test
    func filterDynamicUpdate() {
        SwiftAgentKitLogging.resetForTesting()
        
        let recorder = LogRecorder()
        let capturingLogger = Logger(label: "FilterDynamic") { _ in
            CapturingLogHandler(recorder: recorder)
        }
        
        SwiftAgentKitLogging.bootstrap(logger: capturingLogger, level: .debug)
        _ = recorder.drain()
        
        // Create logger before filter - all messages should pass
        let loggerBeforeFilter = SwiftAgentKitLogging.logger(for: .core("Test"))
        loggerBeforeFilter.info("message 1")
        #expect(recorder.drain().count == 1)
        
        // Apply filter
        let filter = SwiftAgentKitLogging.LogFilter(keywords: ["important"])
        SwiftAgentKitLogging.setFilter(filter)
        _ = recorder.drain()
        
        // Logger created before filter still doesn't have filter (expected behavior)
        loggerBeforeFilter.info("message 2")
        loggerBeforeFilter.info("important message")
        let logsBefore = recorder.drain()
        #expect(logsBefore.count == 2) // Both pass because logger was created before filter
        
        // Create new logger after filter is set - should respect filter
        let loggerAfterFilter = SwiftAgentKitLogging.logger(for: .core("Test"))
        loggerAfterFilter.info("message 3")
        loggerAfterFilter.info("important message")
        let logsAfter = recorder.drain()
        #expect(logsAfter.count == 1) // Only "important message" passes
        #expect(logsAfter.first?.message.contains("important") == true)
        
        // Clear filter
        SwiftAgentKitLogging.setFilter(nil)
        _ = recorder.drain()
        
        // New logger created after filter cleared - all messages should pass
        let loggerAfterClear = SwiftAgentKitLogging.logger(for: .core("Test"))
        loggerAfterClear.info("message 4")
        #expect(recorder.drain().count == 1)
    }
    
    @Test
    func filterAccessor() {
        SwiftAgentKitLogging.resetForTesting()
        
        #expect(SwiftAgentKitLogging.filter() == nil)
        
        let filter = SwiftAgentKitLogging.LogFilter(keywords: ["test"])
        SwiftAgentKitLogging.setFilter(filter)
        
        let retrievedFilter = SwiftAgentKitLogging.filter()
        #expect(retrievedFilter != nil)
        #expect(retrievedFilter?.keywords?.contains("test") == true)
        
        SwiftAgentKitLogging.setFilter(nil)
        #expect(SwiftAgentKitLogging.filter() == nil)
    }
    
    @Test
    func filterAtBootstrap() {
        SwiftAgentKitLogging.resetForTesting()
        
        let recorder = LogRecorder()
        let capturingLogger = Logger(label: "FilterBootstrap") { _ in
            CapturingLogHandler(recorder: recorder)
        }
        
        let filter = SwiftAgentKitLogging.LogFilter(
            level: .minimum(.warning)
        )
        SwiftAgentKitLogging.bootstrap(logger: capturingLogger, level: .debug, filter: filter)
        _ = recorder.drain()
        
        let logger = SwiftAgentKitLogging.logger(for: .core("Test"))
        logger.debug("debug")
        logger.info("info")
        logger.warning("warning")
        
        let logs = recorder.drain()
        #expect(logs.count == 1)
        #expect(logs.first?.message.contains("warning") == true)
    }
}

// MARK: - Helpers

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

