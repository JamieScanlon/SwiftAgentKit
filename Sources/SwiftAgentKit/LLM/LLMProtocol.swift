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
    /// How tool calls are selected when ``availableTools`` is non-empty.
    public let toolInvocationPolicy: ToolInvocationPolicy
    /// .text / .jsonObject / .jsonSchema(JSON)
    public let responseFormat: ResponseFormatRequest?  
    /// honored when ParallelToolCallSupport != .unsupported    
    public let parallelToolCalls: Bool?            
    /// honored when ModelRequestFeatures.reasoningEfforts contains it        
    public let reasoningEffort: ReasoningEffort?           
    
    public init(
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        stream: Bool = false,
        availableTools: [ToolDefinition] = [],
        additionalParameters: JSON? = nil,
        toolInvocationPolicy: ToolInvocationPolicy = .automatic,
        responseFormat: ResponseFormatRequest? = nil,
        parallelToolCalls: Bool? = nil,
        reasoningEffort: ReasoningEffort? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stream = stream
        self.availableTools = availableTools
        self.additionalParameters = additionalParameters
        self.toolInvocationPolicy = toolInvocationPolicy
        self.responseFormat = responseFormat
        self.parallelToolCalls = parallelToolCalls
        self.reasoningEffort = reasoningEffort
    }
}

/// Per-call response-format request. Pair with ``ModelRequestFeatures/responseFormats``
/// to validate that the model accepts the chosen kind.
public enum ResponseFormatRequest: Sendable {
    case text
    case jsonObject
    case jsonSchema(name: String, schema: JSON)
}

/// Configuration options for image generation requests
public struct ImageGenerationRequestConfig: Sendable {
    /// The image data to use for generation/editing. If nil, pure image generation will be performed.
    public let image: Data?
    /// The filename for the image. Required if image is provided.
    public let fileName: String?
    /// An additional image whose fully transparent areas (e.g. where alpha is zero) indicate where image should be edited. Must be a valid PNG file, less than 4MB, and have the same dimensions as image.
    public let mask: Data?
    /// The filename for the mask image
    public let maskFileName: String?
    /// A text description of the desired image(s). The maximum length is 1000 characters.
    public let prompt: String
    /// The number of images to generate. Must be between 1 and 10.
    public let n: Int?
    /// The size of the generated images. Must be one of 256x256, 512x512, or 1024x1024.
    public let size: String?
    
    public init(
        image: Data? = nil,
        fileName: String? = nil,
        mask: Data? = nil,
        maskFileName: String? = nil,
        prompt: String,
        n: Int? = nil,
        size: String? = nil
    ) {
        self.image = image
        self.fileName = fileName
        self.mask = mask
        self.maskFileName = maskFileName
        self.prompt = prompt
        self.n = n
        self.size = size
    }
}

/// A common protocol for interacting with LLMs
public protocol LLMProtocol: Sendable {
    /// The current runtime state for this LLM.
    ///
    /// Implementers can expose detailed execution phases (e.g. reasoning, responding).
    /// Tool-waiting and queue position are **per-request** concerns; see `LLMRequestState`
    /// and `StatefulLLM` / `QueuedLLM`. The default implementation returns `.idle(.ready)`.
    var currentState: LLMRuntimeState { get }

    /// A stream of runtime state transitions for this LLM.
    ///
    /// The default implementation yields `currentState` once and then finishes.
    /// Implementers that support live updates should override and continuously
    /// emit transitions as request processing progresses.
    var stateUpdates: AsyncStream<LLMRuntimeState> { get }

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
    
    /// Generate images based on the provided configuration
    /// - Parameters:
    ///   - config: Configuration for the image generation request
    /// - Returns: The image generation response containing generated images
    func generateImage(_ config: ImageGenerationRequestConfig) async throws -> ImageGenerationResponse

    /// The per-call request features this LLM honors.
    ///
    /// Companion to ``getCapabilities()``: capabilities gate features on/off
    /// (can the model do X at all?), while request features describe the legal
    /// values for the per-call knobs on ``LLMRequestConfig`` (which response
    /// formats, parallel-tool-call cap, reasoning-effort levels, etc.).
    ///
    /// - Returns: The accepted request-feature menu for this model.
    func getRequestFeatures() -> ModelRequestFeatures
}

/// Response from an image generation request
public struct ImageGenerationResponse: Sendable {
    /// URLs pointing to the generated images on the filesystem
    public let images: [URL]
    /// Timestamp when the images were created
    public let createdAt: Date
    /// Optional metadata about the generation (tokens used, model info, etc.)
    public let metadata: LLMMetadata?
    
