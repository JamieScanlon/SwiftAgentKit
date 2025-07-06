//
//  SharedTypes.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 7/6/25.
//

import Foundation

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
    
    public var buffer = Data()
    public func append(_ data: Data) {
        buffer.append(data)
    }
} 