//
//  MCPServerManager.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 5/17/25.
//

import EasyJSON
import Foundation
import Logging
import SwiftAgentKit

/// Manages the lifecycle of MCP server processes.
///
/// The subprocess boot APIs (`bootServer(bootCall:globalEnvironment:)`, `bootServers(config:)`,
/// and `bootServer(named:config:)`) are only compiled on platforms where
/// ``SwiftAgentKit/SubprocessAvailability/isSupported`` is `true` (macOS, Linux, Windows).
/// They live in `MCPServerManager+SubprocessBoot.swift`. On platforms without the `Process`
/// API (e.g. iOS, visionOS), those methods are not available; use remote servers or
/// pre-connected clients instead.
public actor MCPServerManager {
    
    // Internal (not private) so the subprocess-boot extension in a separate file can log.
    let logger: Logger
    
    public init(logger: Logger? = nil) {
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .mcp("MCPServerManager")
        )
    }
}

// MARK: - Extensions

extension JSON {
    
    var mcpEnvironment: [String: String] {
        var result = [String: String]()
        
        guard case .object(let object) = self else {
            return [:]
        }
        
        for (key, value) in object {
            let stringValue: String? = {
                if case .string(let string) = value {
                    return string
                } else if case .integer(let interger) = value {
                    return String(interger)
                } else if case .double(let double) = value {
                    return String(double)
                } else if case .boolean(let boolean) = value {
                    return boolean ? "true" : "false"
                } else {
                    return nil
                }
            }()
            if let stringValue {
                result[key] = stringValue
            }
        }
        return result
    }
}

// MARK: - Errors

public enum MCPServerManagerError: Error, LocalizedError {
    case serverNotFound(String)
    case serverStartupFailed(String, Error)
    case subprocessesUnsupported
    
    public var errorDescription: String? {
        switch self {
        case .serverNotFound(let name):
            return "MCP server '\(name)' not found in configuration"
        case .serverStartupFailed(let name, let error):
            return "Failed to start MCP server '\(name)': \(error.localizedDescription)"
        case .subprocessesUnsupported:
            return SubprocessAvailabilityError.subprocessesUnsupported.errorDescription
        }
    }
} 