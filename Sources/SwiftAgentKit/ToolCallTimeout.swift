import Foundation

/// Thrown when ``withToolCallTimeout(_:toolName:operation:)`` elapses before the operation completes.
///
/// Cancellation is cooperative: the timed-out ``Task`` is cancelled, but blocking synchronous work may not stop immediately.
public struct ToolCallTimeoutError: Error, Sendable {
    public let timeout: TimeInterval
    public let toolName: String?

    public init(timeout: TimeInterval, toolName: String? = nil) {
        self.timeout = timeout
        self.toolName = toolName
    }

    /// User- and LLM-facing message (seconds rounded for readability).
    public var message: String {
        let seconds = max(1, Int(timeout.rounded(.towardZero)))
        if let name = toolName, !name.isEmpty {
            return "Tool call timed out after \(seconds) second(s) (tool: \(name))."
        }
        return "Tool call timed out after \(seconds) second(s)."
    }
}

extension ToolCallTimeoutError: LocalizedError {
    public var errorDescription: String? { message }
}

private enum ToolCallRaceOutcome<T: Sendable>: Sendable {
    case value(Result<T, Error>)
    case timedOut
    case sleepAborted
}

/// Runs `operation` and completes when it finishes or when `timeout` elapses, whichever comes first.
///
/// - Parameters:
///   - timeout: Maximum wall-clock time in seconds.
///   - toolName: Optional tool name for errors and logging.
///   - operation: Async work to bound; cancellation is delivered to this task when the timeout wins.
/// - Returns: The operation’s value if it finishes in time.
/// - Throws: ``ToolCallTimeoutError`` if time elapses first, or any error thrown by `operation`.
public func withToolCallTimeout<T: Sendable>(
    _ timeout: TimeInterval,
    toolName: String? = nil,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: ToolCallRaceOutcome<T>.self) { group in
        group.addTask {
            do {
                return .value(.success(try await operation()))
            } catch {
                return .value(.failure(error))
            }
        }
        group.addTask {
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return .timedOut
            } catch {
                return .sleepAborted
            }
        }
        while let outcome = try await group.next() {
            switch outcome {
            case .value(let result):
                group.cancelAll()
                switch result {
                case .success(let value):
                    return value
                case .failure(let error):
                    throw error
                }
            case .timedOut:
                group.cancelAll()
                throw ToolCallTimeoutError(timeout: timeout, toolName: toolName)
            case .sleepAborted:
                continue
            }
        }
        throw CancellationError()
    }
}
