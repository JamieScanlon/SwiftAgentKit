//
//  A2AClient.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 6/13/25.
//

import EasyJSON
import Foundation
import Logging
import SwiftAgentKit

// MARK: - Client Implementation

public actor A2AClient {
    
    public var agentCard: AgentCard?
    private let logger: Logger
    
    // MARK: Lifecylce
    
    init(
        server: A2AConfig.A2AConfigServer,
        bootCall: A2AConfig.ServerBootCall? = nil,
        logger: Logger? = nil
    ) {
        self.server = server
        self.bootCall = bootCall
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .a2a("A2AClient"),
            metadata: SwiftAgentKitLogging.metadata(
                ("serverName", .string(server.name)),
                ("serverURL", .string(server.url.absoluteString))
            )
        )
        
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }
    
    func initializeA2AClient(globalEnvironment: JSON = .object([:])) async throws {
        
        guard agentCard == nil else {
            throw A2AClientError.alreadyInitialized
        }
        
        var shouldWait = false
        if let bootCall {
            shouldWait = true
            var environment = globalEnvironment.a2aEnvironment
            let bootCallEnvironment = bootCall.environment.a2aEnvironment
            environment.merge(bootCallEnvironment, uniquingKeysWith: { (_, new) in new })
            let (_, outPipe) = Shell.shell(bootCall.command, arguments: bootCall.arguments, environment: environment)
            Task.detached {
                outPipe.fileHandleForReading.readabilityHandler = { pipeHandle in
                    let data = pipeHandle.availableData
                    self.logger.debug(
                        "Boot process output",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("output", .string(String(data: data, encoding: .utf8) ?? "")))
                    )
                }
            }
        }
        
        apiManager = RestAPIManager(baseURL: server.url)
        logger.info(
            "Initializing A2A client",
            metadata: SwiftAgentKitLogging.metadata(
                ("baseURL", .string(server.url.absoluteString))
            )
        )
        
        if shouldWait {
            var secondsToWait = 30
            while agentCard == nil && secondsToWait > 0 {
                do {
                    agentCard = try await getAgentCard()
                } catch {
                    logger.debug(
                        "Waiting for A2A server to become available",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("remainingSeconds", .stringConvertible(secondsToWait))
                        )
                    )
                }
                secondsToWait -= 1
                try? await Task.sleep(for: .seconds(1))
            }
        } else {
            agentCard = try await getAgentCard()
        }
        
        guard agentCard != nil else {
            logger.error("Failed to initialize A2A client; agent card not available")
            throw A2AClientError.failedToInitialize
        }
        
        logger.info("A2A client initialized successfully")
    }
    
    // MARK: Methods
    
    /// Sends a message to the agent and returns the result
    /// Implements the message/send RPC method from A2A spec
    public func sendMessage(params: MessageSendParams) async throws -> MessageResult {
        
        guard let apiManager else {
            throw A2AClientError.notInitialized
        }
        
        let jsonParams = try JSONSerialization.jsonObject(with: encoder.encode(params)) as? [String: Any] ?? [:]
        
        let response: [String: Sendable] = try await apiManager.jsonRequest("message/send", method: .post, parameters: jsonParams, headers: authHeaders)
        
        // Parse the response to determine if it's a message or task
        if let result = response["result"] as? [String: Any] {
            if let kind = result["kind"] as? String {
                switch kind {
                case "message":
                    let messageData = try JSONSerialization.data(withJSONObject: result)
                    let message = try decoder.decode(A2AMessage.self, from: messageData)
                    return .message(message)
                case "task":
                    let taskData = try JSONSerialization.data(withJSONObject: result)
                    let task = try decoder.decode(A2ATask.self, from: taskData)
                    return .task(task)
                default:
                    throw A2AClientError.invalidResponseType
                }
            }
        }
        
        throw A2AClientError.invalidResponse
    }
    
    /// Streams messages from the agent using Server-Sent Events
    /// Implements the message/stream RPC method from A2A spec
    func streamMessage(params: MessageSendParams) async throws -> AsyncStream<SendStreamingMessageSuccessResponse<MessageResult>> {
        
        guard let apiManager else {
            throw A2AClientError.notInitialized
        }
        
        let jsonRPCRequest = JSONRPCRequest<MessageSendParams>(id: requestId, params: params)
        requestId += 1
//        let jsonParams = try JSONSerialization.jsonObject(with: encoder.encode(params)) as? [String: Sendable] ?? [:]
        let jsonParams = try JSONSerialization.jsonObject(with: encoder.encode(jsonRPCRequest)) as? [String: Sendable] ?? [:]
        
        return AsyncStream { continuation in
            Task {
                
                let sseStream = await apiManager.sseRequest("message/stream", method: HTTPMethod.post, parameters: jsonParams, headers: authHeaders)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                for await json in sseStream {
                    // Extract common fields
                    let jsonrpc = json["jsonrpc"] as? String ?? "2.0"
                    let id = json["id"] as? Int ?? 1
                    
                    // Parse the result based on its type
                    if let result = json["result"] as? [String: Sendable] {
                        if let kind = result["kind"] as? String {
                            switch kind {
                            case "message":
                                if let messageData = try? JSONSerialization.data(withJSONObject: result),
                                   let message = try? decoder.decode(A2AMessage.self, from: messageData) {
                                    let messageResult = MessageResult.message(message)
                                    let response = SendStreamingMessageSuccessResponse(
                                        jsonrpc: jsonrpc,
                                        id: id,
                                        result: messageResult
                                    )
                                    continuation.yield(response)
                                }
                            case "task":
                                if let taskData = try? JSONSerialization.data(withJSONObject: result),
                                   let task = try? decoder.decode(A2ATask.self, from: taskData) {
                                    let messageResult = MessageResult.task(task)
                                    let response = SendStreamingMessageSuccessResponse(
                                        jsonrpc: jsonrpc,
                                        id: id,
                                        result: messageResult
                                    )
                                    continuation.yield(response)
                                }
                            case "status-update":
                                if let statusData = try? JSONSerialization.data(withJSONObject: result),
                                   let statusEvent = try? decoder.decode(TaskStatusUpdateEvent.self, from: statusData) {
                                    let messageResult = MessageResult.taskStatusUpdate(statusEvent)
                                    let response = SendStreamingMessageSuccessResponse(
                                        jsonrpc: jsonrpc,
                                        id: id,
                                        result: messageResult
                                    )
                                    continuation.yield(response)
                                }
                            case "artifact-update":
                                if let artifactData = try? JSONSerialization.data(withJSONObject: result),
                                   let artifactEvent = try? decoder.decode(TaskArtifactUpdateEvent.self, from: artifactData) {
                                    let messageResult = MessageResult.taskArtifactUpdate(artifactEvent)
                                    let response = SendStreamingMessageSuccessResponse(
                                        jsonrpc: jsonrpc,
                                        id: id,
                                        result: messageResult
                                    )
                                    continuation.yield(response)
                                }
                            default:
                                break
                            }
                        }
                    }
                }
                continuation.finish()
            }
        }
    }
    
    /// Gets the current status and results of a task
    /// Implements the tasks/get RPC method from A2A spec
    func getTask(params: TaskQueryParams) async throws -> A2ATask {
        
        guard let apiManager else {
            throw A2AClientError.notInitialized
        }
        
        let jsonParams = try JSONSerialization.jsonObject(with: encoder.encode(params)) as? [String: Any] ?? [:]
        
        return try await apiManager.decodableRequest("tasks/get", method: .post, parameters: jsonParams, headers: authHeaders)
    }
    
    /// Cancels a running task
    /// Implements the tasks/cancel RPC method from A2A spec
    func cancelTask(params: TaskIdParams) async throws -> A2ATask {
        
        guard let apiManager else {
            throw A2AClientError.notInitialized
        }
        
        let jsonParams = try JSONSerialization.jsonObject(with: encoder.encode(params)) as? [String: Any] ?? [:]
        
        return try await apiManager.decodableRequest("tasks/cancel", method: .post, parameters: jsonParams, headers: authHeaders)
    }
    
    /// Sets push notification configuration for a task
    /// Implements the tasks/pushNotificationConfig/set RPC method from A2A spec
    func updatePushNotificationConfig(params: TaskPushNotificationConfig) async throws -> TaskPushNotificationConfig {
        
        guard let apiManager else {
            throw A2AClientError.notInitialized
        }
        
        let jsonParams = try JSONSerialization.jsonObject(with: encoder.encode(params)) as? [String: Any] ?? [:]
        
        return try await apiManager.decodableRequest("tasks/pushNotificationConfig/set", method: .post, parameters: jsonParams, headers: authHeaders)
    }
    
    /// Gets push notification configuration for a task
    /// Implements the tasks/pushNotificationConfig/get RPC method from A2A spec
    func getPushNotificationConfig(params: TaskIdParams) async throws -> TaskPushNotificationConfig {
        
        guard let apiManager else {
            throw A2AClientError.notInitialized
        }
        
        let jsonParams = try JSONSerialization.jsonObject(with: encoder.encode(params)) as? [String: Any] ?? [:]
        
        return try await apiManager.decodableRequest("tasks/pushNotificationConfig/get", method: .post, parameters: jsonParams, headers: authHeaders)
    }
    
    /// Resubscribes to a task's event stream
    /// Implements the tasks/resubscribe RPC method from A2A spec
    func resubscribeToTask(params: TaskIdParams) async throws -> AsyncStream<SendStreamingMessageSuccessResponse<MessageResult>> {
        
        guard let apiManager else {
            throw A2AClientError.notInitialized
        }
        
        let jsonParams = try JSONSerialization.jsonObject(with: encoder.encode(params)) as? [String: Sendable] ?? [:]
        
        return AsyncStream { continuation in
            Task {
                let sseStream = await apiManager.sseRequest("tasks/resubscribe", method: HTTPMethod.post, parameters: jsonParams, headers: authHeaders)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                for await json in sseStream {
                    // Extract common fields
                    let jsonrpc = json["jsonrpc"] as? String ?? "2.0"
                    let id = json["id"] as? Int ?? 1
                    
                    // Parse the result based on its type
                    if let result = json["result"] as? [String: Sendable] {
                        if let kind = result["kind"] as? String {
                            switch kind {
                            case "message":
                                if let messageData = try? JSONSerialization.data(withJSONObject: result),
                                   let message = try? decoder.decode(A2AMessage.self, from: messageData) {
                                    let messageResult = MessageResult.message(message)
                                    let response = SendStreamingMessageSuccessResponse(
                                        jsonrpc: jsonrpc,
                                        id: id,
                                        result: messageResult
                                    )
                                    continuation.yield(response)
                                }
                            case "task":
                                if let taskData = try? JSONSerialization.data(withJSONObject: result),
                                   let task = try? decoder.decode(A2ATask.self, from: taskData) {
                                    let messageResult = MessageResult.task(task)
                                    let response = SendStreamingMessageSuccessResponse(
                                        jsonrpc: jsonrpc,
                                        id: id,
                                        result: messageResult
                                    )
                                    continuation.yield(response)
                                }
                            case "status-update":
                                if let statusData = try? JSONSerialization.data(withJSONObject: result),
                                   let statusEvent = try? decoder.decode(TaskStatusUpdateEvent.self, from: statusData) {
                                    let messageResult = MessageResult.taskStatusUpdate(statusEvent)
                                    let response = SendStreamingMessageSuccessResponse(
                                        jsonrpc: jsonrpc,
                                        id: id,
                                        result: messageResult
                                    )
                                    continuation.yield(response)
                                }
                            case "artifact-update":
                                if let artifactData = try? JSONSerialization.data(withJSONObject: result),
                                   let artifactEvent = try? decoder.decode(TaskArtifactUpdateEvent.self, from: artifactData) {
                                    let messageResult = MessageResult.taskArtifactUpdate(artifactEvent)
                                    let response = SendStreamingMessageSuccessResponse(
                                        jsonrpc: jsonrpc,
                                        id: id,
                                        result: messageResult
                                    )
                                    continuation.yield(response)
                                }
                            default:
                                break
                            }
                        }
                    }
                }
                continuation.finish()
            }
        }
    }
    
    /// Gets the authenticated extended agent card
    /// Implements the agent/authenticatedExtendedCard RPC method from A2A spec
    func getAuthenticatedExtendedCard() async throws -> AgentCard {
        
        guard let apiManager else {
            throw A2AClientError.notInitialized
        }
        
        return try await apiManager.decodableRequest("agent/authenticatedExtendedCard", method: .post, headers: authHeaders)
    }
    
    // MARK: - Private
    
    private let server: A2AConfig.A2AConfigServer
    private var apiManager: RestAPIManager?
    private var bootCall: A2AConfig.ServerBootCall?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var authHeaders: [String: String]? {
        if let token = server.token, !token.isEmpty {
            return ["Authorization": "Bearer \(token)"]
        }
        if let apiKey = server.apiKey, !apiKey.isEmpty {
            return ["X-API-Key": apiKey]
        }
        return nil
    }
    private var requestId: Int = 1
    
    /// Fetches the agent card from the standard location
    /// According to A2A spec: https://{server_domain}/.well-known/agent.json
    private func getAgentCard() async throws -> AgentCard {
        
        guard let apiManager else {
            throw A2AClientError.notInitialized
        }
        
        return try await apiManager.decodableRequest(".well-known/agent.json", headers: authHeaders)
    }
    
}

// MARK: - Extensions

extension JSON {
    
    var a2aEnvironment: [String: String] {
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

// MARK: - Types

public enum MessageResult: Encodable, Sendable {
    case message(A2AMessage)
    case task(A2ATask)
    case taskStatusUpdate(TaskStatusUpdateEvent)
    case taskArtifactUpdate(TaskArtifactUpdateEvent)
}

// MARK: - Custom Errors

enum A2AClientError: Error, LocalizedError {
    case alreadyInitialized
    case failedToInitialize
    case notInitialized
    case invalidResponse
    case invalidResponseType
    case networkError(Error)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from A2A server"
        case .invalidResponseType:
            return "Invalid response type from A2A server"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .alreadyInitialized:
            return "Called `initialize` on a client that was already initialized"
        case .failedToInitialize:
            return "Failed to initialize the A2A client"
        case .notInitialized:
            return "Called a communication method on the A2A client that was not initialized"
        }
    }
}
