import Foundation
import Logging
import EasyJSON

// LLMResponse is now defined in LLMResponse.swift

/// Configuration options for LLM requests
public struct LLMRequestConfig: Sendable {
    /// Maximum number of tokens to generate
    public let maxTokens: Int?
    /// Temperature for response randomness (0.0 to 2.0)
    public let temperature: Double?
    /// Top-p sampling parameter
    public let topP: Double?
    /// Whether to enable streaming responses
    public let stream: Bool
    /// Available tools that can be used during processing
    public let availableTools: [ToolDefinition]
    /// Additional model-specific parameters
    public let additionalParameters: JSON?
    
    public init(
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        stream: Bool = false,
        availableTools: [ToolDefinition] = [],
        additionalParameters: JSON? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stream = stream
        self.availableTools = availableTools
        self.additionalParameters = additionalParameters
    }
}

/// A common protocol for interacting with LLMs
public protocol LLMProtocol: Sendable {
    /// The model identifier for this LLM instance
    var model: String { get }
    
    /// The logger for this LLM instance
    var logger: Logger { get }
    
    /// Send a message to the LLM and get a response
    /// - Parameters:
    ///   - message: The message to send
    ///   - config: Configuration for the request
    /// - Returns: The LLM response
    func send(_ message: Message, config: LLMRequestConfig) async throws -> LLMResponse
    
    /// Send multiple messages to the LLM and get a response
    /// - Parameters:
    ///   - messages: The messages to send
    ///   - config: Configuration for the request
    /// - Returns: The LLM response
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse
    
    /// Stream responses from the LLM
    /// - Parameters:
    ///   - message: The message to send
    ///   - config: Configuration for the request
    /// - Returns: An async sequence of streaming responses
    func stream(_ message: Message, config: LLMRequestConfig) -> AsyncThrowingStream<LLMResponse, Error>
    
    /// Stream responses from the LLM with multiple messages
    /// - Parameters:
    ///   - messages: The messages to send
    ///   - config: Configuration for the request
    /// - Returns: An async sequence of streaming responses
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<LLMResponse, Error>
}

/// Default implementations for the LLMProtocol
public extension LLMProtocol {
    
    /// Default implementation for sending a single message
    func send(_ message: Message, config: LLMRequestConfig) async throws -> LLMResponse {
        return try await send([message], config: config)
    }
    
    /// Default implementation for streaming a single message
    func stream(_ message: Message, config: LLMRequestConfig) -> AsyncThrowingStream<LLMResponse, Error> {
        return stream([message], config: config)
    }
    
    /// Helper method to create a streaming config from a regular config
    func createStreamingConfig(from config: LLMRequestConfig) -> LLMRequestConfig {
        return LLMRequestConfig(
            maxTokens: config.maxTokens,
            temperature: config.temperature,
            topP: config.topP,
            stream: true,
            availableTools: config.availableTools,
            additionalParameters: config.additionalParameters
        )
    }
}

/// Common errors that can occur when interacting with LLMs
public enum LLMError: Error, LocalizedError, Sendable {
    case invalidRequest(String)
    case rateLimitExceeded
    case quotaExceeded
    case modelNotFound(String)
    case authenticationFailed
    case networkError(Error)
    case invalidResponse(String)
    case timeout
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .quotaExceeded:
            return "Quota exceeded"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        case .authenticationFailed:
            return "Authentication failed"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .timeout:
            return "Request timeout"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
} 