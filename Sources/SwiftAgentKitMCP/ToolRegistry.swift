//
//  ToolRegistry.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 4/12/25.
//

import Foundation
import Logging
import MCP
import EasyJSON

/// Manages tool registration and execution for MCP servers
public actor ToolRegistry {
    private let logger = Logger(label: "ToolRegistry")
    
    // MARK: - Storage
    private var tools: [String: RegisteredTool] = [:]
    
    // MARK: - Public Interface
    
    /// Check if the registry has any tools
    public var hasTools: Bool {
        return !tools.isEmpty
    }
    
    /// Register a tool with the registry
    /// - Parameters:
    ///   - name: The name of the tool
    ///   - description: Description of what the tool does
    ///   - inputSchema: JSON schema for the tool's input parameters
    ///   - handler: The closure that executes the tool
    public func registerTool(
        name: String,
        description: String,
        inputSchema: [String: String],
        handler: @escaping @Sendable ([String: JSON]) async throws -> MCPToolResult
    ) {
        let tool = RegisteredTool(
            name: name,
            description: description,
            inputSchema: inputSchema,
            handler: handler
        )
        
        tools[name] = tool
        logger.info("Registered tool: \(name)")
    }
    
    /// List all registered tools in MCP format
    public func listTools() -> [Tool] {
        return tools.values.map { registeredTool in
            registeredTool.toMCPTool()
        }
    }
    
    /// Execute a tool by name
    /// - Parameters:
    ///   - name: The name of the tool to execute
    ///   - arguments: The arguments to pass to the tool
    /// - Returns: The result of the tool execution
    public func executeTool(
        name: String,
        arguments: [String: MCP.Value]
    ) async throws -> MCPToolResult {
        guard let tool = tools[name] else {
            throw ToolRegistryError.toolNotFound(name)
        }
        
        logger.info("Executing tool: \(name)")
        
        // Convert MCP.Value to JSON types for the handler
        let args = arguments.mapValues { convertMCPValueToJSON($0) }
        
        do {
            let result = try await tool.handler(args)
            logger.info("Tool \(name) executed successfully")
            return result
        } catch {
            logger.error("Tool \(name) execution failed: \(error)")
            return .error("EXECUTION_ERROR", error.localizedDescription)
        }
    }
    
    /// Unregister a tool
    /// - Parameter name: The name of the tool to unregister
    public func unregisterTool(name: String) {
        tools.removeValue(forKey: name)
        logger.info("Unregistered tool: \(name)")
    }
    
    /// Clear all tools
    public func clearTools() {
        tools.removeAll()
        logger.info("Cleared all tools")
    }
    
    // MARK: - Private Helper Methods
    
    /// Convert MCP.Value to Any
    private func convertMCPValueToAny(_ value: MCP.Value) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let bool):
            return bool
        case .int(let int):
            return int
        case .double(let double):
            return double
        case .string(let string):
            return string
        case .data(_, let data):
            return data
        case .array(let array):
            return array.map { convertMCPValueToAny($0) }
        case .object(let object):
            return object.mapValues { convertMCPValueToAny($0) }
        }
    }
    
    /// Convert MCP.Value to JSON types
    private func convertMCPValueToJSON(_ value: MCP.Value) -> JSON {
        switch value {
        case .null:
            return .string("") // EasyJSON doesn't have null, use empty string
        case .bool(let bool):
            return .boolean(bool)
        case .int(let int):
            return .integer(int)
        case .double(let double):
            return .double(double)
        case .string(let string):
            return .string(string)
        case .data(_, let data):
            return .string(String(data: data, encoding: .utf8) ?? "") // Convert data to string
        case .array(let array):
            return .array(array.map { convertMCPValueToJSON($0) })
        case .object(let object):
            return .object(object.mapValues { convertMCPValueToJSON($0) })
        }
    }
}

// MARK: - Supporting Types

/// Represents a registered tool in the registry
private struct RegisteredTool {
    let name: String
    let description: String
    let inputSchema: [String: String]
    let handler: @Sendable ([String: JSON]) async throws -> MCPToolResult
    
    /// Convert to MCP Tool format
    func toMCPTool() -> Tool {
        return Tool(
            name: name,
            description: description,
            inputSchema: convertToMCPInputSchema(inputSchema)
        )
    }
    
    /// Convert the input schema to MCP format
    private func convertToMCPInputSchema(_ schema: [String: String]) -> MCP.Value {
        // This is a simplified conversion - in practice, you might want more sophisticated schema conversion
        var mcpSchema: [String: MCP.Value] = [:]
        
        for (key, value) in schema {
            mcpSchema[key] = .string(value)
        }
        
        return .object(mcpSchema)
    }
    
    /// Convert a value to MCP format
    private func convertValueToMCP(_ value: Any) -> MCP.Value {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let array as [Any]:
            return .array(array.map { convertValueToMCP($0) })
        case let dictionary as [String: Any]:
            return .object(dictionary.mapValues { convertValueToMCP($0) })
        default:
            return .string(String(describing: value))
        }
    }
}



public enum ToolRegistryError: LocalizedError {
    case toolNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        }
    }
}
