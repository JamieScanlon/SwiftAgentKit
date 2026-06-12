//
//  JSONRPCConnection.swift
//  SwiftAgentKit
//

import Foundation
import Logging

/// Bidirectional JSON-RPC dispatcher.
public actor JSONRPCConnection {
    public typealias MethodHandler = @Sendable (Data) async throws -> Data
    public typealias NotificationHandler = @Sendable (Data) async -> Void

    private let transport: any JSONRPCTransport
    private let logger: Logging.Logger
    private var nextRequestID: Int = 1
    private var pendingContinuations: [String: CheckedContinuation<Data, Error>] = [:]
    private var methodHandlers: [String: MethodHandler] = [:]
    private var notificationHandlers: [String: NotificationHandler] = [:]
    private var readTask: Task<Void, Never>?
    private var isConnected = false
    private var isInitialized = false

    public init(transport: any JSONRPCTransport, logger: Logging.Logger? = nil) {
        self.transport = transport
        self.logger = logger ?? SwiftAgentKitLogging.logger(for: .core("JSONRPCConnection"))
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
            continuation.resume(throwing: JSONRPCConnectionError.disconnected)
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
        guard isConnected else { throw JSONRPCConnectionError.notConnected }
        let id = JSONRPCID.int(nextRequestID)
        nextRequestID += 1
        let requestData = try JSONRPCEncoding.encodeRequest(method, id: id, params: params)
        let responseData = try await sendRequest(requestData, id: idKey(for: id))
        let decoder = JSONDecoder()
        if let errorResponse = try? decoder.decode(JSONRPCErrorResponse.self, from: responseData) {
            throw JSONRPCConnectionError.remoteError(errorResponse.error)
        }
        guard let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let resultObject = object["result"] else {
            throw JSONRPCConnectionError.parseError
        }
        let resultData = try JSONSerialization.data(withJSONObject: resultObject)
        return try decoder.decode(R.self, from: resultData)
    }

    public func notify<P: Encodable & Sendable>(_ method: String, params: P) async throws {
        guard isConnected else { throw JSONRPCConnectionError.notConnected }
        let data = try JSONRPCEncoding.encodeNotification(method, params: params)
        try await sendRaw(data)
    }

    public func sendSuccess<R: Encodable & Sendable>(id: JSONRPCID, result: R) async throws {
        let data = try JSONRPCEncoding.encodeSuccess(id: id, result: result)
        try await sendRaw(data)
    }

    public func sendError(id: JSONRPCID?, code: JSONRPCErrorCode, message: String) async throws {
        try await sendError(id: id, code: code.rawValue, message: message)
    }

    public func sendError(id: JSONRPCID?, code: Int, message: String) async throws {
        let data = try JSONRPCEncoding.encodeError(id: id, code: code, message: message)
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
                "JSON-RPC read loop ended",
                metadata: SwiftAgentKitLogging.metadata(("error", .string(String(describing: error))))
            )
        }
        for (_, continuation) in pendingContinuations {
            continuation.resume(throwing: JSONRPCConnectionError.disconnected)
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
                let message = try JSONRPCParsing.parse(lineData)
                await dispatch(message)
            } catch {
                logger.warning(
                    "Failed to parse JSON-RPC message",
                    metadata: SwiftAgentKitLogging.metadata(("error", .string(String(describing: error))))
                )
            }
        }
    }

    private func dispatch(_ message: JSONRPCInboundMessage) async {
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
                    continuation.resume(throwing: JSONRPCConnectionError.parseError)
                }
            }
        case .error(let id, let error):
            if let id, let continuation = pendingContinuations.removeValue(forKey: idKey(for: id)) {
                continuation.resume(throwing: JSONRPCConnectionError.remoteError(error))
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
        } catch let error as JSONRPCConnectionError {
            switch error {
            case .remoteError(let rpcError):
                try? await sendError(id: id, code: rpcError.code, message: rpcError.message)
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
