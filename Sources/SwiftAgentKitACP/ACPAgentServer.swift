//
//  ACPAgentServer.swift
//  SwiftAgentKitACP
//

import Foundation
import Logging
import SwiftAgentKit
import Vapor

/// Hosts an ACP agent over HTTP/WebSocket per the draft Streamable HTTP & WebSocket transport RFD.
public actor ACPAgentServer {
    public struct Configuration: Sendable {
        public var host: String
        public var port: Int
        public var path: String

        public init(host: String = "0.0.0.0", port: Int = 8080, path: String = "acp") {
            self.host = host
            self.port = port
            self.path = path
        }
    }

    public enum ServerError: Error, LocalizedError, Sendable {
        case alreadyRunning
        case notRunning

        public var errorDescription: String? {
            switch self {
            case .alreadyRunning: return "ACP agent server is already running"
            case .notRunning: return "ACP agent server is not running"
            }
        }
    }

    private let adapterFactory: @Sendable () -> any ACPAgentAdapter
    private let configuration: Configuration
    private let logger: Logger
    private var app: Application?
    private var connectionTasks: [String: Task<Void, Never>] = [:]
    private var streamableServer: ACPStreamableHTTPServer?

    public init(
        adapter: any ACPAgentAdapter,
        configuration: Configuration = Configuration(),
        logger: Logger? = nil
    ) {
        self.adapterFactory = { adapter }
        self.configuration = configuration
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .acp("ACPAgentServer"),
            metadata: SwiftAgentKitLogging.metadata(
                ("port", .stringConvertible(configuration.port)),
                ("path", .string(configuration.path))
            )
        )
    }

    public init(
        adapterFactory: @escaping @Sendable () -> any ACPAgentAdapter,
        configuration: Configuration = Configuration(),
        logger: Logger? = nil
    ) {
        self.adapterFactory = adapterFactory
        self.configuration = configuration
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .acp("ACPAgentServer"),
            metadata: SwiftAgentKitLogging.metadata(
                ("port", .stringConvertible(configuration.port)),
                ("path", .string(configuration.path))
            )
        )
    }

    public func start() async throws {
        guard app == nil else { throw ServerError.alreadyRunning }

        let application = try await Application.make(.testing)
        application.http.server.configuration.port = configuration.port
        application.http.server.configuration.hostname = configuration.host
        application.routes.defaultMaxBodySize = "10mb"

        let adapterFactory = self.adapterFactory
        let path = configuration.path
        let logger = self.logger

        application.webSocket(.init(stringLiteral: path)) { _, socket in
            let connectionId = UUID().uuidString

            let transport = ACPWebSocketServerTransport(socket: socket, connectionId: connectionId)
            let agent = ACPAgent(adapter: adapterFactory(), transport: transport, logger: logger)
            let task = Task {
                do {
                    try await agent.run()
                } catch {
                    logger.error(
                        "ACP agent connection ended with error",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("connectionId", .string(connectionId)),
                            ("error", .string(String(describing: error)))
                        )
                    )
                }
                await agent.stop()
            }
            Task { await self.storeConnectionTask(connectionId: connectionId, task: task) }
            socket.onClose.whenComplete { _ in
                Task { await self.removeConnectionTask(connectionId: connectionId) }
            }
        }

        let httpServer = ACPStreamableHTTPServer(adapterFactory: adapterFactory, logger: logger)
        await httpServer.register(on: application, path: path)
        streamableServer = httpServer

        app = application
        try await application.server.start(address: .hostname(configuration.host, port: configuration.port))
        logger.info("ACP agent server started")
    }

    public func run() async throws {
        try await start()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            app?.running?.onStop.whenComplete { result in
                continuation.resume(with: result.map { _ in () })
            }
        }
    }

    public func stop() {
        guard let app else { return }
        for (_, task) in connectionTasks {
            task.cancel()
        }
        connectionTasks.removeAll()
        app.server.shutdown()
        app.shutdown()
        self.app = nil
        logger.info("ACP agent server stopped")
    }

    private func storeConnectionTask(connectionId: String, task: Task<Void, Never>) {
        connectionTasks[connectionId] = task
    }

    private func removeConnectionTask(connectionId: String) {
        connectionTasks.removeValue(forKey: connectionId)?.cancel()
    }
}
