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

/// MCP Server implementation that leverages the MCP library for protocol handling
public actor MCPServer {
    private let logger = Logger(label: "MCPServer")
    
    // MARK: - Configuration
    public let name: String
    public let version: String
    
    // MARK: - State
    private var isRunning = false
    private var toolRegistry: ToolRegistry
    private var environment: [String: String]
    
    // MARK: - MCP Server
    private var mcpServer: MCP.Server?
    private var transport: (any MCP.Transport)?
    
    // MARK: - Initialization
    
    public init(name: String, version: String = "1.0.0") {
        self.name = name
        self.version = version
        self.toolRegistry = ToolRegistry()
        self.environment = ProcessInfo.processInfo.environment
    }
    
    // MARK: - Public Interface
    
    /// Register a tool with the server
    /// - Parameters:
    ///   - name: The name of the tool
    ///   - description: Description of what the tool does
    ///   - inputSchema: JSON schema for the tool's input parameters
    ///   - handler: The closure that executes the tool
    public func registerTool(
        name: String,
        description: String,
        inputSchema: JSON,
        handler: @escaping @Sendable ([String: JSON]) async throws -> MCPToolResult
    ) async {
        await toolRegistry.registerTool(
            name: name,
            description: description,
            inputSchema: inputSchema,
            handler: handler
        )
        logger.info("Registered tool: \(name)")
    }
    
    /// Get the current environment variables (useful for custom authentication)
    public var environmentVariables: [String: String] {
        return environment
    }
    
    /// Start the MCP server
    public func start() async throws {
        try await start(transport: MCP.StdioTransport())
    }
    
    /// Start the MCP server with a custom transport
    public func start(transport: any MCP.Transport) async throws {
        guard !isRunning else {
            throw MCPServerError.alreadyRunning
        }
        
        logger.info("Starting MCP server: \(name) v\(version)")
        
        // Store the provided transport
        self.transport = transport
        
        // Create MCP server with capabilities
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
        logger.info("MCP server started successfully")

        await mcpServer?.waitUntilCompleted()
    }
    
    /// Stop the MCP server
    public func stop() async {
        guard isRunning else { return }
        
        logger.info("Stopping MCP server: \(name)")
        
        // Stop MCP server
        await mcpServer?.stop()
        mcpServer = nil
        
        // Stop transport
        await transport?.disconnect()
        transport = nil
        
        isRunning = false
        logger.info("MCP server stopped")
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
