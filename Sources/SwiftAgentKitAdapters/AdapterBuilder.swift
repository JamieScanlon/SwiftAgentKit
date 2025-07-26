//
//  AdapterBuilder.swift
//  SwiftAgentKitAdapters
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitMCP

/// Builder pattern for easily assembling adapters with different tool capabilities
public struct AdapterBuilder {
    private var baseAdapter: AgentAdapter?
    private var providers: [ToolProvider] = []
    private let logger = Logger(label: "AdapterBuilder")
    
    public init() {}
    
    /// Set the base LLM adapter
    public func withLLM(_ adapter: AgentAdapter) -> AdapterBuilder {
        var builder = self
        builder.baseAdapter = adapter
        return builder
    }
    
    /// Set the base LLM adapter that supports tool-aware methods
    public func withToolAwareLLM(_ adapter: ToolAwareAgentAdapter) -> AdapterBuilder {
        var builder = self
        builder.baseAdapter = adapter
        return builder
    }
    
    /// Add A2A clients as tool providers
    public func withA2AClients(_ clients: [A2AClient]) -> AdapterBuilder {
        var builder = self
        builder.providers.append(A2AToolProvider(clients: clients))
        return builder
    }
    
    /// Add MCP clients as tool providers
    public func withMCPClients(_ clients: [MCPClient]) -> AdapterBuilder {
        var builder = self
        builder.providers.append(MCPToolProvider(clients: clients))
        return builder
    }
    
    /// Add custom tool providers
    public func withToolProviders(_ providers: [ToolProvider]) -> AdapterBuilder {
        var builder = self
        builder.providers.append(contentsOf: providers)
        return builder
    }
    
    /// Build the final adapter
    public func build() -> AgentAdapter {
        guard let baseAdapter = baseAdapter else {
            fatalError("Base adapter must be specified using withLLM() or withToolAwareLLM()")
        }
        
        if providers.isEmpty {
            logger.info("Building basic adapter without tools")
            // If no tools, just return the base adapter directly
            return baseAdapter
        } else {
            let toolManager = ToolManager(providers: providers)
            logger.info("Building tool-aware adapter with tool manager")
            
            // Check if the base adapter supports tool-aware methods
            if let toolAwareAdapter = baseAdapter as? ToolAwareAgentAdapter {
                return ToolAwareAdapter(baseAdapter: toolAwareAdapter, toolManager: toolManager)
            } else {
                // Fall back to the old approach for non-tool-aware adapters
                // This creates a wrapper that enhances messages with tool information
                return ToolAwareAdapter(baseAdapter: baseAdapter, toolManager: toolManager)
            }
        }
    }
}

// MARK: - Convenience Extensions

extension AdapterBuilder {
    /// Convenience method to add a single A2A client
    public func withA2AClient(_ client: A2AClient) -> AdapterBuilder {
        withA2AClients([client])
    }
    
    /// Convenience method to add a single MCP client
    public func withMCPClient(_ client: MCPClient) -> AdapterBuilder {
        withMCPClients([client])
    }
    
    /// Convenience method to add a single tool provider
    public func withToolProvider(_ provider: ToolProvider) -> AdapterBuilder {
        withToolProviders([provider])
    }
} 