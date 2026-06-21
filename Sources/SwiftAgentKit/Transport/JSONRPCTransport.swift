//
//  JSONRPCTransport.swift
//  SwiftAgentKit
//

import Foundation

public protocol JSONRPCTransport: Sendable {
    func connect() async throws
    func disconnect() async
    func send(_ data: Data) async throws
    func receive() -> AsyncThrowingStream<Data, Error>
}