    public init(
        images: [URL],
        createdAt: Date = Date(),
        metadata: LLMMetadata? = nil
    ) {
        self.images = images
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

/// Default implementations for the LLMProtocol
public extension LLMProtocol {
    var currentState: LLMRuntimeState {
        .idle(.ready)
    }

    var stateUpdates: AsyncStream<LLMRuntimeState> {
        AsyncStream { continuation in
            continuation.yield(currentState)
            continuation.finish()
        }
    }
    
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
            additionalParameters: config.additionalParameters,
            toolInvocationPolicy: config.toolInvocationPolicy,
            responseFormat: config.responseFormat,
            parallelToolCalls: config.parallelToolCalls,
            reasoningEffort: config.reasoningEffort
        )
    }
    
    /// Default implementation that throws an unsupported capability error
    /// Implementations that support image generation should override this method
    func generateImage(_ config: ImageGenerationRequestConfig) async throws -> ImageGenerationResponse {
        throw LLMError.unsupportedCapability(.imageGeneration)
    }

    /// Default returns ``ModelRequestFeatures/unknown``; adapters that know
    /// their backend should override.
    func getRequestFeatures() -> ModelRequestFeatures {
        return ModelRequestFeatures.unknown
    }
}

/// An enumeration representing the exact model capability
public enum LLMCapability: String, Codable, Sendable {
    case unknown
    case completion
    case tools
    case insert
    case vision
    case audio
    case embedding
    case thinking                  // supports OPTIONAL reasoning (caller may enable)
    case reasoningRequired         // ALWAYS reasons; no opt-out (e.g. deepseek-r1)
    case promptCacheEphemeral      // provider/model supports ephemeral cache breakpoints
    case promptCachePersistent     // provider/model supports persistent cache breakpoints
    case imageGeneration
}

public enum ResponseFormatKind: String, Codable, Sendable {
    case text          // implicit baseline; absence => text only
    case jsonObject    // OpenAI response_format=json_object / Ollama format=json
    case jsonSchema    // schema-constrained structured output
}

public enum ReasoningEffort: String, Codable, Sendable {
    case minimal
    case low
    case medium
    case high
}

public enum ParallelToolCallSupport: Sendable, Hashable, Codable {
    case unsupported
    case uncapped
    case capped(Int)   // max simultaneous tool calls per turn
}

public struct ModelRequestFeatures: Sendable, Hashable, Codable {
    public var streaming: Bool // Does this model honor stream: true requests?
    public var responseFormats: Set<ResponseFormatKind> // Which response_format values can I send it?"
    public var parallelToolCalls: ParallelToolCallSupport // If I ask for parallel tool calls, will it accept it, and is there a cap?
    public var reasoningEfforts: Set<ReasoningEffort>     // If reasoning is opt‑in, which reasoning_effort levels does it accept? empty when no opt-in reasoning

    public static let unknown = ModelRequestFeatures(
        streaming: false,
        responseFormats: [.text],
        parallelToolCalls: .unsupported,
        reasoningEfforts: []
    )

    public static let chatBaseline = ModelRequestFeatures(
        streaming: true,
        responseFormats: [.text],
        parallelToolCalls: .unsupported,
        reasoningEfforts: []
    )

    public init(
        streaming: Bool,
        responseFormats: Set<ResponseFormatKind>,
        parallelToolCalls: ParallelToolCallSupport,
        reasoningEfforts: Set<ReasoningEffort>
    ) {
        self.streaming = streaming
        self.responseFormats = responseFormats
        self.parallelToolCalls = parallelToolCalls
        self.reasoningEfforts = reasoningEfforts
    }
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
    
    // Image generation specific errors
    case imageGenerationError(ImageGenerationError)
    
    // Queue specific errors
    case queueFull
    case queueTimeout
    
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
        case .imageGenerationError(let error):
            return error.errorDescription
        case .queueFull:
            return "Request rejected: LLM queue is at capacity"
        case .queueTimeout:
            return "Request timed out waiting in the LLM queue"
        }
    }
}

/// Errors specific to image generation
public enum ImageGenerationError: Error, LocalizedError, Sendable {
    case invalidPrompt(String)  // Prompt too long, empty, etc.
    case invalidSize(String)    // Unsupported size
    case invalidCount(Int)      // n out of range
    case downloadFailed(URL, Error)  // Image download error
    case noImagesGenerated      // API returned no images
    case invalidImageData(URL)  // Downloaded data is not a valid image
    
    public var errorDescription: String? {
        switch self {
        case .invalidPrompt(let reason):
            return "Invalid image generation prompt: \(reason)"
        case .invalidSize(let size):
            return "Invalid image size: \(size). Valid sizes: 256x256, 512x512, 1024x1024, 1024x1792, 1792x1024"
        case .invalidCount(let count):
            return "Invalid image count: \(count). Must be between 1 and 10"
        case .downloadFailed(let url, let error):
            return "Failed to download image from \(url.absoluteString): \(error.localizedDescription)"
        case .noImagesGenerated:
            return "No images were generated by the API"
        case .invalidImageData(let url):
            return "Downloaded data from \(url.absoluteString) is not a valid image"
        }
    }
} 
