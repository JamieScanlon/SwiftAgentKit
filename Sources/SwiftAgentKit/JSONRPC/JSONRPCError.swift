//
//  JSONRPCError.swift
//  SwiftAgentKit
//

import EasyJSON
import Foundation

public struct JSONRPCError: Codable, Sendable {
    public let code: Int
    public let message: String
    public var data: JSON?

    public init(code: Int, message: String, data: JSON? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public struct JSONRPCErrorResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let error: JSONRPCError

    public init(jsonrpc: String = "2.0", id: JSONRPCID?, error: JSONRPCError) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.error = error
    }
}

public struct JSONRPCRequest<P: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID
    public let method: String
    public let params: P

    public init(jsonrpc: String = "2.0", id: JSONRPCID, method: String, params: P) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCSuccessResponse<R: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID
    public let result: R

    public init(jsonrpc: String = "2.0", id: JSONRPCID, result: R) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
    }
}

public struct JSONRPCNotification<P: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: P

    public init(jsonrpc: String = "2.0", method: String, params: P) {
        self.jsonrpc = jsonrpc
        self.method = method
        self.params = params
    }
}
