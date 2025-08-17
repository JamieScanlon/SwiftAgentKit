//
//  A2AModels.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import EasyJSON

// MARK: - A2A Spec Object Models

// MARK: Agent Card

/**
 * An AgentCard conveys key information:
 * - Overall details (version, name, description, uses)
 * - Skills: A set of capabilities the agent can perform
 * - Default modalities/content types supported by the agent.
 * - Authentication requirements
 */
public struct AgentCard: Codable, Sendable {
    /// Human-readable name of the agent.
    public let name: String
    /// Human-readable description. CommonMark MAY be used.
    public let description: String
    /// Base URL for the agent's A2A service. Must be absolute. HTTPS for production.
    public let url: String
    /// Agent or A2A implementation version string.
    public let version: String
    /// Specifies optional A2A protocol features supported (e.g., streaming, push notifications).
    public let capabilities: AgentCapabilities
    /// Input Media Types accepted by the agent.
    public let defaultInputModes: [String]
    /// Output Media Types produced by the agent.
    public let defaultOutputModes: [String]
    /// Array of skills. Must have at least one if the agent performs actions.
    public let skills: [AgentSkill]
    /// Information about the agent's provider.
    public var provider : AgentProvider? = nil
    /// A URL to an icon for the agent.
    public var iconUrl: String? = nil
    /// URL to human-readable documentation for the agent.
    public var documentationUrl: String? = nil
    /// Security scheme details used for authenticating with this agent. undefined implies no A2A-advertised auth (not recommended for production).
    public var securitySchemes: [String]? = nil
    /// Security requirements for contacting the agent.
    public var security: JSON? = nil
    
    /// Information about the organization or entity providing the agent.
    public struct AgentProvider: Codable, Sendable {
        /// Name of the organization/entity.
        public let organization: String
        /// URL for the provider's website/contact.
        public let url: String
        public init(organization: String, url: String) {
            self.organization = organization
            self.url = url
        }
    }
    
    /// Specifies an extension to the A2A protocol supported by the agent.
    public struct AgentExtension: Codable, Sendable {
        /// The URI for the supported extension.
        public var url: String
        /// Whether the agent requires clients to follow some protocol logic specific to the extension. Clients should expect failures when attempting to interact with a server that requires an extension the client does not support.
        public var required: Bool? = nil
        /// A description of how the extension is used by the agent.
        public var description: String? = nil
        /// Configuration parameters specific to the extension
        public var params: JSON? = nil
        public init(url: String, required: Bool? = nil, description: String? = nil, params: JSON? = nil) {
            self.url = url
            self.required = required
            self.description = description
            self.params = params
        }
    }
    
    /// Specifies optional A2A protocol features supported by the agent.
    public struct AgentCapabilities: Codable, Sendable {
        /// Indicates support for SSE streaming methods (message/stream, tasks/resubscribe).
        public var streaming: Bool? = nil
        /// Indicates support for push notification methods (tasks/pushNotificationConfig/*).
        public var pushNotifications: Bool? = nil
        /// Placeholder for future feature: exposing detailed task status change history.
        public var stateTransitionHistory: Bool? = nil
        /// A list of extensions supported by this agent.
        public var extensions: [AgentExtension]? = nil
        public init(streaming: Bool? = nil, pushNotifications: Bool? = nil, stateTransitionHistory: Bool? = nil, extensions: [AgentExtension]? = nil) {
            self.streaming = streaming
            self.pushNotifications = pushNotifications
            self.stateTransitionHistory = stateTransitionHistory
            self.extensions = extensions
        }
    }
    
