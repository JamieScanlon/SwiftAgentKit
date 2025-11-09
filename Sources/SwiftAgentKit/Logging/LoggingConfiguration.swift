import Foundation
import Logging

/// Shared logging utilities for SwiftAgentKit targets.
///
/// Call `SwiftAgentKitLogging.bootstrap(logger:level:metadata:)` exactly once during startup to
/// adopt your app's preferred `Logger` implementation and log level. If you do not supply a
/// logger, a no-op handler is used so the library remains silent by default.
///
/// After bootstrapping, request scoped loggers with `SwiftAgentKitLogging.logger(for:metadata:)`
/// whenever you need to emit structured messages from within the SDK or a consumer application.
/// Scopes automatically attach consistent subsystem/component metadata while still allowing you to
/// pass per-call metadata.
///
/// Use `SwiftAgentKitLogging.withScopedOverride(level:metadata:logger:_:)` in tests (or short-lived
/// tasks) when you need to temporarily adjust logging behavior without disturbing the global
/// configuration.
///
/// ```swift
/// import Logging
/// import SwiftAgentKit
///
/// SwiftAgentKitLogging.bootstrap(
///     logger: Logger(label: "com.example.app"),
///     level: .info,
///     metadata: ["deployment": .string("staging")]
/// )
///
/// let logger = SwiftAgentKitLogging.logger(for: .core("bootstrap"))
/// logger.info("Agent subsystem is ready")
/// ```
public enum SwiftAgentKitLogging {
    private struct LoggingState: Sendable {
        var baseLogger: Logger
        var defaultMetadata: Logger.Metadata
        var currentLevel: Logger.Level
        var overrideStack: [ScopedOverride]
    }
    
    private struct ScopedOverride: Sendable {
        let id: UUID
        let previousLevel: Logger.Level
        let previousMetadata: Logger.Metadata
        let previousLogger: Logger
    }
    
    private final class LockProtected<Value: Sendable>: @unchecked Sendable {
        private var value: Value
        private let lock = NSLock()
        init(_ value: Value) {
            self.value = value
        }
        func withValue<R>(_ body: (inout Value) -> R) -> R {
            lock.lock()
            defer { lock.unlock() }
            return body(&value)
        }
        func readValue<R>(_ body: (Value) -> R) -> R {
            lock.lock()
            let snapshot = value
            lock.unlock()
            return body(snapshot)
        }
    }
    
    private static let state = LockProtected(
        LoggingState(
            baseLogger: SwiftAgentKitLogging.makeNullLogger(),
            defaultMetadata: [:],
            currentLevel: .info,
            overrideStack: []
        )
    )
    
    /// Allowed log levels for SwiftAgentKit.
    public enum AgentLogLevel: String, Sendable {
        case debug
        case info
        case warning
        case error
        
        var swiftLogLevel: Logger.Level {
            switch self {
            case .debug:
                return .debug
            case .info:
                return .info
            case .warning:
                return .warning
            case .error:
                return .error
            }
        }
        
        init(swiftLogLevel: Logger.Level) {
            switch swiftLogLevel {
            case .trace, .debug:
                self = .debug
            case .info, .notice:
                self = .info
            case .warning:
                self = .warning
            case .error, .critical:
                self = .error
            }
        }
    }
    
    /// Logical scopes used to tag log messages with consistent metadata.
    ///
    /// Each scope maps to a stable subsystem identifier so logs can be pivoted by feature when
    /// analyzed in a centralized logging system. Provide meaningful component names to tighten the
    /// grouping (for example, `.networking("http-client")`).
    public enum LoggingScope: Hashable, Sendable {
        case core(String)
        case authentication(String)
        case networking(String)
        case a2a(String)
        case mcp(String)
        case adapters(String)
        case orchestrator
        case examples(String)
        case tests(String)
        case custom(subsystem: String, component: String? = nil)
        
        var metadata: Logger.Metadata {
            var metadata: Logger.Metadata = [
                "subsystem": .string(subsystemIdentifier)
            ]
            if let component = componentIdentifier {
                metadata["component"] = .string(component)
            }
            return metadata
        }
        
