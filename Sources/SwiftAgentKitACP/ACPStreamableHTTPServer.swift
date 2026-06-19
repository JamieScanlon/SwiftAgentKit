//
//  ACPStreamableHTTPServer.swift
//  SwiftAgentKitACP
//

import Foundation
import Logging
import SwiftAgentKit
import Vapor

actor ACPStreamableHTTPServer {
    private struct Connection {
        let id: String
        let bridge: ACPHTTPBridgeTransport
        let agent: ACPAgent
        let agentTask: Task<Void, Never>
        var connectionContinuations: [UUID: AsyncStream<String>.Continuation] = [:]
        var sessionContinuations: [String: [UUID: AsyncStream<String>.Continuation]] = [:]
        var initializeContinuation: CheckedContinuation<Data, Error>?
    }

    private var connections: [String: Connection] = [:]
    private let adapterFactory: @Sendable () -> any ACPAgentAdapter
    private let logger: Logger

    init(adapterFactory: @escaping @Sendable () -> any ACPAgentAdapter, logger: Logger) {
        self.adapterFactory = adapterFactory
        self.logger = logger
    }

    func register(on application: Application, path: String) {
        application.post(.init(stringLiteral: path)) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.internalServerError) }
            return try await self.handlePOST(req)
        }
        application.get(.init(stringLiteral: path)) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.internalServerError) }
            return try await self.handleGET(req)
        }
        application.on(.DELETE, .init(stringLiteral: path), body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.internalServerError) }
            return try await self.handleDELETE(req)
        }
    }

    private func handlePOST(_ req: Request) async throws -> Response {
        guard req.headers.contentType?.description.contains("application/json") == true else {
            throw Abort(.unsupportedMediaType)
        }
        guard let buffer = req.body.data, let body = buffer.getData(at: 0, length: buffer.readableBytes) else {
            throw Abort(.badRequest)
        }

        let method = extractMethod(from: body)
        let connectionHeader = req.headers.first(name: ACPHTTPHeaders.connectionId)

        if method == "initialize", connectionHeader == nil {
            let connectionId = UUID().uuidString
            let bridge = ACPHTTPBridgeTransport { [weak self] data in
                guard let self else { return }
                await self.routeOutbound(connectionId: connectionId, data: data)
            }
            let agent = ACPAgent(adapter: adapterFactory(), transport: bridge, logger: logger)
            let task = Task {
                do { try await agent.run() } catch {}
                await agent.stop()
            }

            let responseBody = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connections[connectionId] = Connection(
                    id: connectionId,
                    bridge: bridge,
                    agent: agent,
                    agentTask: task,
                    initializeContinuation: continuation
                )
                bridge.ingest(body)
            }

            var response = Response(status: .ok)
            response.body = .init(data: responseBody)
            response.headers.replaceOrAdd(name: HTTPHeaders.Name(ACPHTTPHeaders.connectionId), value: connectionId)
            return response
        }

        guard let connectionId = connectionHeader,
              var connection = connections[connectionId] else {
            throw Abort(.notFound)
        }

        if requiresSessionHeader(method), req.headers.first(name: ACPHTTPHeaders.sessionId) == nil {
            throw Abort(.badRequest, reason: "Missing Acp-Session-Id")
        }

        connection.bridge.ingest(body)
        connections[connectionId] = connection
        return Response(status: .accepted)
    }

    private func handleGET(_ req: Request) async throws -> Response {
        let accept = req.headers.accept.description
        guard accept.contains("text/event-stream") else {
            throw Abort(.notAcceptable)
        }
        guard let connectionId = req.headers.first(name: ACPHTTPHeaders.connectionId) else {
            throw Abort(.badRequest, reason: "Missing Acp-Connection-Id")
        }
        guard connections[connectionId] != nil else {
            throw Abort(.notFound)
        }

        let sessionId = req.headers.first(name: ACPHTTPHeaders.sessionId)
        let stream = AsyncStream<String> { continuation in
            Task { await self.registerSSE(connectionId: connectionId, sessionId: sessionId, continuation: continuation) }
        }

        let response = Response(status: .ok, body: .init(asyncStream: { writer in
            for await chunk in stream {
                try await writer.write(.buffer(.init(string: "data: \(chunk)\n\n")))
            }
        }))
        response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
        return response
    }

    private func handleDELETE(_ req: Request) async throws -> Response {
        guard let connectionId = req.headers.first(name: ACPHTTPHeaders.connectionId) else {
            throw Abort(.badRequest, reason: "Missing Acp-Connection-Id")
        }
        await removeConnection(connectionId: connectionId)
        return Response(status: .accepted)
    }

    private func registerSSE(
        connectionId: String,
        sessionId: String?,
        continuation: AsyncStream<String>.Continuation
    ) {
        guard var connection = connections[connectionId] else {
            continuation.finish()
            return
        }
        let token = UUID()
        if let sessionId {
            var sessionMap = connection.sessionContinuations[sessionId] ?? [:]
            sessionMap[token] = continuation
            connection.sessionContinuations[sessionId] = sessionMap
        } else {
            connection.connectionContinuations[token] = continuation
        }
        connections[connectionId] = connection
    }

    private func routeOutbound(connectionId: String, data: Data) {
        guard var connection = connections[connectionId] else { return }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""

        if let initContinuation = connection.initializeContinuation,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["result"] != nil {
            connection.initializeContinuation = nil
            connections[connectionId] = connection
            initContinuation.resume(returning: data)
            return
        }

        let sessionId = extractSessionId(from: data)
        if let sessionId, let sessionMap = connection.sessionContinuations[sessionId] {
            for (_, continuation) in sessionMap {
                continuation.yield(text)
            }
        } else {
            for (_, continuation) in connection.connectionContinuations {
                continuation.yield(text)
            }
        }
        connections[connectionId] = connection
    }

    private func removeConnection(connectionId: String) async {
        guard let connection = connections.removeValue(forKey: connectionId) else { return }
        connection.agentTask.cancel()
        await connection.agent.stop()
        connection.initializeContinuation?.resume(throwing: Abort(.gone))
        for (_, continuation) in connection.connectionContinuations {
            continuation.finish()
        }
        for (_, map) in connection.sessionContinuations {
            for (_, continuation) in map {
                continuation.finish()
            }
        }
    }

    private func extractMethod(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["method"] as? String
    }

    private func extractSessionId(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let params = object["params"] as? [String: Any], let sessionId = params["sessionId"] as? String {
            return sessionId
        }
        return nil
    }

    private func requiresSessionHeader(_ method: String?) -> Bool {
        guard let method else { return false }
        return method.hasPrefix("session/") && method != "session/new" && method != "session/list"
    }
}
