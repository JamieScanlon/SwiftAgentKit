//
//  File.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 8/17/25.
//

import Foundation
import SwiftAgentKit
import SwiftAgentKitA2A

/// Protocol that extends AgentAdapter with tool-aware methods.
/// This protocol is used with the `ToolProxyAdapter` and provides tool-using versions of the send methods
/// Objects that implemplement this protocol are responsible for executing the tool calls within these medhods
public protocol ToolAwareAdapter: AgentAdapter {
    /// Handle a task send with available tools.
    /// - Parameters:
    ///   - params: The message parameters
    ///   - taskId: The ID of the task
    ///   - contextId: The context ID for this interaction
    ///   - toolProviders: `ToolProvider` objects used for listing available tools and executing them
    ///   - store: The task store
    func handleTaskSendWithTools(_ params: MessageSendParams, taskId: String, contextId: String, toolProviders: [ToolProvider], store: TaskStore) async throws
    
    /// Handle streaming with available tools
    /// - Parameters:
    ///   - params: The message parameters
    ///   - taskId: The ID of the task (should be unwrapped - tool methods require tracking)
    ///   - contextId: The context ID for this interaction
    ///   - toolProviders: `ToolProvider` objects used for listing available tools and executing them
    ///   - store: The task store (should be unwrapped - tool methods require tracking)
    ///   - eventSink: Callback for streaming events
    ///
    /// Note: Tool-aware methods typically require task tracking, so implementers should unwrap optionals
    func handleStreamWithTools(_ params: MessageSendParams, taskId: String?, contextId: String?, toolProviders: [ToolProvider], store: TaskStore?, eventSink: @escaping (Encodable) -> Void) async throws
}
