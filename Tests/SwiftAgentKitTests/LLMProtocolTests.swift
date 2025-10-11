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
        #expect(completeResponse.finishReason == "stop")
    }
    
    @Test("LLMError provides proper error descriptions")
    func testLLMErrorDescriptions() throws {
        let invalidRequest = LLMError.invalidRequest("test message")
        let rateLimit = LLMError.rateLimitExceeded
        let modelNotFound = LLMError.modelNotFound("gpt-5")
        let authFailed = LLMError.authenticationFailed
        let timeout = LLMError.timeout
        let unsupportedCapability = LLMError.unsupportedCapability(.vision)
        
        #expect(invalidRequest.localizedDescription.contains("Invalid request"))
        #expect(invalidRequest.localizedDescription.contains("test message"))
        #expect(rateLimit.localizedDescription.contains("Rate limit exceeded"))
        #expect(modelNotFound.localizedDescription.contains("Model not found"))
        #expect(modelNotFound.localizedDescription.contains("gpt-5"))
        #expect(authFailed.localizedDescription.contains("Authentication failed"))
        #expect(timeout.localizedDescription.contains("Request timeout"))
        #expect(unsupportedCapability.localizedDescription.contains("Unsupported capability"))
        #expect(unsupportedCapability.localizedDescription.contains("vision"))
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
} 
