//
//  JSONRPCTestHelpers.swift
//  SwiftAgentKitTests
//

import Foundation
import SwiftAgentKit

enum JSONRPCTestHelpers {
    static func roundTripCodable<T: Codable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func connectionErrorsEqual(_ lhs: JSONRPCConnectionError, _ rhs: JSONRPCConnectionError) -> Bool {
        switch (lhs, rhs) {
        case (.notConnected, .notConnected): return true
        case (.parseError, .parseError): return true
        case (.invalidRequest, .invalidRequest): return true
        case (.encodingFailed, .encodingFailed): return true
        case (.disconnected, .disconnected): return true
        case (.methodNotFound(let a), .methodNotFound(let b)): return a == b
        case (.remoteError(let a), .remoteError(let b)): return a.code == b.code && a.message == b.message
        default: return false
        }
    }
}
