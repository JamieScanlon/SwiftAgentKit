import Foundation

/// A generic type for handling streaming operations that provide both streaming chunks and a final result
/// - `T`: The type of streaming chunks (must be Sendable)
/// - `R`: The type of the final result (must be Sendable)
public enum StreamResult<T: Sendable, R: Sendable>: Sendable {
    /// A streaming chunk of type T
    case stream(T)
    /// The final result of type R
    case complete(R)
}

/// Extension to provide convenient access to the associated values
public extension StreamResult {
    /// Extract the streaming value if this is a `.stream` case
    var streamValue: T? {
        switch self {
        case .stream(let value):
            return value
        case .complete:
            return nil
        }
    }
    
    /// Extract the final result if this is a `.complete` case
    var completeValue: R? {
        switch self {
        case .stream:
            return nil
        case .complete(let value):
            return value
        }
    }
    
    /// Check if this is a streaming chunk
    var isStream: Bool {
        switch self {
        case .stream:
            return true
        case .complete:
            return false
        }
    }
    
    /// Check if this is the final result
    var isComplete: Bool {
        switch self {
        case .stream:
            return false
        case .complete:
            return true
        }
    }
} 