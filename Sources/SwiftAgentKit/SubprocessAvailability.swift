//
//  SubprocessAvailability.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 6/21/26.
//

import Foundation

/// Indicates whether the current platform can spawn subprocesses (via `Process`/`Shell`).
///
/// Subprocess support is available on macOS, Linux, and Windows. On platforms without the
/// `Process` API (e.g. iOS, visionOS), local stdio MCP servers cannot be booted; use remote
/// servers or pre-connected clients instead.
public enum SubprocessAvailability: Sendable {
    #if os(macOS) || os(Linux) || os(Windows)
    public static let isSupported = true
    #else
    public static let isSupported = false
    #endif
}

/// Errors related to subprocess availability on the current platform.
public enum SubprocessAvailabilityError: Error, LocalizedError, Sendable {
    case subprocessesUnsupported

    public var errorDescription: String? {
        switch self {
        case .subprocessesUnsupported:
            return "Local subprocess servers are not supported on this platform. Use remote servers or pre-connected clients."
        }
    }
}
