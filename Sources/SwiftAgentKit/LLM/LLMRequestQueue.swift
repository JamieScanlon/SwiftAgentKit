import Foundation

/// Priority level for LLM queue requests.
///
/// Set via `@TaskLocal` so that callers (adapters, orchestrators) can signal
/// priority without changing the `LLMProtocol` interface. `QueuedLLM` reads
/// the current value automatically.
public enum LLMQueuePriority: Sendable {
    /// Standard priority for new requests.
    case normal
    /// Elevated priority for requests continuing an agentic loop after tool
    /// execution. These are dequeued ahead of `.normal` requests.
    case continuation

    @TaskLocal public static var current: LLMQueuePriority = .normal
}

/// Configuration for the per-LLM request queue.
public struct LLMQueueConfiguration: Sendable {
    /// Maximum number of requests waiting in the queue. `nil` means unlimited.
    /// When full, new requests are rejected with `LLMError.queueFull`.
    public let maxQueueSize: Int?

    /// Maximum time a request may wait in the queue before being executed.
    /// `nil` means no timeout. When exceeded, the request is rejected with `LLMError.queueTimeout`.
    public let requestTimeout: TimeInterval?

    /// Maximum number of requests executing concurrently. Defaults to `1`.
    /// Raise only for providers that explicitly support safe parallel requests.
    public let maxConcurrentRequests: Int

    public init(
        maxQueueSize: Int? = nil,
        requestTimeout: TimeInterval? = nil,
        maxConcurrentRequests: Int = 1
    ) {
        precondition(maxConcurrentRequests >= 1, "maxConcurrentRequests must be at least 1")
        self.maxQueueSize = maxQueueSize
        self.requestTimeout = requestTimeout
        self.maxConcurrentRequests = maxConcurrentRequests
    }
}

/// FIFO request queue that serializes access to a shared LLM instance.
///
/// Each queued item waits until a concurrency slot is available. The item is
/// appended to `pending` synchronously (before any suspension) via
/// `AsyncStream.makeStream()`, eliminating races between enqueue and
/// cancel/timeout.
public actor LLMRequestQueue {
    private let configuration: LLMQueueConfiguration

    private var activeCount: Int = 0

    private struct PendingItem {
        let id: UUID
        let priority: LLMQueuePriority
        let signal: AsyncStream<Void>.Continuation
    }

    private var pending: [PendingItem] = []

    public init(configuration: LLMQueueConfiguration = LLMQueueConfiguration()) {
        self.configuration = configuration
    }

    /// Number of requests currently waiting in the queue (not yet executing).
    public var queueDepth: Int {
        pending.count
    }

    /// Number of requests currently executing.
    public var activeRequestCount: Int {
        activeCount
    }

    /// Acquire a queue slot. Suspends until this request reaches the front.
    ///
    /// The returned `QueueSlot` **must** be released when the LLM call completes
    /// (whether success, failure, or cancellation) by calling `release(_:)`.
    ///
    /// - Parameter priority: Queue priority. `.continuation` items are dequeued
    ///   ahead of `.normal` items.
    /// - Throws: `LLMError.queueFull` if the queue is at capacity.
    /// - Throws: `LLMError.queueTimeout` if the request waited longer than `requestTimeout`.
    /// - Throws: `CancellationError` if the calling `Task` is cancelled while queued.
    public func acquire(priority: LLMQueuePriority = .normal) async throws -> QueueSlot {
        if let maxSize = configuration.maxQueueSize, pending.count >= maxSize {
            throw LLMError.queueFull
        }

        if activeCount < configuration.maxConcurrentRequests {
            activeCount += 1
            return QueueSlot(id: UUID())
        }

        let itemId = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        pending.append(PendingItem(id: itemId, priority: priority, signal: continuation))

        if let timeout = configuration.requestTimeout {
            let wasSignaled = try await waitWithTimeout(
                stream: stream, timeout: timeout, itemId: itemId
            )
            if !wasSignaled {
                throw CancellationError()
            }
        } else {
            let wasSignaled = await waitWithCancellation(
                stream: stream, itemId: itemId
            )
            if !wasSignaled {
                throw CancellationError()
            }
        }

        return QueueSlot(id: itemId)
    }

    /// Release a previously acquired queue slot, allowing the next queued request to proceed.
    public func release(_ slot: QueueSlot) {
        activeCount -= 1
        drainNext()
    }

    // MARK: - Internal

    /// Wait for the signal stream, supporting cooperative cancellation.
    /// Returns `true` if properly signaled (slot acquired), `false` if cancelled.
    private func waitWithCancellation(
        stream: AsyncStream<Void>,
        itemId: UUID
    ) async -> Bool {
        await withTaskCancellationHandler {
            var iterator = stream.makeAsyncIterator()
            let result: Void? = await iterator.next()
            return result != nil
        } onCancel: {
            Task { await self.cancelPending(id: itemId) }
        }
    }

    /// Wait for the signal stream with a timeout.
    /// Returns `true` if properly signaled, throws on timeout.
    private func waitWithTimeout(
        stream: AsyncStream<Void>,
        timeout: TimeInterval,
        itemId: UUID
    ) async throws -> Bool {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                let result: Void? = await iterator.next()
                return result != nil
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw LLMError.queueTimeout
            }

            do {
                guard let wasSignaled = try await group.next() else {
                    throw LLMError.queueTimeout
                }
                group.cancelAll()
                return wasSignaled
            } catch {
                group.cancelAll()
                removePending(id: itemId)
                throw error
            }
        }
    }

    private func drainNext() {
        guard activeCount < configuration.maxConcurrentRequests, !pending.isEmpty else {
            return
        }

        let index: Int
        if let continuationIndex = pending.firstIndex(where: { $0.priority == .continuation }) {
            index = continuationIndex
        } else {
            index = pending.startIndex
        }

        let next = pending.remove(at: index)
        activeCount += 1
        next.signal.yield()
        next.signal.finish()
    }

    private func removePending(id: UUID) {
        if let index = pending.firstIndex(where: { $0.id == id }) {
            let item = pending.remove(at: index)
            item.signal.finish()
        }
    }

    private func cancelPending(id: UUID) {
        removePending(id: id)
    }
}

/// Opaque token representing a held queue slot. Must be released via `LLMRequestQueue.release(_:)`.
public struct QueueSlot: Sendable {
    let id: UUID
}
