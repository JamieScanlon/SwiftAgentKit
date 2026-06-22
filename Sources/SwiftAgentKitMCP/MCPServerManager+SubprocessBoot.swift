//
//  MCPServerManager+SubprocessBoot.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 6/21/26.
//

#if os(macOS) || os(Linux) || os(Windows)
import EasyJSON
import Foundation
import Logging
import System
import SwiftAgentKit

extension MCPServerManager {

    /// Boots up an MCP server and returns the communication pipes and subprocess handle.
    /// - Parameters:
    ///   - bootCall: Configuration for the server to boot
    ///   - globalEnvironment: Global environment variables to merge with server-specific ones
    /// - Returns: Tuple of (inputPipe, outputPipe, process) for communicating with the server and terminating it on shutdown.
    /// - Throws: Errors if server startup fails
    public func bootServer(bootCall: MCPConfig.ServerBootCall, globalEnvironment: JSON = .object([:])) async throws -> (inPipe: Pipe, outPipe: Pipe, process: Process) {

        logger.info(
            "Booting MCP server",
            metadata: SwiftAgentKitLogging.metadata(("server", .string(bootCall.name)))
        )

        // Merge global and server-specific environment variables
        var environment = globalEnvironment.mcpEnvironment
        let bootCallEnvironment = bootCall.environment.mcpEnvironment
        environment.merge(bootCallEnvironment, uniquingKeysWith: { (_, new) in new })

        logger.debug(
            "Server command",
            metadata: SwiftAgentKitLogging.metadata(
                ("server", .string(bootCall.name)),
                ("command", .string(bootCall.command))
            )
        )
        logger.debug(
            "Server arguments",
            metadata: SwiftAgentKitLogging.metadata(
                ("server", .string(bootCall.name)),
                ("arguments", .stringConvertible(bootCall.arguments))
            )
        )
        logger.debug(
            "Server environment variables",
            metadata: SwiftAgentKitLogging.metadata(
                ("server", .string(bootCall.name)),
                ("environment", .string(environment.description))
            )
        )

        // Start the server process (retain `process` for shutdown; see ``MCPManager/shutdown()``).
        let launched = Shell.launchSubprocess(
            command: bootCall.command,
            arguments: bootCall.arguments,
            environment: environment,
            useShell: bootCall.useShell
        )

        logger.info(
            "MCP server started successfully",
            metadata: SwiftAgentKitLogging.metadata(("server", .string(bootCall.name)))
        )

        return (inPipe: launched.inPipe, outPipe: launched.outPipe, process: launched.process)
    }

    /// Boots up multiple MCP servers from a configuration
    /// - Parameter config: MCP configuration containing server definitions
    /// - Returns: Dictionary mapping server names to their communication pipes and subprocess handles
    /// - Throws: Errors if any server startup fails
    public func bootServers(config: MCPConfig) async throws -> [String: (inPipe: Pipe, outPipe: Pipe, process: Process)] {

        logger.info(
            "Booting MCP servers",
            metadata: SwiftAgentKitLogging.metadata(
                ("count", .stringConvertible(config.serverBootCalls.count))
            )
        )

        var serverPipes: [String: (inPipe: Pipe, outPipe: Pipe, process: Process)] = [:]

        for bootCall in config.serverBootCalls {
            let boot = try await bootServer(bootCall: bootCall, globalEnvironment: config.globalEnvironment)
            serverPipes[bootCall.name] = boot
        }

        logger.info(
            "Successfully booted MCP servers",
            metadata: SwiftAgentKitLogging.metadata(
                ("count", .stringConvertible(serverPipes.count))
            )
        )

        return serverPipes
    }

    /// Boots up a single MCP server by name from a configuration
    /// - Parameters:
    ///   - serverName: Name of the server to boot
    ///   - config: MCP configuration containing server definitions
    /// - Returns: Communication pipes and subprocess handle for the specified server
    /// - Throws: Errors if server not found or startup fails
    public func bootServer(named serverName: String, config: MCPConfig) async throws -> (inPipe: Pipe, outPipe: Pipe, process: Process) {

        guard let bootCall = config.serverBootCalls.first(where: { $0.name == serverName }) else {
            logger.error(
                "Server not found in configuration",
                metadata: SwiftAgentKitLogging.metadata(("server", .string(serverName)))
            )
            throw MCPServerManagerError.serverNotFound(serverName)
        }

        return try await bootServer(bootCall: bootCall, globalEnvironment: config.globalEnvironment)
    }
}
#endif