    /// Describes a specific capability, function, or area of expertise the agent can perform or address.
    public struct AgentSkill: Codable, Sendable {
        /// Unique skill identifier within this agent.
        public let id: String
        /// Human-readable skill name.
        public let name: String
        /// Detailed skill description. CommonMark MAY be used.
        public let description: String
        /// Keywords/categories for discoverability.
        public let tags: [String]
        /// Example prompts or use cases demonstrating skill usage.
        public var examples: [String]? = nil
        /// Overrides defaultInputModes for this specific skill. Accepted Media Types.
        public var inputModes: [String]? = nil
        /// Overrides defaultOutputModes for this specific skill. Produced Media Types.
        public var outputModes: [String]? = nil
        public init(id: String, name: String, description: String, tags: [String], examples: [String]? = nil, inputModes: [String]? = nil, outputModes: [String]? = nil) {
            self.id = id
            self.name = name
            self.description = description
            self.tags = tags
            self.examples = examples
            self.inputModes = inputModes
            self.outputModes = outputModes
        }
    }
    public init(name: String, description: String, url: String, version: String, capabilities: AgentCapabilities, defaultInputModes: [String], defaultOutputModes: [String], skills: [AgentSkill], provider: AgentProvider? = nil, iconUrl: String? = nil, documentationUrl: String? = nil, securitySchemes: [String]? = nil, security: JSON? = nil) {
        self.name = name
        self.description = description
        self.url = url
        self.version = version
        self.capabilities = capabilities
        self.defaultInputModes = defaultInputModes
        self.defaultOutputModes = defaultOutputModes
        self.skills = skills
        self.provider = provider
        self.iconUrl = iconUrl
        self.documentationUrl = documentationUrl
        self.securitySchemes = securitySchemes
        self.security = security
    }
}

// MARK: Tasks

/// Task Structure
public struct A2ATask: Codable, Sendable {
    /// Unique identifier for the task
    public let id: String
    /// Server-generated id for contextual alignment across interactions
    public let contextId: String
    /// Current status of the task
    public var status: TaskStatus
    public var history: [A2AMessage]? = nil
    /// Collection of artifacts created by the agent.
    public var artifacts: [Artifact]? = nil
    /// Arbitrary key-value metadata associated with the task.
    public var metadata: JSON? = nil
    public var kind = "task"
    public init(id: String, contextId: String, status: TaskStatus, history: [A2AMessage]? = nil, artifacts: [Artifact]? = nil, metadata: JSON? = nil, kind: String = "task") {
        self.id = id
        self.contextId = contextId
        self.status = status
        self.history = history
        self.artifacts = artifacts
        self.metadata = metadata
        self.kind = kind
    }
}

/// Represents the possible states of a Task.
public enum TaskState: String, Codable, Sendable {
    /// Task received by the server and acknowledged, but processing has not yet actively started.
    case submitted
    /// Task is actively being processed by the agent. Client may expect further updates or a terminal state.
    case working
    /// Agent requires additional input from the client/user to proceed. The task is effectively paused.
    case inputRequired = "input-required"
    /// Task finished successfully. Results are typically available in Task.artifacts or TaskStatus.message.
    case completed
    /// Task was canceled (e.g., by a tasks/cancel request or server-side policy).
    case canceled
    /// Task terminated due to an error during processing. TaskStatus.message may contain error details.
    case failed
    /// Task terminated due to rejection by remote agent. TaskStatus.message may contain error details.
    case rejected
    /// Agent requires additional authentication from the client/user to proceed. The task is effectively paused.
    case authRequired = "auth-required"
    /// The state of the task cannot be determined (e.g., task ID is invalid, unknown, or has expired).
    case unknown
}

/// Represents the current state and associated context (e.g., a message from the agent) of a Task.
/// `TaskState` and accompanying message.
public struct TaskStatus: Codable, Sendable {
    public var state: TaskState
    /** Additional status updates for client */
    public var message: A2AMessage? = nil
    /**
     * ISO 8601 datetime string when the status was recorded.
     * @example "2023-10-27T10:00:00Z"
     * */
    public var timestamp: String? = nil
    public init(state: TaskState, message: A2AMessage? = nil, timestamp: String? = nil) {
        self.state = state
        self.message = message
        self.timestamp = timestamp
    }
}

// Request Structures
public struct MessageSendParams: Codable, Sendable {
    /// The message being sent to the server.
    public let message: A2AMessage
    /// Optional additional message configuration.
    public var configuration: MessageSendConfiguration? = nil
    /// Request-specific metadata.
    public var metadata: JSON? = nil

    public init(message: A2AMessage, configuration: MessageSendConfiguration? = nil, metadata: JSON? = nil) {
        self.message = message
        self.configuration = configuration
        self.metadata = metadata
    }
}

/// Configuration for the send message request.
public struct MessageSendConfiguration: Codable, Sendable {
    /// Accepted output modalities by the client.
    public let acceptedOutputModes: [String]
    /// Number of recent messages to be retrieved.
    public var historyLength: Int? = nil
    /// Where the server should send notifications when disconnected.
    public var pushNotificationConfig: PushNotificationConfig? = nil
    /// If the server should treat the client as a blocking request.
    public var blocking: Bool? = nil

