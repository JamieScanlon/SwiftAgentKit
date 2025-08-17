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
    /// Handle a message with available tools.
    /// - Parameters:
    ///   - params: The message parameters
    ///   - toolProvider: A `ToolProvider` used for listing available tools and executing them
    ///   - store: The task store
    /// - Returns: An A2A task representing the response
    func handleSendWithTools(_ params: MessageSendParams, task: A2ATask, toolProviders: [ToolProvider], store: TaskStore) async throws
    
    /// Handle streaming with available tools
    /// - Parameters:
    ///   - params: The message parameters
    ///   - toolProvider: A `ToolProvider` used for listing available tools and executing them
    ///   - store: The task store
    ///   - eventSink: Callback for streaming events
    func handleStreamWithTools(_ params: MessageSendParams, task: A2ATask, toolProviders: [ToolProvider], store: TaskStore, eventSink: @escaping (Encodable) -> Void) async throws
}