        private var subsystemIdentifier: String {
            switch self {
            case .core:
                return "swiftagentkit.core"
            case .authentication:
                return "swiftagentkit.authentication"
            case .networking:
                return "swiftagentkit.networking"
            case .a2a:
                return "swiftagentkit.a2a"
            case .mcp:
                return "swiftagentkit.mcp"
            case .adapters:
                return "swiftagentkit.adapters"
            case .orchestrator:
                return "swiftagentkit.orchestrator"
            case .examples:
                return "swiftagentkit.examples"
            case .tests:
                return "swiftagentkit.tests"
            case .custom(let subsystem, _):
                return subsystem
            }
        }
        
        private var componentIdentifier: String? {
            switch self {
            case .core(let component),
                    .authentication(let component),
                    .networking(let component),
                    .a2a(let component),
                    .mcp(let component),
                    .adapters(let component),
                    .examples(let component),
                    .tests(let component):
                return component
            case .orchestrator:
                return "SwiftAgentKitOrchestrator"
            case .custom(_, let component):
                return component
            }
        }
    }
    
    /// Configure the shared logging system with an optional base logger, preferred level, and default metadata.
    ///
    /// Call this early in your application's lifecycle—typically from `main.swift` or during app
    /// initialization—to ensure all subsequent loggers inherit the same configuration.
    /// - Parameters:
    ///   - logger: The root `Logger` to wrap. Pass `nil` to adopt a no-op logger that suppresses output.
    ///   - level: The initial log level for all SwiftAgentKit loggers (default `.info`).
    ///   - metadata: Default metadata merged into every logger produced by this utility.
    public static func bootstrap(
        logger: Logger?,
        level: AgentLogLevel = .info,
        metadata: Logger.Metadata = [:]
    ) {
        state.withValue { state in
            let callSite = Thread.callStackSymbols.dropFirst().first ?? "unknown"
            let targetLogger = logger ?? makeNullLogger()
            targetLogger.debug(
                "SwiftAgentKitLogging bootstrap invoked",
                metadata: [
                    "level": .string(level.rawValue),
                    "metadataKeys": .string(metadata.keys.sorted().joined(separator: ",")),
                    "overrideActive": .string(state.overrideStack.isEmpty ? "false" : "true"),
                    "callSite": .string(callSite)
                ]
            )
            state.baseLogger = logger ?? makeNullLogger()
            state.defaultMetadata = metadata
            state.currentLevel = level.swiftLogLevel
            state.baseLogger.logLevel = state.currentLevel
        }
    }
    
    /// Update the log level for the entire library.
    /// Update the log level for the entire library.
    ///
    /// - Parameter level: The new global `AgentLogLevel` applied to all generated loggers.
    public static func setLevel(_ level: AgentLogLevel) {
        state.withValue { state in
            let callSite = Thread.callStackSymbols.dropFirst().first ?? "unknown"
            let previousLevel = AgentLogLevel(swiftLogLevel: state.currentLevel)
            state.baseLogger.debug(
                "SwiftAgentKitLogging setLevel invoked",
                metadata: [
                    "newLevel": .string(level.rawValue),
                    "previousLevel": .string(previousLevel.rawValue),
                    "overrideActive": .string(state.overrideStack.isEmpty ? "false" : "true"),
                    "callSite": .string(callSite)
                ]
            )
            state.currentLevel = level.swiftLogLevel
            state.baseLogger.logLevel = state.currentLevel
        }
    }
    
    /// Retrieve the currently configured log level.
    /// Retrieve the currently configured log level.
    ///
    /// - Returns: The active `AgentLogLevel`, including overrides if one is in effect.
    public static func level() -> AgentLogLevel {
        state.readValue { state in
            AgentLogLevel(swiftLogLevel: state.currentLevel)
        }
    }
    
    /// Produce a scoped logger for the requested component.
    ///
    /// The returned logger inherits the global level and merges default metadata, scope metadata,
    /// and any additional metadata provided for this call. Later metadata values override earlier
    /// ones when keys collide.
    /// - Parameters:
    ///   - scope: The logical scope that determines base metadata (subsystem/component).
    ///   - additionalMetadata: Extra metadata to merge for this logger invocation. Keys override earlier values.
    /// - Returns: A `Logger` configured with the global state, scope metadata, and provided metadata.
    public static func logger(
        for scope: LoggingScope,
        metadata additionalMetadata: Logger.Metadata = [:]
    ) -> Logger {
        let snapshot = state.readValue { state in state }
        var configured = snapshot.baseLogger
        configured.logLevel = snapshot.currentLevel
        
        let mergedMetadata = mergeMetadata(snapshot.defaultMetadata, scope.metadata, additionalMetadata)
        for (key, value) in mergedMetadata {
            configured[metadataKey: key] = value
        }
        
        return configured
    }
    
