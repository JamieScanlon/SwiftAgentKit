//
//  ACPRemoteTransportError.swift
//  SwiftAgentKit
//

import Foundation

public enum ACPRemoteTransportError: Error, LocalizedError, Sendable {
    case invalidURL(String)
    case missingConnectionId
    case missingSessionId
    case unknownConnectionId(String)
    case unknownSessionId(String)
    case httpError(statusCode: Int, message: String)
    case unacceptableAcceptHeader
    case unsupportedMediaType
    case batchRequestsNotSupported
    case http2Required
    case webSocketUpgradeFailed(String)
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid ACP remote URL: \(url)"
        case .missingConnectionId:
            return "Missing Acp-Connection-Id header"
        case .missingSessionId:
            return "Missing Acp-Session-Id header"
        case .unknownConnectionId(let id):
            return "Unknown Acp-Connection-Id: \(id)"
        case .unknownSessionId(let id):
            return "Unknown Acp-Session-Id: \(id)"
        case .httpError(let statusCode, let message):
            return "ACP HTTP error \(statusCode): \(message)"
        case .unacceptableAcceptHeader:
            return "Accept header must include text/event-stream"
        case .unsupportedMediaType:
            return "Content-Type must be application/json"
        case .batchRequestsNotSupported:
            return "Batch JSON-RPC requests are not supported"
        case .http2Required:
            return "Streamable HTTP transport requires HTTP/2"
        case .webSocketUpgradeFailed(let reason):
            return "WebSocket upgrade failed: \(reason)"
        case .notConnected:
            return "ACP remote transport is not connected"
        }
    }
}
