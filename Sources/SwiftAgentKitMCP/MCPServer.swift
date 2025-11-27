//
//  MCPServer.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 4/12/25.
//

import Foundation
import Logging
import MCP
import SwiftAgentKit
import EasyJSON
import Network
/// Available transport types for MCP server
public enum TransportType {
    case stdio // Automatically handles both chunked and non-chunked messages
    case httpClient(endpoint: URL, streaming: Bool = true, sseInitializationTimeout: TimeInterval = 10)
    case network(connection: NWConnection)
    
    /// Create the appropriate transport instance
    func createTransport() -> any MCP.Transport {
        switch self {
        case .stdio:
            // Use adaptive stdio transport that handles both chunked and non-chunked
            return AdaptiveStdioTransport()
        case .httpClient(let endpoint, let streaming, let timeout):
            return MCP.HTTPClientTransport(
                endpoint: endpoint,
                streaming: streaming,
                sseInitializationTimeout: timeout
            )
        case .network(let connection):
            return MCP.NetworkTransport(connection: connection)
        }
    }
}

/// MCP Server implementation that leverages the MCP library for protocol handling
public actor MCPServer {
    private let logger: Logger
    
    // MARK: - Configuration
    public let name: String
    public let version: String
    private let transportType: TransportType
    
    // MARK: - State
    private var isRunning = false
    private var toolRegistry: ToolRegistry
    private var environment: [String: String]
    
    // MARK: - MCP Server
    private var mcpServer: MCP.Server?
    private var transport: (any MCP.Transport)?
    
    // MARK: - Initialization
    
    /// Initialize an MCP server with the specified name, version, and transport type
    /// - Parameters:
    ///   - name: The name of the server
    ///   - version: The version of the server (defaults to "1.0.0")
    ///   - transportType: The type of transport to use (defaults to stdio)
    public init(
        name: String,
        version: String = "1.0.0",
        transportType: TransportType = .stdio,
        logger: Logger? = nil
    ) {
        self.name = name
        self.version = version
        self.transportType = transportType
        let resolvedLogger = logger ?? SwiftAgentKitLogging.logger(
            for: .mcp("MCPServer"),
            metadata: SwiftAgentKitLogging.metadata(
                ("server", .string(name)),
                ("version", .string(version))
            )
        )
        self.logger = resolvedLogger
        self.toolRegistry = ToolRegistry(
            logger: SwiftAgentKitLogging.logger(
                for: .mcp("ToolRegistry"),
                metadata: SwiftAgentKitLogging.metadata(("server", .string(name)))
            )
        )
        self.environment = ProcessInfo.processInfo.environment
    }
    
    // MARK: - Public Interface
    

    
    /// Register a tool with the server using a ToolDefinition
    /// - Parameters:
    ///   - toolDefinition: The tool definition containing name, description, and parameters
    ///   - handler: The closure that executes the tool
    public func registerTool(
        toolDefinition: ToolDefinition,
        handler: @escaping @Sendable ([String: JSON]) async throws -> MCPToolResult
    ) async {
        // Convert ToolDefinition to JSON schema format
        let inputSchema = toolDefinition.toInputSchemaJSON()
        
        await toolRegistry.registerTool(
            name: toolDefinition.name,
            description: toolDefinition.description,
            inputSchema: inputSchema,
            handler: handler
        )
        logger.info(
            "Registered tool",
            metadata: SwiftAgentKitLogging.metadata(("tool", .string(toolDefinition.name)))
        )
    }
    
    /// Get the current environment variables (useful for custom authentication)
    public var environmentVariables: [String: String] {
        return environment
    }
    
    /// Start the MCP server
    public func start() async throws {
        try await start(transport: transportType.createTransport())
    }
    
    /// Start the MCP server with a custom transport
    public func start(transport: any MCP.Transport) async throws {
        guard !isRunning else {
            throw MCPServerError.alreadyRunning
        }
        
        logger.info(
            "Starting MCP server",
            metadata: SwiftAgentKitLogging.metadata(
                ("server", .string(name)),
                ("version", .string(version))
            )
        )
        
        // Store the provided transport
        self.transport = transport
        
        // Create MCP server with capabilities
        // Note: Chunking support is transparent and automatic - no capability negotiation needed
        // Both server and client adaptively handle chunked and non-chunked messages
        let capabilities = MCP.Server.Capabilities(
            prompts: nil,
            resources: nil,
            tools: await toolRegistry.hasTools ? .init() : nil
        )
        
        mcpServer = MCP.Server(
            name: name,
            version: version,
            capabilities: capabilities
        )
        
        // Register tool handlers
        await mcpServer?.withMethodHandler(MCP.ListTools.self) { [weak self] _ in
            guard let self = self else {
                throw MCPError.internalError("Server was deallocated")
            }
            
            let tools = await self.toolRegistry.listTools()
            return MCP.ListTools.Result(tools: tools)
        }
        
        await mcpServer?.withMethodHandler(MCP.CallTool.self) { [weak self] params in
            guard let self = self else {
                throw MCPError.internalError("Server was deallocated")
            }
            
            let result = try await self.toolRegistry.executeTool(
                name: params.name,
                arguments: params.arguments ?? [:]
            )
            
            // Convert MCPToolResult to MCP Tool.Content
            let content = await self.convertToMCPContent(result)
            
            return MCP.CallTool.Result(
                content: [content],
                isError: result.isError
            )
        }
        
        // Start the MCP server
        try await mcpServer?.start(transport: transport)
        
        isRunning = true
        logger.info(
            "MCP server started successfully",
            metadata: SwiftAgentKitLogging.metadata(
                ("server", .string(name)),
                ("version", .string(version))
            )
        )

        await mcpServer?.waitUntilCompleted()
    }
    
    /// Stop the MCP server
    public func stop() async {
        guard isRunning else { return }
        
        logger.info(
            "Stopping MCP server",
            metadata: SwiftAgentKitLogging.metadata(
                ("server", .string(name)),
                ("version", .string(version))
            )
        )
        
        // Stop MCP server
        await mcpServer?.stop()
        mcpServer = nil
        
        // Stop transport
        await transport?.disconnect()
        transport = nil
        
        isRunning = false
        logger.info(
            "MCP server stopped",
            metadata: SwiftAgentKitLogging.metadata(
                ("server", .string(name)),
                ("version", .string(version))
            )
        )
    }
    
    /// Diagnostic method to test if the server is properly configured
    public func diagnosticInfo() async -> [String: String] {
        var info: [String: String] = [:]
        info["name"] = name
        info["version"] = version
        info["isRunning"] = String(isRunning)
        info["hasTransport"] = String(transport != nil)
        info["hasTools"] = String(await toolRegistry.hasTools)
        
        if let transport = transport {
            info["transportType"] = String(describing: type(of: transport))
        }
        
        return info
    }
    
    // MARK: - Private Methods
    
    /// Convert MCPToolResult to MCP Tool.Content
    private func convertToMCPContent(_ result: MCPToolResult) -> MCP.Tool.Content {
        switch result {
        case .success(let message):
            return .text(message)
        case .error(let code, let message):
            // For errors, we return text content but mark it as an error
            return .text("Error [\(code)]: \(message)")
        }
    }
    

}

