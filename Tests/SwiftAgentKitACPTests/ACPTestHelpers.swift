//
//  ACPTestHelpers.swift
//  SwiftAgentKitACPTests
//

import EasyJSON
import Foundation
@testable import SwiftAgentKitACP

/// Thread-safe box for async callback tests.
final class LockBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    var value: T {
        get { withLock { $0 } }
        set { withLock { $0 = newValue } }
    }
    init(_ value: T) { self._value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&_value)
    }
}

enum ACPTestHelpers {
    static func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func roundTripCodable<T: Codable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func tempFileURL(prefix: String, extension ext: String = "json") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).\(ext)")
    }

    static func pairedClientAndAgent(
        adapter: any ACPAgentAdapter = EchoACPAgentAdapter(name: "test-agent"),
        delegate: any ACPClientDelegate = DefaultACPClientDelegate(allowedRoots: [URL(fileURLWithPath: "/")])
    ) -> (ACPClient, ACPAgent, ACPMemoryTransport, ACPMemoryTransport) {
        let (clientTransport, agentTransport) = ACPMemoryTransport.paired()
        let agent = ACPAgent(adapter: adapter, transport: agentTransport)
        let client = ACPClient(name: "test-client", transport: clientTransport, delegate: delegate)
        return (client, agent, clientTransport, agentTransport)
    }

    static func connectedClientAndAgent(
        cwd: String = "/tmp",
        adapter: any ACPAgentAdapter = EchoACPAgentAdapter(name: "test-agent"),
        delegate: any ACPClientDelegate = DefaultACPClientDelegate(allowedRoots: [URL(fileURLWithPath: "/")])
    ) async throws -> (ACPClient, ACPAgent) {
        let (client, agent, _, _) = pairedClientAndAgent(adapter: adapter, delegate: delegate)
        async let agentRun: Void = try await agent.run()
        try await client.connect(cwd: cwd)
        _ = try await agentRun
        return (client, agent)
    }

    static func jsonEqual(_ lhs: JSON?, _ rhs: JSON?) -> Bool {
        jsonEqual(lhs ?? .object([:]), rhs ?? .object([:]))
    }

    static func jsonEqual(_ lhs: JSON, _ rhs: JSON) -> Bool {
        guard let left = try? JSONEncoder().encode(lhs),
              let right = try? JSONEncoder().encode(rhs) else { return false }
        return left == right
    }

    static func connectionErrorsEqual(_ lhs: ACPConnectionError, _ rhs: ACPConnectionError) -> Bool {
        switch (lhs, rhs) {
        case (.notConnected, .notConnected): return true
        case (.parseError, .parseError): return true
        case (.invalidRequest, .invalidRequest): return true
        case (.encodingFailed, .encodingFailed): return true
        case (.disconnected, .disconnected): return true
        case (.methodNotFound(let a), .methodNotFound(let b)): return a == b
        case (.remoteError(let a), .remoteError(let b)): return a.code == b.code && a.message == b.message
        default: return false
        }
    }

    static func clientErrorsEqual(_ lhs: ACPClient.ACPClientError, _ rhs: ACPClient.ACPClientError) -> Bool {
        switch (lhs, rhs) {
        case (.alreadyConnected, .alreadyConnected): return true
        case (.notInitialized, .notInitialized): return true
        case (.noSession, .noSession): return true
        case (.initializationFailed, .initializationFailed): return true
        case (.bootFailed(let a), .bootFailed(let b)): return a == b
        default: return false
        }
    }

    static func agentErrorsEqual(_ lhs: ACPAgent.ACPAgentError, _ rhs: ACPAgent.ACPAgentError) -> Bool {
        switch (lhs, rhs) {
        case (.alreadyRunning, .alreadyRunning): return true
        case (.notRunning, .notRunning): return true
        case (.sessionNotFound(let a), .sessionNotFound(let b)): return a == b
        default: return false
        }
    }
}