    public init(
        acceptedOutputModes: [String],
        historyLength: Int? = nil,
        pushNotificationConfig: PushNotificationConfig? = nil,
        blocking: Bool? = nil
    ) {
        self.acceptedOutputModes = acceptedOutputModes
        self.historyLength = historyLength
        self.pushNotificationConfig = pushNotificationConfig
        self.blocking = blocking
    }
}

/// Parameters for querying a task, including optional history length
public struct TaskQueryParams: Codable, Sendable {
    /// The ID of the task whose current state is to be retrieved.
    public let taskId: String
    /// If positive, requests the server to include up to N recent messages in Task.history.
    public var historyLength: Int? = nil
    /// Request-specific metadata.
    public var metadata: JSON? = nil
    
    enum CodingKeys: String, CodingKey {
        case taskId = "id"
        case historyLength
        case metadata
    }

    public init(taskId: String, historyLength: Int? = nil, metadata: JSON? = nil) {
        self.taskId = taskId
        self.historyLength = historyLength
        self.metadata = metadata
    }
}

/// A simple object containing just the task ID and optional metadata.
public struct TaskIdParams: Codable, Sendable {
    /// The ID of the task.
    public let taskId: String
    /// Request-specific metadata.
    public var metadata: JSON? = nil
    
    enum CodingKeys: String, CodingKey {
        case taskId = "id"
        case metadata
    }

    public init(taskId: String, metadata: JSON? = nil) {
        self.taskId = taskId
        self.metadata = metadata
    }
}

// MARK: Messages

/// Represents a single communication turn or a piece of contextual information between a client and an agent. Messages are used for instructions, prompts, replies, and status updates.
public struct A2AMessage: Codable, Sendable {
    /// Message sender's role
    public let role: String
    /// Message content
    public let parts: [A2AMessagePart]
    /// Identifier created by the message creator
    public let messageId: String
    /// Extension metadata
    public var metadata: JSON? = nil
    /// The URIs of extensions that are present or contributed to this Message.
    public var extensions: [String]? = nil
    /// List of tasks referenced as context by this message.
    public var referenceTaskIds: [String]? = nil
    /// Identifier of task the message is related to
    public var taskId: String? = nil
    /// The context the message is associated with
    public var contextId: String? = nil
    /// Event type
    public var kind: String = "message"
    public init(role: String, parts: [A2AMessagePart], messageId: String, metadata: JSON? = nil, extensions: [String]? = nil, referenceTaskIds: [String]? = nil, taskId: String? = nil, contextId: String? = nil, kind: String = "message") {
        self.role = role
        self.parts = parts
        self.messageId = messageId
        self.metadata = metadata
        self.extensions = extensions
        self.referenceTaskIds = referenceTaskIds
        self.taskId = taskId
        self.contextId = contextId
        self.kind = kind
    }
}

// Message Part Structure
public enum A2AMessagePart: Sendable, Codable, Equatable {
    case text(text: String)
    case file(data: Data?, url: URL?)
    case data(data: Data)
    
    private enum TextKeys : String, CodingKey { case text }
    private enum FileKeys : String, CodingKey { case data, url }
    private enum DataKeys : String, CodingKey { case data }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(["kind": "text", "text": text])
        case .file(let data, let url):
            var value = ["kind": "file"]
            if let data = data {
                value["file"] = data.base64EncodedString()
            }
            if let url = url {
                value["file"] = url.absoluteString
            }
            try container.encode(value)
        case .data(let data):
            let value: JSON = try .init(["kind": "data", "data": data.base64EncodedString()])
            try container.encode(value)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decoded = try container.decode(JSON.self)
        
        guard case .object(let rawData) = decoded else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid data"
                )
            )
        }
        
        if let value = rawData["kind"] {
            
            guard case .string(let kind) = value else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid data"
                    )
                )
            }
            
            switch kind {
            case "text":
                guard let value = rawData["text"], case .string(let text) = value else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: decoder.codingPath,
                            debugDescription: "Invalid data"
                        )
                    )
                }
                self = .text(text: text)
            case "file":
                guard let value = rawData["file"], case .string(let file) = value else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: decoder.codingPath,
                            debugDescription: "Invalid data"
                        )
                    )
                }
                if let url = URL(string: file) {
                    self = .file(data: nil, url: url)
                } else if let data = Data(base64Encoded: file) {
                    self = .file(data: data, url: nil)
                } else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: decoder.codingPath,
                            debugDescription: "Invalid data"
                        )
                    )
                }
            case "data":
                guard let value = rawData["data"], case .string(let base64Data) = value, let data = Data(base64Encoded: base64Data) else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: decoder.codingPath,
                            debugDescription: "Invalid data"
                        )
                    )
                }
                self = .data(data: data)
            default:
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid data"
                    )
                )
            }
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid data"
                )
            )
        }
    }
}

