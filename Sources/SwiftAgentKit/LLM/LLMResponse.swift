import Foundation
import EasyJSON

/// Represents a file or opaque data part in an LLM response (non-image).
/// Stored in metadata as base64 when carrying binary data.
public struct LLMResponseFile: Sendable {
    public var name: String?
    public var mimeType: String?
    public var data: Data?
    public var url: URL?
    
    public init(name: String? = nil, mimeType: String? = nil, data: Data? = nil, url: URL? = nil) {
        self.name = name
        self.mimeType = mimeType
        self.data = data
        self.url = url
    }
    
    /// Decode from JSON (e.g. from metadata.modelMetadata["files"]).
    public init?(from json: JSON) {
        guard case .object(let dict) = json else { return nil }
        if case .string(let n) = dict["name"] { name = n } else { name = nil }
        if case .string(let m) = dict["mimeType"] { mimeType = m } else { mimeType = nil }
        if case .string(let b64) = dict["data"], let d = Data(base64Encoded: b64) { data = d } else { data = nil }
        if case .string(let s) = dict["url"] { url = URL(string: s) } else { url = nil }
    }
    
    /// Encode for storage in metadata (data as base64).
    public func toJSON() -> JSON {
        var d: [String: JSON] = [:]
        if let name { d["name"] = .string(name) }
        if let mimeType { d["mimeType"] = .string(mimeType) }
        if let data { d["data"] = .string(data.base64EncodedString()) }
        if let url { d["url"] = .string(url.absoluteString) }
        return .object(d)
    }
}

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
    
    /// The ID of the tool call this response is associated with (for tool role messages)
    public let toolCallId: String?
    
    public init(
        content: String,
        toolCalls: [ToolCall] = [],
        metadata: LLMMetadata? = nil,
        isComplete: Bool = true,
        toolCallId: String? = nil
    ) {
        self.content = content
        self.toolCalls = toolCalls
        self.metadata = metadata
        self.isComplete = isComplete
        self.toolCallId = toolCallId
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
        isComplete: Bool = true,
        toolCallId: String? = nil
    ) -> LLMResponse {
        return LLMResponse(
            content: content,
            toolCalls: toolCalls,
            metadata: metadata,
            isComplete: isComplete,
            toolCallId: toolCallId
        )
    }
    
    /// Create a streaming chunk response
    static func streamChunk(_ content: String) -> LLMResponse {
        return LLMResponse(content: content, isComplete: false)
    }
    
    /// Create a complete response with metadata
    static func complete(
        content: String,
        metadata: LLMMetadata? = nil,
        toolCallId: String? = nil
    ) -> LLMResponse {
        return LLMResponse(
            content: content,
            metadata: metadata,
            isComplete: true,
            toolCallId: toolCallId
        )
    }
    
    func appending(toolCalls: [ToolCall]) -> LLMResponse {
        var updatedToolCalls = self.toolCalls
        updatedToolCalls.append(contentsOf: toolCalls)
        return LLMResponse(
            content: content,
            toolCalls: updatedToolCalls,
            metadata: metadata,
            isComplete: isComplete,
            toolCallId: toolCallId
        )
    }
    
    func removingToolCalls() -> LLMResponse {
        return LLMResponse(
            content: content,
            toolCalls: [],
            metadata: metadata,
            isComplete: isComplete,
            toolCallId: toolCallId
        )
    }
    
    func updatingContent(with newContent: String) -> LLMResponse {
        return LLMResponse(
            content: newContent,
            toolCalls: toolCalls,
            metadata: metadata,
            isComplete: isComplete,
            toolCallId: toolCallId
        )
    }
    
    func updatingMetadata(with newMetadata: LLMMetadata?) -> LLMResponse {
        return LLMResponse(
            content: content,
            toolCalls: toolCalls,
            metadata: newMetadata,
            isComplete: isComplete,
            toolCallId: toolCallId
        )
    }
    
    func markingComplete() -> LLMResponse {
        return LLMResponse(
            content: content,
            toolCalls: toolCalls,
            metadata: metadata,
            isComplete: true,
            toolCallId: toolCallId
        )
    }
    
    func markingIncomplete() -> LLMResponse {
        return LLMResponse(
            content: content,
            toolCalls: toolCalls,
            metadata: metadata,
            isComplete: false,
            toolCallId: toolCallId
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
    
    /// Extracts Message.Image objects from the response metadata
    /// Images are stored in metadata.modelMetadata["images"] as a JSON array
    var images: [Message.Image] {
        guard let modelMetadata = metadata?.modelMetadata,
              case .object(let dict) = modelMetadata,
              case .array(let imagesArray) = dict["images"] else {
            return []
        }
        
        return imagesArray.compactMap { imageJSON in
            Message.Image(from: imageJSON)
        }
    }
    
    /// Extracts file/data content from the response metadata
    /// Files are stored in metadata.modelMetadata["files"] as a JSON array (data as base64)
    var files: [LLMResponseFile] {
        guard let modelMetadata = metadata?.modelMetadata,
              case .object(let dict) = modelMetadata,
              case .array(let filesArray) = dict["files"] else {
            return []
        }
        
        return filesArray.compactMap { fileJSON in
            LLMResponseFile(from: fileJSON)
        }
    }
} 
