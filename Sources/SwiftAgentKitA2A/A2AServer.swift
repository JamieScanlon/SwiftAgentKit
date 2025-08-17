//
//  A2AServer.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import Vapor

// Alias protocol-defined types for convenience
typealias AgentCapabilities = AgentCard.AgentCapabilities
typealias AgentSkill = AgentCard.AgentSkill

extension AgentCard: Content {}

// MARK: - Server Implementation

/// A2A Server (Remote Agent): An agent or agentic system that exposes an A2A-compliant HTTP endpoint, processing tasks and providing responses.
public actor A2AServer {
    
    /**
     * Initializes a new APILayer instance.
     *
     * - Parameter port: The port number that the server will listen on. Defaults to `4245` standing for A2AS(erver).
     */
    public init(port: Int = 4245, adapter: AgentAdapter) {
        self.port = port
        self.adapter = adapter
        // derive AgentCard from adapter metadata
        self.agentCard = AgentCard(
            name: adapter.agentName,
            description: adapter.agentDescription,
            url: "http://localhost:\(port)",
            version: "0.1.3",
            capabilities: adapter.cardCapabilities,
            defaultInputModes: adapter.defaultInputModes,
            defaultOutputModes: adapter.defaultOutputModes,
            skills: adapter.skills,
            securitySchemes: ["bearer"]
        )
        
        self.encoder.dateEncodingStrategy = .iso8601
    }
    
    public func start() async throws {
        
        // Create a new Vapor application using the modern async API
        let env = try Environment.detect()
        let app = try await Application.make(env)
        self.app = app
        
        // Configure the server to listen on the specified port
        app.http.server.configuration.port = port
        app.http.server.configuration.hostname = "0.0.0.0"
        
        // Configure maximum body size (100MB)
        app.routes.defaultMaxBodySize = "100mb"
        
        // Enable TLS.
        //        let resourcesURL = Bundle(for: Self.self).resourceURL?.appending(path: "SwiftAgentKit_SwiftAgentKit.bundle/Contents/Resources/")
        //        app.http.server.configuration.tlsConfiguration = .makeServerConfiguration(
        //            certificateChain: try NIOSSLCertificate.fromPEMFile(resourcesURL!.appending(path: "myCA.pem").path()).map { .certificate($0) },
        //            privateKey: .privateKey(try NIOSSLPrivateKey(file: resourcesURL!.appending(path: "converted.pem").path(), format: .pem))
        //        )
        
        // Register routes
        setupRoutes(app: app)
        
        // Start the server and wait for it to be ready
        try await app.execute()
    }
    
    func stop() {
        app?.shutdown()
        app = nil
    }
    
    // MARK: - Private
    
    /// The port that the API server listens on
    private let port: Int
    
    /// The Vapor application instance
    private var app: Application?
    private let taskStore = TaskStore()
    private let adapter: AgentAdapter  // Changed to let since it's immutable
    /// Agent Card Definition
    private let agentCard: AgentCard
    private let encoder = JSONEncoder()
    
    private func setupRoutes(app: Application) {
        
        // Expose the Agent Card at the standard /.well-known/agent.json path
        app.get(".well-known", "agent.json") { req async -> AgentCard in
            return self.agentCard
        }
        
        // API route group
        let message = app.grouped("message")
        
        // A2A protocol endpoint to send a Message
        message.post("send", use: self.handleMessageSend)
        
        // message/stream
        message.post("stream", use: self.handleMessageStream)
        
        // API route group
        let tasks = app.grouped("tasks")
        
        // A2A protocol endpoint to get task status and results
        tasks.post("get", use: self.handleTaskGet)
        
        // A2A protocol endpoint to cancel a task
        tasks.post("cancel", use: self.handleTaskCancel)
        
        // A2A protocol endpoint to resubscribe to a task (event stream)
        tasks.post("resubscribe", use: self.handleTaskResubscribe)
        
        // Push Notification Config route group
        let pushConfig = tasks.grouped("pushNotificationConfig")
        
        pushConfig.post("set", use: self.handlePushConfigSet)
        
        pushConfig.post("get", use: self.handlePushConfigGet)
        
        // Agent route group
        let agent = app.grouped("agent")
        
        agent.post("authenticatedExtendedCard", use: self.handleAuthenticatedExtendedCard)
    }
    
    private func handleMessageSend(_ req: Request) async throws -> Response {
        guard isAuthorized(req) else {
            return jsonRPCErrorResponse(code: 401, message: "Unauthorized", status: .unauthorized)
        }
        let params = try req.content.decode(MessageSendParams.self)
        
        // Create initial task
        
        let taskId = UUID().uuidString
        let contextId = UUID().uuidString
        
        let task = A2ATask(
            id: taskId,
            contextId: contextId,
            status: TaskStatus(
                state: .submitted,
                timestamp: ISO8601DateFormatter().string(from: .init())
            ),
            history: [params.message]
        )
        
        await taskStore.addTask(task: task)
        
        try await adapter.handleSend(params, task: task, store: taskStore)
        
        let updatedTask = await taskStore.getTask(id: taskId)
        let data = try encoder.encode(updatedTask)
        let response = Response(status: .ok)
        response.body = .init(data: data)
        return response
    }
    
    private func handleMessageStream(_ req: Request) async throws -> Response {
        guard agentCard.capabilities.streaming == true else {
            let httpResponseStatus: HTTPResponseStatus = .notImplemented
            return jsonRPCErrorResponse(code: Int(httpResponseStatus.code), message: "Streaming is not supported for this agent", status: httpResponseStatus)
        }
        guard isAuthorized(req) else {
            let httpResponseStatus: HTTPResponseStatus = .unauthorized
            return jsonRPCErrorResponse(code: Int(httpResponseStatus.code), message: "Unauthorized", status: httpResponseStatus)
        }
        // Decode JSON-RPC request envelope to capture request id and params
        let rpcRequest: JSONRPCRequest<MessageSendParams>
        do {
            rpcRequest = try req.content.decode(JSONRPCRequest<MessageSendParams>.self)
        } catch {
            return jsonRPCErrorResponse(code: ErrorCode.invalidParams.rawValue, message: "Could not decode JSON-RPC request: \(error)", status: .badRequest)
        }
        let params = rpcRequest.params
        let requestId = rpcRequest.id
        let adapter = self.adapter  // Capture adapter before the task
        let res = Response(status:.ok)
        let store = taskStore
        res.headers.replaceOrAdd(name:.contentType, value:"text/event-stream")
        res.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        res.headers.replaceOrAdd(name: .connection, value: "keep-alive")
        res.headers.replaceOrAdd(name: .cacheControl, value: "no-transform")
        res.headers.replaceOrAdd(name: "X-Accel-Buffering", value: "no")
        
        // Update the MessageSendParams metadata to include the requestId
        // This is so the id can be used in the responses
        let updatedParams: MessageSendParams = {
            var returnValue = params
            if var metadataObject = (returnValue.metadata ?? (try! .init([:]))).literalValue as? [String: Any] {
                metadataObject["requestId"] = requestId
                returnValue.metadata = try? .init(metadataObject)
            }
            return returnValue
        }()
        
        // Validate task continuation -
        // if the request's MessageSendParams contains a `taskId` it is assumed that this is an attempt to
        // reconnect with an existing task. In this case we need to validate that the task exists and is still running
        var isExistingTask = false
        if let taskId = updatedParams.message.taskId {
            guard let foundTask = await taskStore.getTask(id: taskId) else {
                return jsonRPCErrorResponse(id: requestId, code: ErrorCode.taskNotFound.rawValue, message: "Task not found", status: .badRequest)
            }
            // cannot be completed, canceled, rejected, or failed
            guard foundTask.status.state != .completed && foundTask.status.state != .failed && foundTask.status.state != .canceled && foundTask.status.state != .rejected else {
                return jsonRPCErrorResponse(id: requestId, code: ErrorCode.invalidRequest.rawValue, message: "A task which has reached a terminal state (completed, canceled, rejected, or failed) can't be restarted", status: .badRequest)
            }
            isExistingTask = true
        }
        
        // Create task
        
        let taskId = isExistingTask ? updatedParams.message.taskId ?? UUID().uuidString : UUID().uuidString
        let contextId = updatedParams.message.contextId ?? UUID().uuidString
        
        let task: A2ATask = await {
            if isExistingTask {
                return await taskStore.getTask(id: taskId)!
            } else {
                let aTask = A2ATask(
                    id: taskId,
                    contextId: contextId,
                    status: TaskStatus(
                        state: .submitted,
                        timestamp: ISO8601DateFormatter().string(from: .init())
                    ),
                    history: [updatedParams.message]
                )
                await taskStore.addTask(task: aTask)
                return aTask
            }
        }()
        
        // TODO: implement resubscribing to an existing task rather than restarting it which is what the current behavior is doing
        
        let bodyStream = AsyncStream<ByteBuffer> { cont in
            Task.detached {
                do {
                    try await adapter.handleStream(updatedParams, task: task, store: store) { ev in
                        if let data = try? self.encoder.encode(ev), let json = String(data: data, encoding:.utf8) {
                            let wrapped = "{\"jsonrpc\":\"2.0\",\"id\":\(requestId),\"result\":\(json)}"
                            var buf = ByteBufferAllocator().buffer(capacity: wrapped.count+8)
                            buf.writeString("data: \(wrapped)\n\n")
                            cont.yield(buf)
                        }
                    }
                } catch {
                    // Ensure the stream finishes even if the adapter throws
                }
                cont.finish()
            }
        }
        res.body = .init(stream: { writer in
            Task.detached {
                for await buffer in bodyStream {
                    _ = writer.write(.buffer(buffer))
                }
                _ = writer.write(.end)
            }
        })
        return res
    }
    
    private func handleTaskGet(_ req: Request) async throws -> Response {
        guard isAuthorized(req) else {
            return jsonRPCErrorResponse(code: 401, message: "Unauthorized", status: .unauthorized)
        }
        let taskRequest = try req.content.decode(TaskQueryParams.self)
        let taskId = taskRequest.taskId
        guard var task = await self.taskStore.getTask(id: taskId) else {
            return jsonRPCErrorResponse(code: ErrorCode.taskNotFound.rawValue, message: "Task not found", status: .notFound)
        }
        
        let historyLength = taskRequest.historyLength ?? -1
        if historyLength <= 0 {
            task.history = nil
        } else {
            let hist = task.history ?? []
            task.history = hist.suffix(historyLength)
        }
        
        let response = Response(status: .ok)
        let data = try! encoder.encode(task)
        response.body = .init(data: data)
        return response
    }
    
    private func handleTaskCancel(_ req: Request) async throws -> Response {
        guard isAuthorized(req) else {
            return jsonRPCErrorResponse(code: 401, message: "Unauthorized", status: .unauthorized)
        }
        let taskRequest = try req.content.decode(TaskIdParams.self)
        let taskId = taskRequest.taskId
        
        guard let task = await self.taskStore.getTask(id: taskId) else {
            return jsonRPCErrorResponse(code: ErrorCode.taskNotFound.rawValue, message: "Task not found", status: .notFound)
        }
        
        if task.status.state != .completed && task.status.state != .failed && task.status.state != .canceled {
            var aStatus = task.status
            aStatus.state = .canceled
            _ = await self.taskStore.updateTaskStatus(id: taskId, status: aStatus)
        }
        
        guard let updatedTask = await self.taskStore.getTask(id: taskId) else {
            return jsonRPCErrorResponse(code: ErrorCode.taskNotFound.rawValue, message: "Task not found after update", status: .notFound)
        }
        
        let response = Response(status: .ok)
        let data = try! encoder.encode(updatedTask)
        response.body = .init(data: data)
        return response
    }
    
    private func handlePushConfigSet(_ req: Request) async throws -> Response {
        let config = try req.content.decode(TaskPushNotificationConfig.self)
        let response = Response(status: .ok)
        response.body = try .init(data: encoder.encode(config))
        return response
    }
    
    private func handlePushConfigGet(_ req: Request) async throws -> Response {
        let taskIdParams = try req.content.decode(TaskIdParams.self)
        let dummy = TaskPushNotificationConfig(
            taskId: taskIdParams.taskId,
            pushNotificationConfig: PushNotificationConfig(
                url: "https://example.com/webhook",
                id: UUID().uuidString,
                token: "example-token",
                authentication: nil
            )
        )
        let response = Response(status: .ok)
        response.body = try .init(data: encoder.encode(dummy))
        return response
    }
    
    private func handleAuthenticatedExtendedCard(_ req: Request) async throws -> Response {
        guard isAuthorized(req) else {
            return jsonRPCErrorResponse(code: 401, message: "Unauthorized", status: .unauthorized)
        }
        let response = Response(status: .ok)
        response.body = try .init(data: encoder.encode(agentCard))
        return response
    }
    
    /// On resubscribe upt to two events are sent immediately:
    ///  - A `TaskArtifactUpdateEvent` to communicate the last artifact. This event is not sent if there are no artifacts.
    ///  - A `TaskStatusUpdateEvent` to communicate the current status of the task
    /// - Parameter req: the `Request`
    /// - Returns: a `Response` object
    private func handleTaskResubscribe(_ req: Request) async throws -> Response {
        // tasks/resubscribe also uses JSON-RPC envelope to echo id
        let rpcRequest = try req.content.decode(JSONRPCRequest<TaskIdParams>.self)
        let taskIdParams = rpcRequest.params
        let requestId = rpcRequest.id
        guard let task = await self.taskStore.getTask(id: taskIdParams.taskId) else {
            return jsonRPCErrorResponse(code: ErrorCode.taskNotFound.rawValue, message: "Task not found", status: .notFound)
        }
        
        let now = ISO8601DateFormatter().string(from: Date())
        let stream = AsyncStream<ByteBuffer> { continuation in
            func send<T: Encodable>(_ obj: T) {
                if let data = try? encoder.encode(obj),
                   let json = String(data: data, encoding: .utf8) {
                    let wrapped = "{\"jsonrpc\":\"2.0\",\"id\":\(requestId),\"result\":\(json)}"
                    var buffer = ByteBufferAllocator().buffer(capacity: wrapped.count + 8)
                    buffer.writeString("data: \(wrapped)\n\n")
                    continuation.yield(buffer)
                }
            }
            
            let isComplete = (task.status.state == .completed || task.status.state == .failed || task.status.state == .canceled)
            
            if let artifact = task.artifacts?.last {
                let ev = TaskArtifactUpdateEvent(
                    taskId: task.id,
                    contextId: task.contextId,
                    kind: "artifact-update",
                    artifact: artifact,
                    append: false,
                    lastChunk: isComplete,
                    metadata: nil
                )
                send(ev)
            }

            let statusEv = TaskStatusUpdateEvent(
                taskId: task.id,
                contextId: task.contextId,
                kind: "status-update",
                status: TaskStatus(state: task.status.state, message: task.status.message, timestamp: now),
                final: isComplete
            )
            send(statusEv)
            
            // TODO: reconnect and stream the task events here
            
            continuation.finish()
        }
        
        let response = Response(status: .ok)
        response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
        response.body = .init(stream: { writer in
            Task.detached {
                for await buffer in stream {
                    _ = writer.write(.buffer(buffer))
                }
                _ = writer.write(.end)
            }
        })
        return response
    }
    
    // MARK: - Basic Authentication Helper
    private var expectedToken: String { "local-dev-token" }
    
    private func isAuthorized(_ req: Request) -> Bool {
        guard let schemes = agentCard.securitySchemes, !schemes.isEmpty else { return true }
        guard let auth = req.headers.bearerAuthorization else { return false }
        return auth.token == expectedToken
    }
}

// MARK: - JSON-RPC Error Response Helper

extension A2AServer {
    /// Helper to create a JSON-RPC 2.0 error response
    fileprivate func jsonRPCErrorResponse(id: Int = 1, code: Int, message: String, status: HTTPResponseStatus) -> Response {
        let error = JSONRPCError(code: code, message: message)
        let errorResp = JSONRPCErrorResponse(jsonrpc: "2.0", id: id, error: error)
        let data = (try? encoder.encode(errorResp)) ?? Data()
        return Response(status: status, body: .init(data: data))
    }
}
