//
//  ACPConnection.swift
//  SwiftAgentKitACP
//

import Foundation
import Logging
import SwiftAgentKit

public enum ACPConnectionError: Error, LocalizedError, Sendable {
    case notConnected
    case parseError
    case invalidRequest
    case methodNotFound(String)
    case remoteError(ACPJSONRPCError)
    case encodingFailed
    case disconnected

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "ACP connection is not connected"
        case .parseError: return "Failed to parse JSON-RPC message"
        case .invalidRequest: return "Invalid JSON-RPC request"
        case .methodNotFound(let method): return "Method not found: \(method)"
        case .remoteError(let error): return "Remote error \(error.code): \(error.message)"
        case .encodingFailed: return "Failed to encode JSON-RPC message"
        case .disconnected: return "ACP connection disconnected"
        }
    }
}

public protocol ACPTransport: Sendable {
    func connect() async throws
    func disconnect() async
    func send(_ data: Data) async throws
    func receive() -> AsyncThrowingStream<Data, Error>
}

/// Bidirectional JSON-RPC dispatcher for ACP.
public actor ACPConnection {
    public typealias MethodHandler = @Sendable (Data) async throws -> Data
    public typealias NotificationHandler = @Sendable (Data) async -> Void

    private let transport: any ACPTransport
    private let logger: Logger
    private var nextRequestID: Int = 1
    private var pendingContinuations: [String: CheckedContinuation<Data, Error>] = [:]
    private var methodHandlers: [String: MethodHandler] = [:]
    private var notificationHandlers: [String: NotificationHandler] = [:]
    private var readTask: Task<Void, Never>?
    private var isConnected = false
    private var isInitialized = false

    public init(transport: any ACPTransport, logger: Logger? = nil) {
        self.transport = transport
        self.logger = logger ?? SwiftAgentKitLogging.logger(for: .acp("ACPConnection"))
    }

    public var initialized: Bool { isInitialized }

    public func markInitialized() {
        isInitialized = true
    }

    public func connect() async throws {
        guard !isConnected else { return }
        try await transport.connect()
        isConnected = true
        readTask = Task {
            await self.readLoop()
        }
    }

    public func disconnect() async {
        isConnected = false
        readTask?.cancel()
        readTask = nil
        for (_, continuation) in pendingContinuations {
            continuation.resume(throwing: ACPConnectionError.disconnected)
        }
        pendingContinuations.removeAll()
        await transport.disconnect()
    }

    public func registerMethod(_ method: String, handler: @escaping MethodHandler) {
        methodHandlers[method] = handler
    }

    public func registerNotification(_ method: String, handler: @escaping NotificationHandler) {
        notificationHandlers[method] = handler
    }

    public func call<P: Encodable & Sendable, R: Decodable & Sendable>(
        _ method: String,
        params: P
    ) async throws -> R {
        guard isConnected else { throw ACPConnectionError.notConnected }
        let id = JSONRPCID.int(nextRequestID)
        nextRequestID += 1
        let requestData = try ACPJSONRPCEncoding.encodeRequest(method, id: id, params: params)
        let responseData = try await sendRequest(requestData, id: idKey(for: id))
        let decoder = JSONDecoder()
        if let errorResponse = try? decoder.decode(ACPJSONRPCErrorResponse.self, from: responseData) {
            throw ACPConnectionError.remoteError(errorResponse.error)
        }
        guard let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let resultObject = object["result"] else {
            throw ACPConnectionError.parseError
        }
        let resultData = try JSONSerialization.data(withJSONObject: resultObject)
        return try decoder.decode(R.self, from: resultData)
    }

    public func notify<P: Encodable & Sendable>(_ method: String, params: P) async throws {
        guard isConnected else { throw ACPConnectionError.notConnected }
        let data = try ACPJSONRPCEncoding.encodeNotification(method, params: params)
        try await sendRaw(data)
    }

    public func sendSuccess<R: Encodable & Sendable>(id: JSONRPCID, result: R) async throws {
        let data = try ACPJSONRPCEncoding.encodeSuccess(id: id, result: result)
        try await sendRaw(data)
    }

    public func sendError(id: JSONRPCID?, code: ACPErrorCode, message: String) async throws {
        let data = try ACPJSONRPCEncoding.encodeError(id: id, code: code, message: message)
        try await sendRaw(data)
    }

    private func sendRequest(_ data: Data, id: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            pendingContinuations[id] = continuation
            Task {
                do {
                    try await self.sendRaw(data)
                } catch {
                    self.pendingContinuations.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func sendRaw(_ data: Data) async throws {
        var payload = data
        if payload.last != UInt8(ascii: "\n") {
            payload.append(UInt8(ascii: "\n"))
        }
        try await transport.send(payload)
    }

    private func readLoop() async {
        let stream = transport.receive()
        do {
            for try await data in stream {
                await handleIncoming(data)
            }
        } catch {
            logger.debug(
                "ACP read loop ended",
                metadata: SwiftAgentKitLogging.metadata(("error", .string(String(describing: error))))
            )
        }
        for (_, continuation) in pendingContinuations {
            continuation.resume(throwing: ACPConnectionError.disconnected)
        }
        pendingContinuations.removeAll()
    }

    private func handleIncoming(_ data: Data) async {
        let lines = String(data: data, encoding: .utf8)?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        for line in lines {
            guard let lineData = line.data(using: .utf8) else { continue }
            do {
                let message = try ACPJSONRPCParsing.parse(lineData)
                await dispatch(message)
            } catch {
                logger.warning(
                    "Failed to parse ACP message",
                    metadata: SwiftAgentKitLogging.metadata(("error", .string(String(describing: error))))
                )
            }
        }
    }

    private func dispatch(_ message: ACPInboundMessage) async {
        switch message {
        case .request(let id, let method, let params):
            await handleRequest(id: id, method: method, params: params)
        case .notification(let method, let params):
            await handleNotification(method: method, params: params)
        case .success(let id, let result):
            if let continuation = pendingContinuations.removeValue(forKey: idKey(for: id)) {
                do {
                    let resultObject = try JSONSerialization.jsonObject(with: result)
                    let wrapper: [String: Any] = ["jsonrpc": "2.0", "id": idValue(for: id), "result": resultObject]
                    let responseData = try JSONSerialization.data(withJSONObject: wrapper)
                    continuation.resume(returning: responseData)
                } catch {
                    continuation.resume(throwing: ACPConnectionError.parseError)
                }
            }
        case .error(let id, let error):
            if let id, let continuation = pendingContinuations.removeValue(forKey: idKey(for: id)) {
                continuation.resume(throwing: ACPConnectionError.remoteError(error))
            }
        }
    }

    private func handleRequest(id: JSONRPCID, method: String, params: Data) async {
        guard let handler = methodHandlers[method] else {
            try? await sendError(id: id, code: .methodNotFound, message: "Method not found: \(method)")
            return
        }
        do {
            let resultData = try await handler(params)
            let resultObject = try JSONSerialization.jsonObject(with: resultData)
            let wrapper: [String: Any] = ["jsonrpc": "2.0", "id": idValue(for: id), "result": resultObject]
            let responseData = try JSONSerialization.data(withJSONObject: wrapper)
            try await sendRaw(responseData)
        } catch let error as ACPConnectionError {
            switch error {
            case .remoteError(let rpcError):
                try? await sendError(id: id, code: ACPErrorCode(rawValue: rpcError.code) ?? .internalError, message: rpcError.message)
            default:
                try? await sendError(id: id, code: .internalError, message: error.localizedDescription)
            }
        } catch {
            try? await sendError(id: id, code: .internalError, message: error.localizedDescription)
        }
    }

    private func handleNotification(method: String, params: Data) async {
        guard let handler = notificationHandlers[method] else { return }
        await handler(params)
    }

    private func idKey(for id: JSONRPCID) -> String {
        switch id {
        case .int(let value): return "i:\(value)"
        case .string(let value): return "s:\(value)"
        }
    }

    private func idValue(for id: JSONRPCID) -> Any {
        switch id {
        case .int(let value): return value
        case .string(let value): return value
        }
    }
}

/// In-memory transport for tests — paired read/write ends.
public final class ACPMemoryTransport: ACPTransport, @unchecked Sendable {
    private let outbound: AsyncStream<Data>.Continuation
    private let inbound: AsyncThrowingStream<Data, Error>
    private var peer: ACPMemoryTransport?
    private var connected = false

    public init() {
        var inboundContinuation: AsyncThrowingStream<Data, Error>.Continuation!
        inbound = AsyncThrowingStream { inboundContinuation = $0 }
        var outboundContinuation: AsyncStream<Data>.Continuation!
        _ = AsyncStream<Data> { outboundContinuation = $0 }
        outbound = outboundContinuation
        self.inboundContinuation = inboundContinuation
    }

    private var inboundContinuation: AsyncThrowingStream<Data, Error>.Continuation

    public static func paired() -> (ACPMemoryTransport, ACPMemoryTransport) {
        let a = ACPMemoryTransport()
        let b = ACPMemoryTransport()
        a.peer = b
        b.peer = a
        return (a, b)
    }

    public func connect() async throws {
        connected = true
    }

    public func disconnect() async {
        connected = false
        inboundContinuation.finish()
    }

    public func send(_ data: Data) async throws {
        guard connected, let peer else { throw ACPConnectionError.notConnected }
        peer.inboundContinuation.yield(data)
    }

    public func receive() -> AsyncThrowingStream<Data, Error> {
        inbound
    }
}
