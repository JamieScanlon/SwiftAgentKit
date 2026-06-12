//
//  JSONRPCEncoding.swift
//  SwiftAgentKit
//

import Foundation

public enum JSONRPCEncoding {
    public static func encodeRequest<P: Encodable>(_ method: String, id: JSONRPCID, params: P) throws -> Data {
        let paramsData = try JSONEncoder().encode(params)
        let paramsObject = try JSONSerialization.jsonObject(with: paramsData)
        let wrapper: [String: Any] = [
            "jsonrpc": "2.0",
            "id": idValue(for: id),
            "method": method,
            "params": paramsObject
        ]
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
        let wrapper: [String: Any] = ["jsonrpc": "2.0", "id": idValue(for: id), "result": resultObject]
        return try JSONSerialization.data(withJSONObject: wrapper)
    }

    public static func encodeError(id: JSONRPCID?, code: JSONRPCErrorCode, message: String) throws -> Data {
        try encodeError(id: id, code: code.rawValue, message: message)
    }

    public static func encodeError(id: JSONRPCID?, code: Int, message: String) throws -> Data {
        let response = JSONRPCErrorResponse(
            id: id,
            error: JSONRPCError(code: code, message: message)
        )
        return try JSONEncoder().encode(response)
    }

    private static func idValue(for id: JSONRPCID) -> Any {
        switch id {
        case .int(let value): return value
        case .string(let value): return value
        }
    }
}