// MARK: Artifact

/// Represents a tangible output generated by the agent during a task. Artifacts are the results or products of the agent's work.
public struct Artifact: Codable, Sendable {
    /// Unique identifier for the artifact.
    public let artifactId: String
    /// Artifact parts
    public let parts: [A2AMessagePart]
    /// Optional name for the artifact.
    public var name: String? = nil
    /// Optional description for the artifact.
    public var description: String? = nil
    /// Extension metadata.
    public var metadata: JSON? = nil
    /// The URIs of extensions that are present or contributed to this Artifact.
    public var extensions: [String]? = nil
    public init(artifactId: String, parts: [A2AMessagePart], name: String? = nil, description: String? = nil, metadata: JSON? = nil, extensions: [String]? = nil) {
        self.artifactId = artifactId
        self.parts = parts
        self.name = name
        self.description = description
        self.metadata = metadata
        self.extensions = extensions
    }
}

// MARK: Push Notifications

/// Configuration provided by the client to the server for sending asynchronous push notifications about task updates.
public struct PushNotificationConfig: Codable, Sendable {
    /// URL for sending the push notifications.
    public let url: String
    /// Push Notification ID - created by server to support multiple callbacks
    public var id: String? = nil
    /// Token unique to this task/session.
    public var token: String? = nil
    public var authentication: PushNotificationAuthenticationInfo? = nil

    public init(url: String, id: String? = nil, token: String? = nil, authentication: PushNotificationAuthenticationInfo? = nil) {
        self.url = url
        self.id = id
        self.token = token
        self.authentication = authentication
    }
}

/// A generic structure for specifying authentication requirements, typically used within PushNotificationConfig to describe how the A2A Server should authenticate to the client's webhook.
public struct PushNotificationAuthenticationInfo: Codable, Sendable {
    /// Supported authentication schemes - e.g. Basic, Bearer
    public let schemes: [String]
    /// Optional credentials
    public var credentials: String? = nil

    public init(schemes: [String], credentials: String? = nil) {
        self.schemes = schemes
        self.credentials = credentials
    }
}

/// Used as the params object for the tasks/pushNotificationConfig/set method and as the result object for the tasks/pushNotificationConfig/get method.
public struct TaskPushNotificationConfig: Codable, Sendable {
    /// Task id.
    public let taskId: String
    /// Push notification configuration.
    public let pushNotificationConfig: PushNotificationConfig

    public init(taskId: String, pushNotificationConfig: PushNotificationConfig) {
        self.taskId = taskId
        self.pushNotificationConfig = pushNotificationConfig
    }
}

// MARK: Errors

// JSON-RPC Error Structures
public struct JSONRPCError: Codable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public struct JSONRPCErrorResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: Int
    public let error: JSONRPCError

    public init(jsonrpc: String, id: Int, error: JSONRPCError) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.error = error
    }
}

/// JSON-RPC 2.0 request envelope used to carry params and id for RPC calls
public struct JSONRPCRequest<T: Decodable & Sendable>: Decodable, Sendable {
    public let jsonrpc: String
    public let id: Int
    public let params: T

    public init(jsonrpc: String = "2.0", id: Int, params: T) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.params = params
    }
}

public enum ErrorCode: Int {
    // Standard JSON-RPC Errors
    /// Server received JSON that was not well-formed.
    case parseError = -32700
    /// The JSON payload was valid JSON, but not a valid JSON-RPC Request object.
    case invalidRequest = -32600
    /// The requested A2A RPC method (e.g., "tasks/foo") does not exist or is not supported.
    case methodNotFound = -32601
    /// The params provided for the method are invalid (e.g., wrong type, missing required field).
    case invalidParams = -32602
    /// An unexpected error occurred on the server during processing.
    case internalError = -32603
    
