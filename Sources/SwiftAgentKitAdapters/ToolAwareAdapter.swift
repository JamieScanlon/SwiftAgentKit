//
//  ToolAwareAdapter.swift
//  SwiftAgentKitAdapters
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import Logging
import SwiftAgentKit
import SwiftAgentKitA2A

/// Enhanced adapter that can use tools while keeping the base adapter unchanged
public struct ToolAwareAdapter: AgentAdapter {
    private let baseAdapter: AgentAdapter
    private let toolManager: ToolManager?
    private let logger = Logger(label: "ToolAwareAdapter")
    
    public init(
        baseAdapter: AgentAdapter,
        toolManager: ToolManager? = nil
    ) {
        self.baseAdapter = baseAdapter
        self.toolManager = toolManager
    }
    
    // MARK: - AgentAdapter Implementation
    
    public var cardCapabilities: AgentCard.AgentCapabilities {
        baseAdapter.cardCapabilities
    }
    
    public var skills: [AgentCard.AgentSkill] {
        baseAdapter.skills
    }
    
    public var defaultInputModes: [String] { baseAdapter.defaultInputModes }
    public var defaultOutputModes: [String] { baseAdapter.defaultOutputModes }
    
    public func handleSend(_ params: MessageSendParams, store: TaskStore) async throws -> A2ATask {
        guard let toolManager = toolManager else {
            // No tools available, use base adapter
            return try await baseAdapter.handleSend(params, store: store)
        }
        
        // TODO: Implement enhanced handling with tool support
        // For now, just use the base adapter
        logger.info("Tool manager available with \(toolManager.allTools.count) tools, but tool integration not yet implemented")
        return try await baseAdapter.handleSend(params, store: store)
    }
    
    public func handleStream(_ params: MessageSendParams, store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws {
        guard let toolManager = toolManager else {
            // No tools available, use base adapter
            try await baseAdapter.handleStream(params, store: store, eventSink: eventSink)
            return
        }
        
        // TODO: Implement enhanced streaming with tool support
        // For now, just use the base adapter
        logger.info("Tool manager available with \(toolManager.allTools.count) tools, but streaming tool integration not yet implemented")
        try await baseAdapter.handleStream(params, store: store, eventSink: eventSink)
    }
} 