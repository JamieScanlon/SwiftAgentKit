import Foundation
import Testing
import SwiftAgentKit
import Logging
import EasyJSON

@Suite struct LLMProtocolTests {
    
    @Test("LLMRequestConfig can be initialized with default values")
    func testLLMRequestConfigDefaultInit() throws {
        let config = LLMRequestConfig()
        
        #expect(config.maxTokens == nil)
        #expect(config.temperature == nil)
        #expect(config.topP == nil)
        #expect(config.stream == false)
        #expect(config.availableTools.isEmpty)
        #expect(config.additionalParameters == nil)
        #expect(config.toolInvocationPolicy == .automatic)
    }
    
    @Test("LLMRequestConfig can be initialized with custom values")
    func testLLMRequestConfigCustomInit() throws {
        let availableTools = [
            ToolDefinition(
                name: "test_tool",
                description: "A test tool",
                parameters: [
                    .init(name: "input", description: "Input parameter", type: "string", required: true)
                ],
                type: .function
            )
        ]
        
        let config = LLMRequestConfig(
            maxTokens: 1000,
            temperature: 0.7,
            topP: 0.9,
            stream: true,
            availableTools: availableTools,
            additionalParameters: .object(["test": .string("value")])
        )
        
        #expect(config.maxTokens == 1000)
        #expect(config.temperature == 0.7)
        #expect(config.topP == 0.9)
        #expect(config.stream == true)
        #expect(config.availableTools.count == 1)
        #expect(config.availableTools.first?.name == "test_tool")
        #expect(config.additionalParameters != nil)
        #expect(config.toolInvocationPolicy == .automatic)
    }
    
    @Test("LLMResponse works correctly")
    func testLLMResponseCases() throws {
        // Test simple text response
        let textResponse = LLMResponse.text("Hello")
        #expect(textResponse.content == "Hello")
        #expect(textResponse.isComplete == true)
        #expect(textResponse.hasToolCalls == false)
        
        // Test streaming chunk
        let streamChunk = LLMResponse.streamChunk("Partial")
        #expect(streamChunk.content == "Partial")
        #expect(streamChunk.isComplete == false)
        #expect(streamChunk.isStreamingChunk == true)
        
        // Test response with tool calls
        let toolCall = ToolCall(name: "calculator", arguments: try! JSON(["expression": "2+2"]), id: UUID().uuidString)
        let toolResponse = LLMResponse.withToolCalls(
            content: "I'll calculate that for you",
            toolCalls: [toolCall]
        )
        #expect(toolResponse.content == "I'll calculate that for you")
        #expect(toolResponse.hasToolCalls == true)
        #expect(toolResponse.toolCalls.count == 1)
        #expect(toolResponse.toolCalls.first?.name == "calculator")
        
        // Test response with metadata
        let metadata = LLMMetadata(
            promptTokens: 10,
            completionTokens: 5,
            totalTokens: 15,
            finishReason: "stop"
        )
        let completeResponse = LLMResponse.complete(content: "Done", metadata: metadata)
        #expect(completeResponse.content == "Done")
        #expect(completeResponse.isComplete == true)
        #expect(completeResponse.totalTokens == 15)
        #expect(completeResponse.inputTokens == 10)
        #expect(completeResponse.outputTokens == 5)
        #expect(completeResponse.finishReason == "stop")
        
        let ctxMeta = LLMMetadata(
            promptTokens: 100,
            completionTokens: 20,
            totalTokens: 120,
            contextWindowTokens: 8192,
            finishReason: "stop"
        )
        #expect(ctxMeta.remainingContextTokens == 8092)
        let ctxResponse = LLMResponse.complete(content: "x", metadata: ctxMeta)
        #expect(ctxResponse.remainingContextTokens == 8092)
    }
    
    @Test("LLMError provides proper error descriptions")
    func testLLMErrorDescriptions() throws {
        let invalidRequest = LLMError.invalidRequest("test message")
        let rateLimit = LLMError.rateLimitExceeded
        let modelNotFound = LLMError.modelNotFound("gpt-5")
        let authFailed = LLMError.authenticationFailed
        let timeout = LLMError.timeout
        let unsupportedCapabilityVision = LLMError.unsupportedCapability(.vision)
        let unsupportedCapabilityImageGen = LLMError.unsupportedCapability(.imageGeneration)
        
        #expect(invalidRequest.localizedDescription.contains("Invalid request"))
        #expect(invalidRequest.localizedDescription.contains("test message"))
        #expect(rateLimit.localizedDescription.contains("Rate limit exceeded"))
        #expect(modelNotFound.localizedDescription.contains("Model not found"))
        #expect(modelNotFound.localizedDescription.contains("gpt-5"))
        #expect(authFailed.localizedDescription.contains("Authentication failed"))
        #expect(timeout.localizedDescription.contains("Request timeout"))
        #expect(unsupportedCapabilityVision.localizedDescription.contains("Unsupported capability"))
        #expect(unsupportedCapabilityVision.localizedDescription.contains("vision"))
        #expect(unsupportedCapabilityImageGen.localizedDescription.contains("Unsupported capability"))
        #expect(unsupportedCapabilityImageGen.localizedDescription.contains("imageGeneration"))
        
        let imageGenError = LLMError.imageGenerationError(.noImagesGenerated)
        #expect(imageGenError.localizedDescription.contains("No images were generated") == true)
    }
    
