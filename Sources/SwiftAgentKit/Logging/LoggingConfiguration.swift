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
        var baseHandlerFactory: @Sendable (String) -> LogHandler
        var defaultMetadata: Logger.Metadata
        var currentLevel: Logger.Level
        var overrideStack: [ScopedOverride]
        var activeFilter: LogFilter?
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
            baseHandlerFactory: { _ in NullLogHandler() },
            defaultMetadata: [:],
            currentLevel: .info,
            overrideStack: [],
            activeFilter: nil
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
    
    /// Filter configuration for controlling which log entries are emitted.
    ///
    /// All specified filter criteria must match for a log entry to pass through (AND logic).
    /// If a filter criterion is `nil`, it is not applied.
    public struct LogFilter: Sendable {
        /// Minimum log level to allow, or specific set of allowed levels.
        /// If `nil`, level filtering is not applied.
        public let level: LevelFilter?
        
        /// Set of allowed scopes. Log entries must match at least one scope.
        /// If `nil`, scope filtering is not applied.
        public let allowedScopes: Set<LoggingScope>?
        
        /// Set of metadata keys that must be present in the log entry.
        /// If `nil`, metadata key filtering is not applied.
        public let requiredMetadataKeys: Set<String>?
        
        /// Set of keywords that must appear in the message text or metadata values.
        /// Keywords are matched case-insensitively.
        /// If `nil`, keyword filtering is not applied.
        public let keywords: Set<String>?
        
        /// Level filtering options.
        public enum LevelFilter: Sendable {
            /// Minimum level - allows this level and all higher severity levels.
            case minimum(AgentLogLevel)
            /// Specific set of allowed levels.
            case allowed(Set<AgentLogLevel>)
        }
        
        public init(
            level: LevelFilter? = nil,
            allowedScopes: Set<LoggingScope>? = nil,
            requiredMetadataKeys: Set<String>? = nil,
            keywords: Set<String>? = nil
        ) {
            self.level = level
            self.allowedScopes = allowedScopes
            self.requiredMetadataKeys = requiredMetadataKeys
            self.keywords = keywords
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
    ///   - filter: Optional filter configuration to apply to all log entries.
    public static func bootstrap(
        logger: Logger?,
        level: AgentLogLevel = .info,
        metadata: Logger.Metadata = [:],
        filter: LogFilter? = nil
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
            state.baseLogger = targetLogger
            // Store a factory that creates handlers wrapping the base logger
            let loggerToWrap = targetLogger
            state.baseHandlerFactory = { _ in
                BaseLoggerHandler(baseLogger: loggerToWrap)
            }
            state.defaultMetadata = metadata
            state.currentLevel = level.swiftLogLevel
            state.baseLogger.logLevel = state.currentLevel
            state.activeFilter = filter
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
        
        let mergedMetadata = mergeMetadata(snapshot.defaultMetadata, scope.metadata, additionalMetadata)
        
        // If a filter is active, create a logger with FilteringLogHandler
        if let filter = snapshot.activeFilter {
            return Logger(label: snapshot.baseLogger.label) { _ in
                let baseHandler = snapshot.baseHandlerFactory(snapshot.baseLogger.label)
                var filteringHandler = FilteringLogHandler(
                    wrapped: baseHandler,
                    filter: filter,
                    scope: scope
                )
                filteringHandler.logLevel = snapshot.currentLevel
                // Apply merged metadata to the filtering handler
                for (key, value) in mergedMetadata {
                    filteringHandler[metadataKey: key] = value
                }
                return filteringHandler
            }
        }
        
        // No filter: create logger normally
        var configured = snapshot.baseLogger
        configured.logLevel = snapshot.currentLevel
        for (key, value) in mergedMetadata {
            configured[metadataKey: key] = value
        }
        return configured
    }
    
    /// Set or clear the active log filter.
    ///
    /// - Parameter filter: The filter configuration to apply, or `nil` to clear filtering.
    public static func setFilter(_ filter: LogFilter?) {
        state.withValue { state in
            state.activeFilter = filter
        }
    }
    
    /// Retrieve the currently configured log filter.
    ///
    /// - Returns: The active `LogFilter`, or `nil` if no filter is configured.
    public static func filter() -> LogFilter? {
        state.readValue { state in
            state.activeFilter
        }
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
            state.baseHandlerFactory = { _ in NullLogHandler() }
            state.defaultMetadata = [:]
            state.currentLevel = .info
            state.baseLogger.logLevel = state.currentLevel
            state.overrideStack.removeAll()
            state.activeFilter = nil
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

/// Handler that forwards log calls to a base Logger.
/// This is used to wrap a Logger when we need to apply filtering.
struct BaseLoggerHandler: LogHandler {
    private let baseLogger: Logger
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level
    
    init(baseLogger: Logger) {
        self.baseLogger = baseLogger
        self.logLevel = baseLogger.logLevel
        // Note: We can't directly access Logger's metadata, so we start empty
        // The metadata will be set via subscript when the logger is configured
        self.metadata = [:]
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
        // Forward to base logger by setting metadata and calling log
        var tempLogger = baseLogger
        tempLogger.logLevel = self.logLevel
        // Apply our metadata
        for (key, value) in self.metadata {
            tempLogger[metadataKey: key] = value
        }
        // Apply additional metadata
        if let additionalMetadata {
            for (key, value) in additionalMetadata {
                tempLogger[metadataKey: key] = value
            }
        }
        // Call the appropriate log method based on level
        switch level {
        case .trace:
            tempLogger.trace(message, metadata: nil, source: source, file: file, function: function, line: line)
        case .debug:
            tempLogger.debug(message, metadata: nil, source: source, file: file, function: function, line: line)
        case .info:
            tempLogger.info(message, metadata: nil, source: source, file: file, function: function, line: line)
        case .notice:
            tempLogger.notice(message, metadata: nil, source: source, file: file, function: function, line: line)
        case .warning:
            tempLogger.warning(message, metadata: nil, source: source, file: file, function: function, line: line)
        case .error:
            tempLogger.error(message, metadata: nil, source: source, file: file, function: function, line: line)
        case .critical:
            tempLogger.critical(message, metadata: nil, source: source, file: file, function: function, line: line)
        }
    }
}

/// Log handler that applies filtering criteria before forwarding log entries.
struct FilteringLogHandler: LogHandler {
    private let wrapped: LogHandler
    private let filter: SwiftAgentKitLogging.LogFilter
    private let scope: SwiftAgentKitLogging.LoggingScope
    private var _metadata: Logger.Metadata = [:]
    private var _logLevel: Logger.Level
    
    var metadata: Logger.Metadata {
        get { _metadata }
        set { _metadata = newValue }
    }
    
    var logLevel: Logger.Level {
        get { _logLevel }
        set { _logLevel = newValue }
    }
    
    init(wrapped: LogHandler, filter: SwiftAgentKitLogging.LogFilter, scope: SwiftAgentKitLogging.LoggingScope) {
        self.wrapped = wrapped
        self.filter = filter
        self.scope = scope
        self._metadata = wrapped.metadata
        self._logLevel = wrapped.logLevel
    }
    
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { _metadata[key] }
        set { _metadata[key] = newValue }
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
        // Combine handler metadata with additional metadata
        var combinedMetadata = metadata
        if let additionalMetadata {
            for (key, value) in additionalMetadata {
                combinedMetadata[key] = value
            }
        }
        
        // Apply filters with AND logic - all must pass
        guard shouldAllowLog(
            level: level,
            message: message.description,
            metadata: combinedMetadata
        ) else {
            return
        }
        
        // Forward to wrapped handler
        wrapped.log(
            level: level,
            message: message,
            metadata: additionalMetadata,
            source: source,
            file: file,
            function: function,
            line: line
        )
    }
    
    private func shouldAllowLog(
        level: Logger.Level,
        message: String,
        metadata: Logger.Metadata
    ) -> Bool {
        // Level filter
        if let levelFilter = filter.level {
            let agentLevel = SwiftAgentKitLogging.AgentLogLevel(swiftLogLevel: level)
            switch levelFilter {
            case .minimum(let minLevel):
                let levelOrder: [SwiftAgentKitLogging.AgentLogLevel] = [.debug, .info, .warning, .error]
                guard let minIndex = levelOrder.firstIndex(of: minLevel),
                      let currentIndex = levelOrder.firstIndex(of: agentLevel),
                      currentIndex >= minIndex else {
                    return false
                }
            case .allowed(let allowedLevels):
                guard allowedLevels.contains(agentLevel) else {
                    return false
                }
            }
        }
        
        // Scope filter
        if let allowedScopes = filter.allowedScopes {
            guard allowedScopes.contains(scope) else {
                return false
            }
        }
        
        // Metadata key filter
        if let requiredKeys = filter.requiredMetadataKeys {
            for key in requiredKeys {
                guard metadata[key] != nil else {
                    return false
                }
            }
        }
        
        // Keyword filter
        if let keywords = filter.keywords {
            let lowercasedMessage = message.lowercased()
            var foundKeywords = Set<String>()
            
            // Check message text
            for keyword in keywords {
                if lowercasedMessage.contains(keyword.lowercased()) {
                    foundKeywords.insert(keyword.lowercased())
                }
            }
            
            // Check metadata values recursively
            let metadataStrings = extractStrings(from: metadata)
            for keyword in keywords {
                let lowercasedKeyword = keyword.lowercased()
                for metadataString in metadataStrings {
                    if metadataString.lowercased().contains(lowercasedKeyword) {
                        foundKeywords.insert(lowercasedKeyword)
                        break
                    }
                }
            }
            
            // All keywords must be found
            guard foundKeywords.count == keywords.count else {
                return false
            }
        }
        
        return true
    }
    
    /// Recursively extract all string values from metadata.
    private func extractStrings(from metadata: Logger.Metadata) -> [String] {
        var strings: [String] = []
        for (_, value) in metadata {
            switch value {
            case .string(let str):
                strings.append(str)
            case .stringConvertible(let convertible):
                strings.append(String(describing: convertible))
            case .dictionary(let dict):
                strings.append(contentsOf: extractStrings(from: dict))
            case .array(let arr):
                for item in arr {
                    switch item {
                    case .string(let str):
                        strings.append(str)
                    case .stringConvertible(let convertible):
                        strings.append(String(describing: convertible))
                    case .dictionary(let dict):
                        strings.append(contentsOf: extractStrings(from: dict))
                    case .array:
                        // Nested arrays not supported by swift-log, but handle gracefully
                        break
                    }
                }
            }
        }
        return strings
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

