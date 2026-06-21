//
//  JSONRPCID.swift
//  SwiftAgentKit
//

import Foundation

/// JSON-RPC request id — integer or string per JSON-RPC 2.0.
public enum JSONRPCID: Codable, Sendable, Hashable {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSON-RPC id")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }

    /// Returns the integer value when the id is an int, otherwise nil.
    public var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }
}

extension JSONRPCID: CustomStringConvertible {
    public var description: String {
        switch self {
        case .int(let value): return String(value)
        case .string(let value): return value
        }
    }
}
