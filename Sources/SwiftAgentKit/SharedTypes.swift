//
//  SharedTypes.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 7/6/25.
//

import Foundation
import Logging

// MARK: - HTTP Method

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - API Error

public enum APIError: Error {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case invalidJSON
    case decodingFailed(Error)
    case serverError(statusCode: Int, message: String?)
    case unknown
}

// MARK: - Streaming Data Buffer

public actor StreamingDataBuffer {
    private static let logger = SwiftAgentKitLogging.logger(
        for: .core("StreamingDataBuffer")
    )
    
    public var buffer = Data()
    public func append(_ data: Data) {
        buffer.append(data)
        Self.logger.debug(
            "Appended data chunk to streaming buffer",
            metadata: [
                "appendedBytes": .stringConvertible(data.count),
                "totalBytes": .stringConvertible(buffer.count)
            ]
        )
    }
} 