    /// Produce a null logger that discards all messages.
    /// Produce a null logger that discards all messages.
    ///
    /// - Returns: A `Logger` whose handler drops all emitted records.
    public static func makeNullLogger() -> Logger {
        Logger(label: "SwiftAgentKit.null") { _ in NullLogHandler() }
    }
    
    internal static func resetForTesting() {
        state.withValue { state in
            state.baseLogger = makeNullLogger()
            state.defaultMetadata = [:]
            state.currentLevel = .info
            state.baseLogger.logLevel = state.currentLevel
            state.overrideStack.removeAll()
        }
    }
    
    /// Temporarily override the global logging configuration for the duration of the closure.
    /// Useful in tests that need to adjust log level or metadata without leaking state.
    ///
    /// Overrides stack, so nested calls restore configurations in LIFO order. Prefer this helper
    /// over mutating `bootstrap` or `setLevel` directly when you only need a short-lived change.
    /// - Parameters:
    ///   - level: Optional temporary override for the log level.
    ///   - metadata: Optional temporary metadata to replace the global defaults.
    ///   - logger: Optional logger to temporarily replace the global base logger.
    ///   - perform: The closure executed while the override is active.
    /// - Returns: The value produced by `perform`.
    @discardableResult
    public static func withScopedOverride<T>(
        level: AgentLogLevel? = nil,
        metadata: Logger.Metadata? = nil,
        logger: Logger? = nil,
        _ perform: () throws -> T
    ) rethrows -> T {
        let override = state.withValue { state -> ScopedOverride in
            let ticket = ScopedOverride(
                id: UUID(),
                previousLevel: state.currentLevel,
                previousMetadata: state.defaultMetadata,
                previousLogger: state.baseLogger
            )
            state.overrideStack.append(ticket)
            
            if let logger {
                state.baseLogger = logger
            }
            if let metadata {
                state.defaultMetadata = metadata
            }
            if let level {
                state.currentLevel = level.swiftLogLevel
                state.baseLogger.logLevel = state.currentLevel
            }
            state.baseLogger.debug(
                "Applying scoped logging override",
                metadata: [
                    "overrideId": .string(ticket.id.uuidString),
                    "level": .string(AgentLogLevel(swiftLogLevel: state.currentLevel).rawValue),
                    "metadataKeys": .string(state.defaultMetadata.keys.sorted().joined(separator: ","))
                ]
            )
            return ticket
        }
        
        defer {
            state.withValue { state in
                guard let last = state.overrideStack.last, last.id == override.id else {
                    state.baseLogger.warning(
                        "Attempted to pop logging override out of order",
                        metadata: ["overrideId": .string(override.id.uuidString)]
                    )
                    return
                }
                state.overrideStack.removeLast()
                state.baseLogger = override.previousLogger
                state.defaultMetadata = override.previousMetadata
                state.currentLevel = override.previousLevel
                state.baseLogger.logLevel = state.currentLevel
                state.baseLogger.debug(
                    "Restored logging state after scoped override",
                    metadata: ["overrideId": .string(override.id.uuidString)]
                )
            }
        }
        
        return try perform()
    }
    
    private static func mergeMetadata(_ parts: Logger.Metadata...) -> Logger.Metadata {
        parts.reduce(into: Logger.Metadata()) { result, metadata in
            for (key, value) in metadata {
                result[key] = value
            }
        }
    }
    
    /// Convenience helper to build metadata dictionaries.
    public static func metadata(_ pairs: (String, Logger.MetadataValue)...) -> Logger.Metadata {
        Dictionary(uniqueKeysWithValues: pairs)
    }
}

struct NullLogHandler: LogHandler {
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .critical
    
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }
    
    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        // Intentionally swallow all messages.
    }
}

