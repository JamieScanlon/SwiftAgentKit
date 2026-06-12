//
//  ACPJSONRPC.swift
//  SwiftAgentKitACP
//

import Foundation
import EasyJSON

// MARK: - JSON-RPC envelopes

public struct ACPJSONRPCError: Codable, Sendable {
    public let code: Int
    public let message: String
    public var data: JSON?

    public init(code: Int, message: String, data: JSON? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public struct ACPJSONRPCErrorResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let error: ACPJSONRPCError

    public init(jsonrpc: String = "2.0", id: JSONRPCID?, error: ACPJSONRPCError) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.error = error
    }
}

public struct ACPJSONRPCRequest<P: Codable & Sendable>: Codable, Sendable {
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

public struct ACPJSONRPCSuccessResponse<R: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID
    public let result: R

    public init(jsonrpc: String = "2.0", id: JSONRPCID, result: R) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
    }
}

public struct ACPJSONRPCNotification<P: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: P

    public init(jsonrpc: String = "2.0", method: String, params: P) {
        self.jsonrpc = jsonrpc
        self.method = method
        self.params = params
    }
}

/// JSON-RPC request id — integer or string per JSON-RPC 2.0.
public enum JSONRPCID: Codable, Sendable, Hashable {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSON-RPC id")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

public enum ACPErrorCode: Int, Sendable {
    case parseError = -32700
    case invalidRequest = -32600
    case methodNotFound = -32601
    case invalidParams = -32602
    case internalError = -32603
    case authRequired = -32001
    case sessionNotFound = -32002
}

public enum ACPJSONRPCEncoding {
    public static func encodeRequest<P: Encodable>(_ method: String, id: JSONRPCID, params: P) throws -> Data {
        let paramsData = try JSONEncoder().encode(params)
        let paramsObject = try JSONSerialization.jsonObject(with: paramsData)
        let idValue: Any
        switch id {
        case .int(let value): idValue = value
        case .string(let value): idValue = value
        }
        let wrapper: [String: Any] = ["jsonrpc": "2.0", "id": idValue, "method": method, "params": paramsObject]
        return try JSONSerialization.data(withJSONObject: wrapper)
    }

    public static func encodeNotification<P: Encodable>(_ method: String, params: P) throws -> Data {
        let paramsData = try JSONEncoder().encode(params)
        let paramsObject = try JSONSerialization.jsonObject(with: paramsData)
        let wrapper: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": paramsObject]
        return try JSONSerialization.data(withJSONObject: wrapper)
    }

    public static func encodeSuccess<R: Encodable>(id: JSONRPCID, result: R) throws -> Data {
        let resultData = try JSONEncoder().encode(result)
        let resultObject = try JSONSerialization.jsonObject(with: resultData)
        let idValue: Any
        switch id {
        case .int(let value): idValue = value
        case .string(let value): idValue = value
        }
        let wrapper: [String: Any] = ["jsonrpc": "2.0", "id": idValue, "result": resultObject]
        return try JSONSerialization.data(withJSONObject: wrapper)
    }

    public static func encodeError(id: JSONRPCID?, code: ACPErrorCode, message: String) throws -> Data {
        let response = ACPJSONRPCErrorResponse(
            id: id,
            error: ACPJSONRPCError(code: code.rawValue, message: message)
        )
        let encoder = JSONEncoder()
        return try encoder.encode(response)
    }
}

/// Parsed inbound JSON-RPC message (request, notification, or response).
public enum ACPInboundMessage: Sendable {
    case request(id: JSONRPCID, method: String, params: Data)
    case notification(method: String, params: Data)
    case success(id: JSONRPCID, result: Data)
    case error(id: JSONRPCID?, error: ACPJSONRPCError)
}

public enum ACPJSONRPCParsing {
    public static func parse(_ data: Data) throws -> ACPInboundMessage {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ACPConnectionError.parseError
        }
        guard let jsonrpc = object["jsonrpc"] as? String, jsonrpc == "2.0" else {
            throw ACPConnectionError.invalidRequest
        }

        if let errorDict = object["error"] as? [String: Any],
           let code = errorDict["code"] as? Int,
           let message = errorDict["message"] as? String {
            let id = parseID(object["id"])
            let error = ACPJSONRPCError(code: code, message: message)
            return .error(id: id, error: error)
        }

        if let result = object["result"] {
            guard let id = parseID(object["id"]) else {
                throw ACPConnectionError.invalidRequest
            }
            let resultData = try JSONSerialization.data(withJSONObject: result)
            return .success(id: id, result: resultData)
        }

        guard let method = object["method"] as? String else {
            throw ACPConnectionError.invalidRequest
        }

        let paramsData: Data
        if let params = object["params"] {
            paramsData = try JSONSerialization.data(withJSONObject: params)
        } else {
            paramsData = Data("{}".utf8)
        }

        if let id = parseID(object["id"]) {
            return .request(id: id, method: method, params: paramsData)
        }
        return .notification(method: method, params: paramsData)
    }

    private static func parseID(_ value: Any?) -> JSONRPCID? {
        guard let value else { return nil }
        if let intValue = value as? Int { return .int(intValue) }
        if let stringValue = value as? String { return .string(stringValue) }
        return nil
    }
}