    @Test("LLMRequestConfig can be initialized with available tools")
    func testLLMRequestConfigWithTools() throws {
        let availableTools = [
            ToolDefinition(
                name: "calculator",
                description: "A simple calculator",
                parameters: [
                    .init(name: "expression", description: "Mathematical expression", type: "string", required: true)
                ],
                type: .function
            ),
            ToolDefinition(
                name: "weather",
                description: "Get weather information",
                parameters: [
                    .init(name: "location", description: "Location to check", type: "string", required: true)
                ],
                type: .function
            )
        ]
        
        let config = LLMRequestConfig(availableTools: availableTools)
        
        #expect(config.availableTools.count == 2)
        #expect(config.availableTools.first?.name == "calculator")
        #expect(config.availableTools.last?.name == "weather")
        #expect(config.availableTools.first?.type == .function)
        #expect(config.availableTools.first?.parameters.count == 1)
        #expect(config.availableTools.first?.parameters.first?.name == "expression")
    }
    
    @Test("LLMProtocol implementations provide getModelName()")
    func testGetModelName() throws {
        // Create a test LLM implementation
        struct TestLLM: LLMProtocol {
            let modelName: String
            
            func getModelName() -> String {
                return modelName
            }
            
            func getCapabilities() -> [LLMCapability] {
                return [.completion, .tools]
            }
            
            func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
                return LLMResponse.complete(content: "Test response")
            }
            
            func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
                return AsyncThrowingStream { continuation in
                    continuation.yield(.complete(LLMResponse.complete(content: "Test streaming response")))
                    continuation.finish()
                }
            }
        }
        
        let testLLM = TestLLM(modelName: "test-model-v1")
        
        #expect(testLLM.getModelName() == "test-model-v1")
    }

    @Test("LLMProtocol default runtime state is ready")
    func testDefaultRuntimeState() throws {
        struct StatelessLLM: LLMProtocol {
            func getModelName() -> String { "stateless" }
            func getCapabilities() -> [LLMCapability] { [.completion] }
            func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
                .complete(content: "ok")
            }
            func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
                AsyncThrowingStream { continuation in
                    continuation.yield(.complete(.complete(content: "ok")))
                    continuation.finish()
                }
            }
        }

        let llm = StatelessLLM()
        #expect(llm.currentState == .idle(.ready))
    }

    @Test("LLMRuntimeStateStore broadcasts transitions in order")
    func testRuntimeStateStoreBroadcastsTransitions() async throws {
        let store = LLMRuntimeStateStore()
        let stream = store.makeStream()
        let collector = Task<[LLMRuntimeState], Never> {
            var observed: [LLMRuntimeState] = []
            var iterator = stream.makeAsyncIterator()
            for _ in 0..<3 {
                if let state = await iterator.next() {
                    observed.append(state)
                }
            }
            return observed
        }

        store.transition(to: .generating(.reasoning))
        store.transition(to: .idle(.completed))

        let observed = await collector.value
        #expect(observed.count == 3)
        #expect(observed[0] == .idle(.ready))
        #expect(observed[1] == .generating(.reasoning))
        #expect(observed[2] == .idle(.completed))
    }

    @Test("StatefulLLM transitions to completed for tool-call response (LLM is done generating)")
    func testStatefulLLMTransitionsForToolCallResponse() async throws {
        struct ToolCallLLM: LLMProtocol {
            func getModelName() -> String { "tool-call-llm" }
            func getCapabilities() -> [LLMCapability] { [.completion, .tools] }
            func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
                .withToolCalls(
                    content: "",
                    toolCalls: [ToolCall(name: "calculator", arguments: .object([:]), id: UUID().uuidString)]
                )
            }
            func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
                AsyncThrowingStream { continuation in
                    continuation.yield(.complete(.complete(content: "unused")))
                    continuation.finish()
                }
            }
        }

        let llm = StatefulLLM(baseLLM: ToolCallLLM())
        let observation = llm.stateUpdates

        let collector = Task<[LLMRuntimeState], Never> {
            var observed: [LLMRuntimeState] = []
            var iterator = observation.makeAsyncIterator()
            for _ in 0..<3 {
                if let state = await iterator.next() {
                    observed.append(state)
                }
            }
            return observed
        }

        _ = try await llm.send([Message(id: UUID(), role: .user, content: "hi")], config: LLMRequestConfig())
        let observed = await collector.value

        #expect(observed[0] == .idle(.ready))
        #expect(observed[1] == .generating(.reasoning))
        #expect(observed[2] == .idle(.completed))
        #expect(llm.currentState == .idle(.completed))
    }

    @Test("StatefulLLM send publishes per-call request phases without queued")
    func testStatefulLLMRequestStatesSendExcludesQueued() async throws {
        struct SimpleLLM: LLMProtocol {
            func getModelName() -> String { "simple" }
            func getCapabilities() -> [LLMCapability] { [.completion] }
            func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
                .complete(content: "ok")
            }
            func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        }

        let llm = StatefulLLM(baseLLM: SimpleLLM())
        let stream = llm.requestStateUpdates
        var iterator = stream.makeAsyncIterator()

        let sendTask = Task {
            try await llm.send([Message(id: UUID(), role: .user, content: "hi")], config: LLMRequestConfig())
        }

        var phases: [LLMRequestState] = []
        while let (_, phase) = await iterator.next() {
            phases.append(phase)
            if case .completed = phase { break }
        }
        _ = try await sendTask.value

        #expect(phases.contains(.active))
        #expect(phases.contains(.generating(.reasoning)))
        #expect(phases.contains(.completed))
        let hasQueued = phases.contains { phase in
            if case .queued = phase { return true }
            return false
        }
        #expect(!hasQueued)
    }
    
    @Test("ImageGenerationRequestConfig can be initialized")
    func testImageGenerationRequestConfig() throws {
        let imageData = Data("test image data".utf8)
        let maskData = Data("test mask data".utf8)
        
        let config = ImageGenerationRequestConfig(
            image: imageData,
            fileName: "test.png",
            mask: maskData,
            maskFileName: "mask.png",
            prompt: "A beautiful sunset",
            n: 3,
            size: "512x512"
        )
        
        #expect(config.image == imageData)
        #expect(config.fileName == "test.png")
        #expect(config.mask == maskData)
        #expect(config.maskFileName == "mask.png")
        #expect(config.prompt == "A beautiful sunset")
        #expect(config.n == 3)
        #expect(config.size == "512x512")
    }
    
    @Test("ImageGenerationRequestConfig can be initialized with optional parameters")
    func testImageGenerationRequestConfigOptional() throws {
        let imageData = Data("test image data".utf8)
        
        let config = ImageGenerationRequestConfig(
            image: imageData,
            fileName: "test.png",
            prompt: "A beautiful sunset"
        )
        
        #expect(config.image == imageData)
        #expect(config.fileName == "test.png")
        #expect(config.mask == nil)
        #expect(config.maskFileName == nil)
        #expect(config.prompt == "A beautiful sunset")
        #expect(config.n == nil)
        #expect(config.size == nil)
    }
    
    @Test("ImageGenerationRequestConfig can be initialized for pure generation without image")
    func testImageGenerationRequestConfigPureGeneration() throws {
        // Pure image generation - no input image required
        let config = ImageGenerationRequestConfig(
            prompt: "A beautiful sunset",
            n: 2,
            size: "512x512"
        )
        
        #expect(config.image == nil)
        #expect(config.fileName == nil)
        #expect(config.mask == nil)
        #expect(config.maskFileName == nil)
        #expect(config.prompt == "A beautiful sunset")
        #expect(config.n == 2)
        #expect(config.size == "512x512")
    }
    
    @Test("ImageGenerationResponse can be initialized")
    func testImageGenerationResponse() throws {
        let imageURL1 = URL(fileURLWithPath: "/tmp/image1.png")
        let imageURL2 = URL(fileURLWithPath: "/tmp/image2.png")
        let metadata = LLMMetadata(totalTokens: 100)
        let createdAt = Date()
        
        let response = ImageGenerationResponse(
            images: [imageURL1, imageURL2],
            createdAt: createdAt,
            metadata: metadata
        )
        
        #expect(response.images.count == 2)
        #expect(response.images[0] == imageURL1)
        #expect(response.images[1] == imageURL2)
        #expect(response.createdAt == createdAt)
        #expect(response.metadata?.totalTokens == 100)
    }
    
    @Test("ImageGenerationResponse can be initialized with default createdAt")
    func testImageGenerationResponseDefaultCreatedAt() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/image.png")
        let beforeCreation = Date()
        
        let response = ImageGenerationResponse(images: [imageURL])
        
        let afterCreation = Date()
        
        #expect(response.images.count == 1)
        #expect(response.images[0] == imageURL)
        #expect(response.createdAt >= beforeCreation)
        #expect(response.createdAt <= afterCreation)
        #expect(response.metadata == nil)
    }
    
    @Test("Default generateImage implementation throws unsupported capability error")
    func testDefaultGenerateImageThrowsError() async throws {
        struct TestLLM: LLMProtocol {
            func getModelName() -> String { "test-model" }
            func getCapabilities() -> [LLMCapability] { [.completion] }
            func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
                return LLMResponse.complete(content: "Test")
            }
            func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
                return AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        }
        
        let llm = TestLLM()
        let config = ImageGenerationRequestConfig(
            prompt: "test prompt"
        )
        
        do {
            _ = try await llm.generateImage(config)
            Issue.record("Expected error to be thrown")
        } catch let error as LLMError {
            if case .unsupportedCapability(.imageGeneration) = error {
                // Expected error
            } else {
                Issue.record("Unexpected error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test("ImageGenerationError provides proper error descriptions")
    func testImageGenerationErrorDescriptions() throws {
        let invalidPrompt = ImageGenerationError.invalidPrompt("Prompt exceeds 1000 characters")
        #expect(invalidPrompt.errorDescription?.contains("Invalid image generation prompt") == true)
        
        let invalidSize = ImageGenerationError.invalidSize("2000x2000")
        #expect(invalidSize.errorDescription?.contains("Invalid image size") == true)
        #expect(invalidSize.errorDescription?.contains("256x256") == true)
        
        let invalidCount = ImageGenerationError.invalidCount(15)
        #expect(invalidCount.errorDescription?.contains("Invalid image count") == true)
        #expect(invalidCount.errorDescription?.contains("15") == true)
        
        let noImages = ImageGenerationError.noImagesGenerated
        #expect(noImages.errorDescription?.contains("No images were generated") == true)
        
        let testURL = URL(string: "https://example.com/image.png")!
        let testError = NSError(domain: "TestError", code: 404, userInfo: nil)
        let downloadFailed = ImageGenerationError.downloadFailed(testURL, testError)
        #expect(downloadFailed.errorDescription?.contains("Failed to download image") == true)
        #expect(downloadFailed.errorDescription?.contains("example.com") == true)
    }
    
    @Test("LLMError.queueFull provides proper description")
    func testQueueFullErrorDescription() throws {
        let error = LLMError.queueFull
        #expect(error.localizedDescription.contains("queue"))
        #expect(error.localizedDescription.contains("capacity"))
    }

    @Test("LLMError.queueTimeout provides proper description")
    func testQueueTimeoutErrorDescription() throws {
        let error = LLMError.queueTimeout
        #expect(error.localizedDescription.contains("timed out"))
        #expect(error.localizedDescription.contains("queue"))
    }

    @Test("QueuedLLM transparently wraps an LLMProtocol implementation")
    func testQueuedLLMSmokeTest() async throws {
        struct SimpleLLM: LLMProtocol {
            func getModelName() -> String { "simple" }
            func getCapabilities() -> [LLMCapability] { [.completion] }
            func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
                .complete(content: "queued-ok")
            }
            func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
                AsyncThrowingStream { continuation in
                    continuation.yield(.complete(.complete(content: "stream-ok")))
                    continuation.finish()
                }
            }
        }

        let queued = QueuedLLM(baseLLM: SimpleLLM())
        #expect(queued.getModelName() == "simple")
        #expect(queued.getCapabilities() == [.completion])

        let response = try await queued.send(
            [Message(id: UUID(), role: .user, content: "test")],
            config: LLMRequestConfig()
        )
        #expect(response.content == "queued-ok")
    }

    @Test("LLMError.imageGenerationError wraps ImageGenerationError")
    func testLLMErrorImageGenerationError() throws {
        let imageError = ImageGenerationError.noImagesGenerated
        let llmError = LLMError.imageGenerationError(imageError)
        
        #expect(llmError.errorDescription == imageError.errorDescription)
        
        if case .imageGenerationError(let wrappedError) = llmError {
            // Verify wrapped error matches
            if case .noImagesGenerated = wrappedError {
                // Expected
            } else {
                Issue.record("Expected noImagesGenerated error")
            }
        } else {
            Issue.record("Expected imageGenerationError case")
        }
    }
} 
