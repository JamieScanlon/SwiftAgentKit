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
    
    /// Default implementation that throws an unsupported capability error
    /// Implementations that support image generation should override this method
    func generateImage(_ config: ImageGenerationRequestConfig) async throws -> ImageGenerationResponse {
        throw LLMError.unsupportedCapability(.imageGeneration)
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
    case imageGeneration
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
