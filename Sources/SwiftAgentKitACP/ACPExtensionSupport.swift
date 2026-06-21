//
//  ACPExtensionSupport.swift
//  SwiftAgentKitACP
//

import EasyJSON
import Foundation
import SwiftAgentKit

public enum ACPExtensionError: Error, LocalizedError, Sendable {
    case invalidMethodName(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMethodName(let method):
            return "Extension methods must start with '_': \(method)"
        }
    }
}

public enum ACPExtensionSupport {
    public static func validateExtensionMethod(_ method: String) throws {
        guard method.hasPrefix("_") else {
            throw ACPExtensionError.invalidMethodName(method)
        }
    }

    public static func decodeParams(_ data: Data) throws -> JSON {
        try JSONDecoder().decode(JSON.self, from: data)
    }

    public static func encodeResult(_ result: JSON) throws -> Data {
        try JSONEncoder().encode(result)
    }

    public static func withExtensionMeta(
        on capabilities: ACPAgentCapabilities,
        namespace: String,
        features: JSON
    ) -> ACPAgentCapabilities {
        var updated = capabilities
        var meta = updated.meta ?? .object([:])
        if case .object(var dict) = meta {
            dict[namespace] = features
            meta = .object(dict)
        } else {
            meta = .object([namespace: features])
        }
        updated.meta = meta
        return updated
    }

    public static func withExtensionMeta(
        on capabilities: ACPClientCapabilities,
        namespace: String,
        features: JSON
    ) -> ACPClientCapabilities {
        var updated = capabilities
        var meta = updated.meta ?? .object([:])
        if case .object(var dict) = meta {
            dict[namespace] = features
            meta = .object(dict)
        } else {
            meta = .object([namespace: features])
        }
        updated.meta = meta
        return updated
    }
}
