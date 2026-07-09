import Foundation
import EasyJSON

/// A deferred mutation to shared tool-dispatch context.
///
/// During a parallel stage, tools may enqueue modifiers but must not observe
/// sibling mutations. After the stage completes, the orchestrator applies queued
/// modifiers in **call order** before the next stage.
public struct ToolContextModifier: Sendable, Equatable, Codable {
    public let toolCallID: String
    public let key: String
    public let value: JSON

    public init(toolCallID: String, key: String, value: JSON) {
        self.toolCallID = toolCallID
        self.key = key
        self.value = value
    }

    public static func == (lhs: ToolContextModifier, rhs: ToolContextModifier) -> Bool {
        lhs.toolCallID == rhs.toolCallID
            && lhs.key == rhs.key
            && String(describing: lhs.value) == String(describing: rhs.value)
    }
}

/// Shared key/value store visible to tools during a dispatch stage.
///
/// Reads during a parallel stage see the pre-stage snapshot. Writes from tools
/// should go through ``ToolContextModifierQueue`` so they apply only after the stage.
public final class ToolDispatchSharedContext: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: JSON]

    @TaskLocal public static var current: ToolDispatchSharedContext?

    public init(_ initial: [String: JSON] = [:]) {
        self.storage = initial
    }

    public func value(forKey key: String) -> JSON? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func snapshot() -> [String: JSON] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public func apply(_ modifier: ToolContextModifier) {
        lock.lock()
        defer { lock.unlock() }
        storage[modifier.key] = modifier.value
    }

    public func applyAll(_ modifiers: [ToolContextModifier]) {
        for modifier in modifiers {
            apply(modifier)
        }
    }

    /// Run `body` with this context installed as the task-local current shared context.
    public func withCurrent<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async rethrows -> T {
        try await Self.$current.withValue(self) {
            try await body()
        }
    }
}

/// Stage-scoped collector for deferred ``ToolContextModifier`` values.
///
/// Install via ``withCollector(_:)`` around a dispatch stage. Tools call
/// ``enqueue(_:)``; the orchestrator drains and applies after the stage.
public enum ToolContextModifierQueue: Sendable {
    @TaskLocal public static var current: Collector?

    /// Thread-safe collector installed for the duration of a dispatch stage.
    public final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var modifiers: [ToolContextModifier] = []

        public init() {}

        public func enqueue(_ modifier: ToolContextModifier) {
            lock.lock()
            defer { lock.unlock() }
            modifiers.append(modifier)
        }

        public func drain() -> [ToolContextModifier] {
            lock.lock()
            defer { lock.unlock() }
            let drained = modifiers
            modifiers = []
            return drained
        }
    }

    /// Enqueue a modifier on the current stage collector, if one is installed.
    @discardableResult
    public static func enqueue(_ modifier: ToolContextModifier) -> Bool {
        guard let collector = current else { return false }
        collector.enqueue(modifier)
        return true
    }

    /// Run `body` with a fresh collector installed as the task-local current queue.
    public static func withCollector<T: Sendable>(
        _ body: @Sendable (Collector) async throws -> T
    ) async rethrows -> T {
        let collector = Collector()
        return try await $current.withValue(collector) {
            try await body(collector)
        }
    }

    /// Sort drained modifiers so they apply in the given call-ID order.
    /// Modifiers whose `toolCallID` is not in `callOrder` are appended last,
    /// preserving relative drain order among themselves.
    public static func sortedForCallOrder(
        _ modifiers: [ToolContextModifier],
        callOrder: [String]
    ) -> [ToolContextModifier] {
        var indexByID: [String: Int] = [:]
        indexByID.reserveCapacity(callOrder.count)
        for (index, id) in callOrder.enumerated() {
            indexByID[id] = index
        }
        return modifiers.enumerated().sorted { lhs, rhs in
            let leftOrder = indexByID[lhs.element.toolCallID] ?? Int.max
            let rightOrder = indexByID[rhs.element.toolCallID] ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}