// MARK: - ToolDefinition Extensions

extension ToolDefinition {
    /// Convert the tool definition to a JSON schema format suitable for MCP input schema
    func toInputSchemaJSON() -> JSON {
        var properties: [String: JSON] = [:]
        var required: [JSON] = []
        
        for parameter in parameters {
            properties[parameter.name] = .object([
                "type": .string(parameter.type),
                "description": .string(parameter.description)
            ])
            
            if parameter.required {
                required.append(.string(parameter.name))
            }
        }
        
        return .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required)
        ])
    }
}

// MARK: - Supporting Types

public enum MCPServerError: LocalizedError {
    case alreadyRunning
    case transportNotInitialized
    case invalidMessageFormat
    case methodNotSupported(String)
    case invalidParams
    
    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "MCP server is already running"
        case .transportNotInitialized:
            return "Transport not initialized"
        case .invalidMessageFormat:
            return "Invalid message format"
        case .methodNotSupported(let method):
            return "Method not supported: \(method)"
        case .invalidParams:
            return "Invalid parameters"
        }
    }
}

public enum MCPToolResult: Sendable {
    case success(String)
    case error(String, String) // code, message
    
    /// Check if this result represents an error
    public var isError: Bool {
        switch self {
        case .success:
            return false
        case .error:
            return true
        }
    }
}
