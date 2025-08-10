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

    /// Returns the model name for this LLM instance
    func getModelName() -> String
    
    /// Returns the capabilities of this LLM
    func getCapabilities() -> [LLMCapability]
    
    /// Send multiple messages to the LLM and get a response
    /// - Parameters:
    ///   - messages: The messages to send
    ///   - config: Configuration for the request
    /// - Returns: The LLM response
    func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse
    
    /// Stream responses from the LLM with multiple messages
    /// - Parameters:
    ///   - messages: The messages to send
    ///   - config: Configuration for the request
    /// - Returns: An async sequence of streaming results
    func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error>
}

/// Default implementations for the LLMProtocol
public extension LLMProtocol {
    
    /// Send a message to the LLM and get a response
    /// - Parameters:
    ///   - message: The message to send
    ///   - config: Configuration for the request
    /// - Returns: The LLM response
    func send(_ message: Message, config: LLMRequestConfig) async throws -> LLMResponse {
        return try await send([message], config: config)
    }
    
    /// Stream responses from the LLM
    /// - Parameters:
    ///   - message: The message to send
    ///   - config: Configuration for the request
    /// - Returns: An async sequence of streaming results
    func stream(_ message: Message, config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
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
    
    /// A helper method for extracting a `ToolCall` from message content.
    /// This method uses `ToolCall.processModelResponse()` to look for tool calls within a message string.
    /// - Parameters:
    ///   - from: Raw message content from the LLM response.
    ///   - availableTools: An array of available tools. This should be the same list of available tools used in the `LLMRequestConfig` when the originalt message was sent to the LLM
    /// - Returns: An `LLMResponse`
    func llmResponse(from content: String, availableTools: [ToolDefinition]) -> LLMResponse {
        var toolCalls: [ToolCall] = []
        let (processedText, toolCallString) = ToolCall.processModelResponse(content: content, availableTools: availableTools.map({$0.name}))
        
        // Parse any tool calls found in text
        if let toolCallString, let toolCall = ToolCall.parse(toolCallString) {
            toolCalls.append(toolCall)
        }
        
        let response = LLMResponse(content: processedText, toolCalls: toolCalls)
        return response
    }
}

/// An enumeration representing the exact model capability
public enum LLMCapability: String, Codable, Sendable {
    case unknown
    case completion
    case tools
    case insert
    case vision
    case embedding
    case thinking
}

/// Common errors that can occur when interacting with LLMs
///
/// ## Examples
///
/// ```swift
/// // Check if LLM supports a required capability
/// let requiredCapability = LLMCapability.vision
/// if !llm.getCapabilities().contains(requiredCapability) {
///     throw LLMError.unsupportedCapability(requiredCapability)
/// }
/// ```
public enum LLMError: Error, LocalizedError, Sendable {
    case invalidRequest(String)
    case rateLimitExceeded
    case quotaExceeded
    case modelNotFound(String)
    case authenticationFailed
    case networkError(Error)
    case invalidResponse(String)
    case timeout
    case unsupportedCapability(LLMCapability)
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
        case .unsupportedCapability(let capability):
            return "Unsupported capability: \(capability.rawValue)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
} 
