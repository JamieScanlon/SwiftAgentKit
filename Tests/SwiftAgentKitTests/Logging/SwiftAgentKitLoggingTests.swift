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
        
        let logger = SwiftAgentKitLogging.logger(
            for: .authentication("OAuthAuthProvider"),
            metadata: ["requestId": .string("123")]
        )
        logger.debug("payload")
        
        let records = recorder.drain()
        #expect(records.count == 1)
        #expect(records.first?.level == .debug)
        #expect(records.first?.metadata["subsystem"] == .string("swiftagentkit.authentication"))
        #expect(records.first?.metadata["component"] == .string("OAuthAuthProvider"))
        #expect(records.first?.metadata["environment"] == .string("unit"))
        #expect(records.first?.metadata["requestId"] == .string("123"))
        #expect(records.first?.message.contains("payload") == true)
    }
    
    @Test
    func levelUpdatesPropagateToLoggers() {
        SwiftAgentKitLogging.resetForTesting()
        
        let recorder = LogRecorder()
        let capturingLogger = Logger(label: "LevelCapture") { _ in
            CapturingLogHandler(recorder: recorder)
        }
        
        SwiftAgentKitLogging.bootstrap(logger: capturingLogger, level: .info)
        
        let infoLogger = SwiftAgentKitLogging.logger(for: .core("Message"))
        infoLogger.debug("hidden")
        #expect(recorder.drain().isEmpty)
        
        SwiftAgentKitLogging.setLevel(.debug)
        let debugLogger = SwiftAgentKitLogging.logger(for: .core("Message"))
        debugLogger.debug("visible")
        
        let logs = recorder.drain()
        let messageLogs = logs.filter { $0.metadata["component"] == .string("Message") }
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

