//
//  JSONRPCParsing.swift
//  SwiftAgentKit
//

import Foundation

public enum JSONRPCInboundMessage: Sendable {
    case request(id: JSONRPCID, method: String, params: Data)
    case notification(method: String, params: Data)
    case success(id: JSONRPCID, result: Data)
    case error(id: JSONRPCID?, error: JSONRPCError)
}

public enum JSONRPCParsing {
    public static func parse(_ data: Data) throws -> JSONRPCInboundMessage {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JSONRPCConnectionError.parseError
        }
        guard let jsonrpc = object["jsonrpc"] as? String, jsonrpc == "2.0" else {
            throw JSONRPCConnectionError.invalidRequest
        }

        if let errorDict = object["error"] as? [String: Any],
           let code = errorDict["code"] as? Int,
           let message = errorDict["message"] as? String {
            let id = parseID(object["id"])
            let error = JSONRPCError(code: code, message: message)
            return .error(id: id, error: error)
        }

        if let result = object["result"] {
            guard let id = parseID(object["id"]) else {
                throw JSONRPCConnectionError.invalidRequest
            }
            let resultData = try JSONSerialization.data(withJSONObject: result)
            return .success(id: id, result: resultData)
        }

        guard let method = object["method"] as? String else {
            throw JSONRPCConnectionError.invalidRequest
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