    // A2A-Specific Errors
    /// Task not found    The specified task id does not correspond to an existing or active task. It might be invalid, expired, or already completed and purged.
    case taskNotFound = -32001
    /// Task cannot be canceled    An attempt was made to cancel a task that is not in a cancelable state (e.g., it has already reached a terminal state like completed, failed, or canceled).
    case taskNotCandelable = -32002
    /// Push Notification is not supported    Client attempted to use push notification features (e.g., tasks/pushNotificationConfig/set) but the server agent does not support them (i.e., AgentCard.capabilities.pushNotifications is false).
    case pushNotificationsNotSupported = -32003
    /// This operation is not supported    The requested operation or a specific aspect of it (perhaps implied by parameters) is not supported by this server agent implementation. Broader than just method not found.
    case unsupportedOperation = -32004
    /// Incompatible content types    A Media Type provided in the request's message.parts (or implied for an artifact) is not supported by the agent or the specific skill being invoked.
    case contentTypeNotSupported = -32005
    /// Invalid agent response type
    case invalidAgentResponse = -32006
}

// MARK: - A2A Spec RPC Models

/// This is the structure of the JSON object found in the data field of each Server-Sent Event sent by the server for a message/stream request or tasks/resubscribe request.
public struct SendStreamingMessageSuccessResponse<T>: Encodable, Sendable where T : (Encodable & Sendable) {
    /// JSON-RPC version string.
    /// "2.0" (literal)
    public let jsonrpc: String
    /// Matches the id from the originating message/stream or tasks/resubscribe request.
    public let id: Int
    /// The event payload
    /// Either `A2AMessage`
    /// OR `A2ATask`
    /// OR `TaskStatusUpdateEvent`
    /// OR `TaskArtifactUpdateEvent`
    public let result: T

    public init(jsonrpc: String, id: Int, result: T) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
    }
}

/// Carries information about a change in the task's status during streaming. This is one of the possible result types in a SendStreamingMessageSuccessResponse.
public struct TaskStatusUpdateEvent: Codable, Sendable {
    /// Task ID being updated
    public let taskId: String
    /// Context ID the task is associated with
    public let contextId: String
    /// Type discriminator, literal value
    /// Default "status-update"
    public var kind: String = "status-update"
    /// The new TaskStatus object.
    public let status: TaskStatus
    /// If true, indicates this is the terminal status update for the current stream cycle. The server typically closes the SSE connection after this.
    public let final: Bool
    /// Event-specific metadata.
    public var metadata: JSON? = nil

    public init(taskId: String, contextId: String, kind: String = "status-update", status: TaskStatus, final: Bool, metadata: JSON? = nil) {
        self.taskId = taskId
        self.contextId = contextId
        self.kind = kind
        self.status = status
        self.final = final
        self.metadata = metadata
    }
}

/// Carries a new or updated artifact (or a chunk of an artifact) generated by the task during streaming. This is one of the possible result types in a SendTaskStreamingResponse.
public struct TaskArtifactUpdateEvent: Codable, Sendable {
    /// Task ID associated with the generated artifact part
    public let taskId: String
    /// The context the task is associated with
    public let contextId: String
    /// Event type. Type discriminator, literal value
    /// Default "artifact-update"
    public var kind: String = "artifact-update"
    /// The Artifact data. Could be a complete artifact or an incremental chunk.
    public let artifact: Artifact
    /// true means append parts to artifact; false (default) means replace.
    public var append: Bool? = nil
    /// true indicates this is the final update for the artifact.
    public var lastChunk: Bool? = nil
    /// Event-specific metadata.
    public var metadata: JSON? = nil

    public init(taskId: String, contextId: String, kind: String = "artifact-update", artifact: Artifact, append: Bool? = nil, lastChunk: Bool? = nil, metadata: JSON? = nil) {
        self.taskId = taskId
        self.contextId = contextId
        self.kind = kind
        self.artifact = artifact
        self.append = append
        self.lastChunk = lastChunk
        self.metadata = metadata
    }
}

public actor TaskStore {
    
    private var tasks: [String: A2ATask] = [:]
    
    public init() {}
    
    public func addTask(task: A2ATask) {
        tasks[task.id] = task
    }
    
    public func getTask(id: String) -> A2ATask? {
        return tasks[id]
    }
    
    @discardableResult
    public func updateTaskStatus(id: String, status: TaskStatus) -> Bool {
        guard var task = tasks[id] else { return false }
        task.status = status
        tasks[id] = task
        return true
    }
    
    @discardableResult
    public func updateTaskArtifacts(id: String, artifacts: [Artifact]) -> Bool {
        guard var task = tasks[id] else { return false }
        task.artifacts = artifacts
        tasks[id] = task
        return true
    }
}
