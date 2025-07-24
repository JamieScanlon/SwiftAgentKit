//
//  MCPServerManager.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 5/17/25.
//

import EasyJSON
import Foundation
import Logging
import System
import SwiftAgentKit

/// Manages the lifecycle of MCP server processes
public actor MCPServerManager {
    
    private let logger = Logger(label: "MCPServerManager")
    
    public init() {}
    
    /// Boots up an MCP server and returns the communication pipes
    /// - Parameters:
    ///   - bootCall: Configuration for the server to boot
    ///   - globalEnvironment: Global environment variables to merge with server-specific ones
    /// - Returns: Tuple of (inputPipe, outputPipe) for communicating with the server
    /// - Throws: Errors if server startup fails
    public func bootServer(bootCall: MCPConfig.ServerBootCall, globalEnvironment: JSON = .object([:])) async throws -> (inPipe: Pipe, outPipe: Pipe) {
        
        logger.info("Booting MCP server: \(bootCall.name)")
        
        // Merge global and server-specific environment variables
        var environment = globalEnvironment.mcpEnvironment
        let bootCallEnvironment = bootCall.environment.mcpEnvironment
        environment.merge(bootCallEnvironment, uniquingKeysWith: { (_, new) in new })
        
        logger.debug("Server command: \(bootCall.command)")
        logger.debug("Server arguments: \(bootCall.arguments)")
        logger.debug("Environment variables: \(environment)")
        
        // Start the server process
        let (inPipe, outPipe) = Shell.shell(bootCall.command, arguments: bootCall.arguments, environment: environment)
        
        logger.info("MCP server '\(bootCall.name)' started successfully")
        
        return (inPipe: inPipe, outPipe: outPipe)
    }
    
    /// Boots up multiple MCP servers from a configuration
    /// - Parameter config: MCP configuration containing server definitions
    /// - Returns: Dictionary mapping server names to their communication pipes
    /// - Throws: Errors if any server startup fails
    public func bootServers(config: MCPConfig) async throws -> [String: (inPipe: Pipe, outPipe: Pipe)] {
        
        logger.info("Booting \(config.serverBootCalls.count) MCP servers")
        
        var serverPipes: [String: (inPipe: Pipe, outPipe: Pipe)] = [:]
        
        for bootCall in config.serverBootCalls {
            let pipes = try await bootServer(bootCall: bootCall, globalEnvironment: config.globalEnvironment)
            serverPipes[bootCall.name] = pipes
        }
        
        logger.info("Successfully booted all \(serverPipes.count) MCP servers")
        
        return serverPipes
    }
    
    /// Boots up a single MCP server by name from a configuration
    /// - Parameters:
    ///   - serverName: Name of the server to boot
    ///   - config: MCP configuration containing server definitions
    /// - Returns: Communication pipes for the specified server
    /// - Throws: Errors if server not found or startup fails
    public func bootServer(named serverName: String, config: MCPConfig) async throws -> (inPipe: Pipe, outPipe: Pipe) {
        
        guard let bootCall = config.serverBootCalls.first(where: { $0.name == serverName }) else {
            logger.error("Server '\(serverName)' not found in configuration")
            throw MCPServerManagerError.serverNotFound(serverName)
        }
        
        return try await bootServer(bootCall: bootCall, globalEnvironment: config.globalEnvironment)
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
    
    public var errorDescription: String? {
        switch self {
        case .serverNotFound(let name):
            return "MCP server '\(name)' not found in configuration"
        case .serverStartupFailed(let name, let error):
            return "Failed to start MCP server '\(name)': \(error.localizedDescription)"
        }
    }
} 