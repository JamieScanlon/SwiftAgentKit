import Foundation
import EasyJSON

/// Represents a comprehensive response from an LLM
public struct LLMResponse: Sendable {
    /// The content of the response (text content)
    public let content: String
    
    /// Tool calls that the LLM wants to perform
    public let toolCalls: [ToolCall]
    
    /// Metadata about the response (tokens used, model info, etc.)
    public let metadata: LLMMetadata?
    
    /// Whether this response is complete or a streaming chunk
    public let isComplete: Bool
    
    public init(
        content: String,
        toolCalls: [ToolCall] = [],
        metadata: LLMMetadata? = nil,
        isComplete: Bool = true
    ) {
        self.content = content
        self.toolCalls = toolCalls
        self.metadata = metadata
        self.isComplete = isComplete
    }
}

/// Metadata about an LLM response
public struct LLMMetadata: Sendable {
    /// Number of tokens used in the prompt
    public let promptTokens: Int?
    
    /// Number of tokens generated in the response
    public let completionTokens: Int?
    
    /// Total number of tokens used
    public let totalTokens: Int?
    
    /// Model-specific metadata
    public let modelMetadata: JSON?
    
    /// Finish reason (stop, length, tool_calls, etc.)
    public let finishReason: String?
    
    public init(
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil,
        modelMetadata: JSON? = nil,
        finishReason: String? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.modelMetadata = modelMetadata
        self.finishReason = finishReason
    }
}

/// Convenience initializers for common response types
public extension LLMResponse {
    
    /// Create a simple text response
    static func text(_ content: String, isComplete: Bool = true) -> LLMResponse {
        return LLMResponse(content: content, isComplete: isComplete)
    }
    
    /// Create a response with tool calls
    static func withToolCalls(
        content: String,
        toolCalls: [ToolCall],
        metadata: LLMMetadata? = nil,
        isComplete: Bool = true
    ) -> LLMResponse {
        return LLMResponse(
            content: content,
            toolCalls: toolCalls,
            metadata: metadata,
            isComplete: isComplete
        )
    }
    
    /// Create a streaming chunk response
    static func streamChunk(_ content: String) -> LLMResponse {
        return LLMResponse(content: content, isComplete: false)
    }
    
    /// Create a complete response with metadata
    static func complete(
        content: String,
        metadata: LLMMetadata? = nil
    ) -> LLMResponse {
        return LLMResponse(
            content: content,
            metadata: metadata,
            isComplete: true
        )
    }
}

/// Convenience properties for common use cases
public extension LLMResponse {
    
    /// Whether the response contains tool calls
    var hasToolCalls: Bool {
        return !toolCalls.isEmpty
    }
    
    /// Whether this is a streaming chunk (not complete)
    var isStreamingChunk: Bool {
        return !isComplete
    }
    
    /// The total number of tokens used (if available)
    var totalTokens: Int? {
        return metadata?.totalTokens
    }
    
    /// The finish reason for the response
    var finishReason: String? {
        return metadata?.finishReason
    }
} 