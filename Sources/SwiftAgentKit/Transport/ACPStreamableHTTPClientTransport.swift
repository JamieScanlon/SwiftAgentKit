//
//  ACPStreamableHTTPClientTransport.swift
//  SwiftAgentKit
//

import Foundation
import Logging
import os

/// Streamable HTTP client transport for ACP remote agents (draft RFD HTTP profile).
public final class ACPStreamableHTTPClientTransport: JSONRPCTransport, ACPRemoteTransportContext, @unchecked Sendable {
    private let endpointURL: URL
    private let cookieStore: ACPCookieStore
    private let additionalHeaders: [String: String]
    private let urlSession: URLSession
    private let logger: Logging.Logger
    private let sseParser = SSEParser()
    private let stateLock = OSAllocatedUnfairLock(initialState: TransportState())

    private var inboundContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var connectionSSETask: Task<Void, Never>?
    private var sessionSSETask: Task<Void, Never>?

    private struct TransportState: Sendable {
        var connected = false
        var connectionId: String?
        var sessionId: String?
    }

    public init(
        endpointURL: URL,
        cookieStore: ACPCookieStore = ACPCookieStore(),
        additionalHeaders: [String: String] = [:],
        urlSession: URLSession = .shared,
        logger: Logging.Logger? = nil
    ) {
        self.endpointURL = endpointURL
        self.cookieStore = cookieStore
        self.additionalHeaders = additionalHeaders
        self.urlSession = urlSession
        self.logger = logger ?? SwiftAgentKitLogging.logger(for: .core("ACPStreamableHTTPClientTransport"))
    }

    public func connect() async throws {
        let alreadyConnected = stateLock.withLock { state -> Bool in
            if state.connected { return true }
            state.connected = true
            return false
        }
        guard !alreadyConnected else { return }
    }

    public func disconnect() async {
        stateLock.withLock { $0.connected = false }
        connectionSSETask?.cancel()
        sessionSSETask?.cancel()
        connectionSSETask = nil
        sessionSSETask = nil
        inboundContinuation?.finish()
        inboundContinuation = nil
        await cookieStore.clear()
        stateLock.withLock {
            $0.connectionId = nil
            $0.sessionId = nil
        }
    }

    public func send(_ data: Data) async throws {
        let connected = stateLock.withLock { $0.connected }
        guard connected else { throw ACPRemoteTransportError.notConnected }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = object["method"] as? String else {
            throw JSONRPCConnectionError.invalidRequest
        }

        if method == "initialize" {
            let responseData = try await postInitialize(data)
            inboundContinuation?.yield(wrapAsJSONRPCResponse(responseData))
            if let connectionId = parseConnectionId(from: responseData) {
                stateLock.withLock { $0.connectionId = connectionId }
                startConnectionSSE(connectionId: connectionId)
            }
            return
        }

        _ = try await postAccepted(data)
    }

    public func receive() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            inboundContinuation = continuation
        }
    }

    public func setConnectionId(_ connectionId: String?) async {
        stateLock.withLock { $0.connectionId = connectionId }
        if let connectionId {
            startConnectionSSE(connectionId: connectionId)
        }
    }

    public func setSessionId(_ sessionId: String?) async {
        stateLock.withLock { $0.sessionId = sessionId }
        if let sessionId,
           let connectionId = stateLock.withLock({ $0.connectionId }) {
            startSessionSSE(connectionId: connectionId, sessionId: sessionId)
        }
    }

    public func connectionId() async -> String? {
        stateLock.withLock { $0.connectionId }
    }

    public func sessionId() async -> String? {
        stateLock.withLock { $0.sessionId }
    }

    private func postInitialize(_ body: Data) async throws -> Data {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        await applyHeaders(to: &request)

        let (responseData, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ACPRemoteTransportError.httpError(statusCode: -1, message: "Invalid response")
        }
        await cookieStore.store(from: httpResponse, for: endpointURL)
        guard httpResponse.statusCode == 200 else {
            throw ACPRemoteTransportError.httpError(
                statusCode: httpResponse.statusCode,
                message: String(data: responseData, encoding: .utf8) ?? "initialize failed"
            )
        }
        if let headerConnectionId = httpResponse.value(forHTTPHeaderField: ACPHTTPHeaders.connectionId) {
            stateLock.withLock { $0.connectionId = headerConnectionId }
        }
        return responseData
    }

    private func postAccepted(_ body: Data) async throws -> Data {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        await applyHeaders(to: &request)

        let (responseData, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ACPRemoteTransportError.httpError(statusCode: -1, message: "Invalid response")
        }
        await cookieStore.store(from: httpResponse, for: endpointURL)
        guard httpResponse.statusCode == 202 else {
            throw ACPRemoteTransportError.httpError(
                statusCode: httpResponse.statusCode,
                message: String(data: responseData, encoding: .utf8) ?? "request failed"
            )
        }
        return responseData
    }

    private func applyHeaders(to request: inout URLRequest) async {
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let connectionId = stateLock.withLock({ $0.connectionId }) {
            request.setValue(connectionId, forHTTPHeaderField: ACPHTTPHeaders.connectionId)
        }
        if let sessionId = stateLock.withLock({ $0.sessionId }) {
            request.setValue(sessionId, forHTTPHeaderField: ACPHTTPHeaders.sessionId)
        }
        await cookieStore.apply(to: &request, url: endpointURL)
    }

    private func startConnectionSSE(connectionId: String) {
        connectionSSETask?.cancel()
        connectionSSETask = Task { [weak self] in
            guard let self else { return }
            await self.runSSE(connectionId: connectionId, sessionId: nil)
        }
    }

    private func startSessionSSE(connectionId: String, sessionId: String) {
        sessionSSETask?.cancel()
        sessionSSETask = Task { [weak self] in
            guard let self else { return }
            await self.runSSE(connectionId: connectionId, sessionId: sessionId)
        }
    }

    private func runSSE(connectionId: String, sessionId: String?) async {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(connectionId, forHTTPHeaderField: ACPHTTPHeaders.connectionId)
        if let sessionId {
            request.setValue(sessionId, forHTTPHeaderField: ACPHTTPHeaders.sessionId)
        }
        await applyHeaders(to: &request)

        do {
            let (bytes, response) = try await urlSession.bytes(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                await cookieStore.store(from: httpResponse, for: endpointURL)
            }
            var buffer = Data()
            for try await line in bytes.lines {
                guard let lineData = line.data(using: .utf8) else { continue }
                buffer.append(lineData)
                buffer.append(UInt8(ascii: "\n"))
                let messages = await sseParser.appendChunk(buffer)
                buffer.removeAll(keepingCapacity: true)
                for message in messages {
                    if let jsonData = try? JSONSerialization.data(withJSONObject: message) {
                        inboundContinuation?.yield(jsonData)
                    }
                }
            }
        } catch {
            if stateLock.withLock({ $0.connected }) {
                inboundContinuation?.finish(throwing: error)
            }
        }
    }

    private func parseConnectionId(from responseData: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let connectionId = result["connectionId"] as? String else {
            return nil
        }
        return connectionId
    }

    private func wrapAsJSONRPCResponse(_ responseData: Data) -> Data {
        responseData
    }
}
