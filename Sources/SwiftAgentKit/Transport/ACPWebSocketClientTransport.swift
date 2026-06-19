//
//  ACPWebSocketClientTransport.swift
//  SwiftAgentKit
//

import Foundation
import Logging
import os

/// WebSocket client transport for ACP remote agents (draft RFD WebSocket profile).
public final class ACPWebSocketClientTransport: JSONRPCTransport, ACPFramedJSONRPCTransport, ACPRemoteTransportContext, @unchecked Sendable {
    public let jsonRPCFraming: JSONRPCFraming = .rawFrame

    private let endpointURL: URL
    private let cookieStore: ACPCookieStore
    private let additionalHeaders: [String: String]
    private let logger: Logging.Logger
    private let stateLock = OSAllocatedUnfairLock(initialState: TransportState())

    private var urlSession: URLSession?
    private var sessionDelegate: WebSocketSessionDelegate?
    private var webSocketTask: URLSessionWebSocketTask?
    private var inboundContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var receiveTask: Task<Void, Never>?

    private struct TransportState: Sendable {
        var connected = false
        var connectionId: String?
        var sessionId: String?
    }

    public init(
        endpointURL: URL,
        cookieStore: ACPCookieStore = ACPCookieStore(),
        additionalHeaders: [String: String] = [:],
        logger: Logging.Logger? = nil
    ) {
        self.endpointURL = endpointURL
        self.cookieStore = cookieStore
        self.additionalHeaders = additionalHeaders
        self.logger = logger ?? SwiftAgentKitLogging.logger(for: .core("ACPWebSocketClientTransport"))
    }

    public func connect() async throws {
        let alreadyConnected = stateLock.withLock { state -> Bool in
            if state.connected { return true }
            state.connected = true
            return false
        }
        guard !alreadyConnected else { return }

        var request = URLRequest(url: endpointURL)
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        await cookieStore.apply(to: &request, url: endpointURL)

        let delegate = WebSocketSessionDelegate(cookieStore: cookieStore, endpointURL: endpointURL)
        sessionDelegate = delegate
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        urlSession = session
        webSocketTask = task
        task.resume()
        try await Task.sleep(nanoseconds: 100_000_000)
        startReceiveLoop(task: task)
    }

    public func disconnect() async {
        stateLock.withLock { $0.connected = false }
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        sessionDelegate = nil
        inboundContinuation?.finish()
        inboundContinuation = nil
        await cookieStore.clear()
        stateLock.withLock {
            $0.connectionId = nil
            $0.sessionId = nil
        }
    }

    public func send(_ data: Data) async throws {
        let isConnected = stateLock.withLock { $0.connected }
        guard isConnected, let task = webSocketTask else {
            throw ACPRemoteTransportError.notConnected
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        try await task.send(.string(text.trimmingCharacters(in: .newlines)))
    }

    public func receive() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            inboundContinuation = continuation
        }
    }

    public func setConnectionId(_ connectionId: String?) async {
        stateLock.withLock { $0.connectionId = connectionId }
    }

    public func setSessionId(_ sessionId: String?) async {
        stateLock.withLock { $0.sessionId = sessionId }
    }

    public func connectionId() async -> String? {
        stateLock.withLock { $0.connectionId }
    }

    public func sessionId() async -> String? {
        stateLock.withLock { $0.sessionId }
    }

    private func startReceiveLoop(task: URLSessionWebSocketTask) {
        receiveTask = Task {
            while !Task.isCancelled {
                let isConnected = stateLock.withLock { $0.connected }
                guard isConnected else { break }
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text):
                        if let data = text.data(using: .utf8) {
                            inboundContinuation?.yield(data)
                        }
                    case .data:
                        continue
                    @unknown default:
                        continue
                    }
                } catch {
                    if stateLock.withLock({ $0.connected }) {
                        inboundContinuation?.finish(throwing: error)
                    }
                    break
                }
            }
        }
    }
}

private final class WebSocketSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let cookieStore: ACPCookieStore
    private let endpointURL: URL

    init(cookieStore: ACPCookieStore, endpointURL: URL) {
        self.cookieStore = cookieStore
        self.endpointURL = endpointURL
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        Task { await cookieStore.store(from: response, for: endpointURL) }
        completionHandler(request)
    }
}
