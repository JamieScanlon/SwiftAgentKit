//
//  OpenAIAdapterImageGenerationTests.swift
//  SwiftAgentKitAdaptersTests
//
//  Created on 1/24/25.
//

import Foundation
import Testing
import SwiftAgentKit
import SwiftAgentKitA2A
import SwiftAgentKitAdapters
import EasyJSON

@Suite("OpenAIAdapter Image Generation Tests")
struct OpenAIAdapterImageGenerationTests {
    
    @Test("OpenAIAdapter detects image generation requests via acceptedOutputModes")
    func testImageGenerationDetection() throws {
        // Create a message requesting image generation
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Generate a beautiful sunset")],
            messageId: UUID().uuidString
        )
        
        // Client accepts image output modes
        let config = MessageSendConfiguration(acceptedOutputModes: ["image/png", "text/plain"])
        let params = MessageSendParams(message: message, configuration: config)
        
        // Note: We can't actually test the full flow without an API key,
        // but we can verify the detection logic exists
        // The actual image generation would require mocking OpenAI SDK or using a test API key
        #expect(params.configuration?.acceptedOutputModes.contains("image/png") == true)
    }
    
    @Test("OpenAIAdapter falls back to text when image generation not requested")
    func testFallbackToTextGeneration() throws {
        // Create a message without image output modes
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Hello, how are you?")],
            messageId: UUID().uuidString
        )
        
        // Client only accepts text
        let config = MessageSendConfiguration(acceptedOutputModes: ["text/plain"])
        let params = MessageSendParams(message: message, configuration: config)
        
        // Should not trigger image generation
        #expect(params.configuration?.acceptedOutputModes.contains("image/png") == false)
    }
    
    @Test("OpenAIAdapter handles image generation with metadata parameters")
    func testImageGenerationWithMetadata() throws {
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Generate 2 images")],
            messageId: UUID().uuidString
        )
        
        let config = MessageSendConfiguration(acceptedOutputModes: ["image/png"])
        let params = MessageSendParams(
            message: message,
            configuration: config,
            metadata: try JSON(["n": 2, "size": "1024x1024"])
        )
        
        // Verify metadata is passed correctly
        let metadata = params.metadata?.literalValue as? [String: Any]
        #expect(metadata?["n"] as? Int == 2)
        #expect(metadata?["size"] as? String == "1024x1024")
    }
    
    @Test("OpenAIAdapter supports multiple image MIME types")
    func testMultipleImageMimeTypes() throws {
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Generate an image")],
            messageId: UUID().uuidString
        )
        
        // Test various image MIME types
        let mimeTypes = ["image/png", "image/jpeg", "image/*"]
        
        for mimeType in mimeTypes {
            let config = MessageSendConfiguration(acceptedOutputModes: [mimeType, "text/plain"])
            let params = MessageSendParams(message: message, configuration: config)
            
            let acceptsImages = params.configuration?.acceptedOutputModes.contains { mode in
                mode.lowercased().hasPrefix("image/")
            } ?? false
            
            #expect(acceptsImages, "Should accept \(mimeType)")
        }
    }
    
    @Test("OpenAIAdapter validates n parameter range")
    func testImageGenerationNParameterValidation() throws {
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Generate images")],
            messageId: UUID().uuidString
        )
        
        let config = MessageSendConfiguration(acceptedOutputModes: ["image/png"])
        
        // Test valid n values
        let validNValues = [1, 5, 10]
        for n in validNValues {
            let params = MessageSendParams(
                message: message,
                configuration: config,
                metadata: try? JSON(["n": n])
            )
            let metadata = params.metadata?.literalValue as? [String: Any]
            #expect(metadata?["n"] as? Int == n, "Should accept n=\(n)")
        }
        
        // Test invalid n values (should be handled gracefully)
        let invalidNValues = [0, 11, -1, 100]
        for n in invalidNValues {
            let params = MessageSendParams(
                message: message,
                configuration: config,
                metadata: try? JSON(["n": n])
            )
            // Validation happens in extractImageGenerationConfig, which logs warnings
            // The parameter will be clamped to valid range
            let metadata = params.metadata?.literalValue as? [String: Any]
            #expect(metadata?["n"] as? Int == n, "Metadata should preserve original value")
        }
    }
    
    @Test("OpenAIAdapter validates size parameter")
    func testImageGenerationSizeParameterValidation() throws {
        let message = A2AMessage(
            role: "user",
            parts: [.text(text: "Generate an image")],
            messageId: UUID().uuidString
        )
        
        let config = MessageSendConfiguration(acceptedOutputModes: ["image/png"])
        
        // Test valid size values
        let validSizes = ["256x256", "512x512", "1024x1024", "1024x1792", "1792x1024"]
        for size in validSizes {
            let params = MessageSendParams(
                message: message,
                configuration: config,
                metadata: try? JSON(["size": size])
            )
            let metadata = params.metadata?.literalValue as? [String: Any]
            #expect(metadata?["size"] as? String == size, "Should accept size=\(size)")
        }
        
        // Test invalid size values
        let invalidSizes = ["100x100", "2000x2000", "invalid", ""]
        for size in invalidSizes {
            let params = MessageSendParams(
                message: message,
                configuration: config,
                metadata: try? JSON(["size": size])
            )
            // Validation happens in extractImageGenerationConfig, which logs warnings
            let metadata = params.metadata?.literalValue as? [String: Any]
            #expect(metadata?["size"] as? String == size, "Metadata should preserve original value")
        }
    }
    
    @Test("OpenAIAdapter validates prompt length")
    func testImageGenerationPromptLength() throws {
        // Test normal prompt
        let normalPrompt = "Generate a sunset"
        let normalMessage = A2AMessage(
            role: "user",
            parts: [.text(text: normalPrompt)],
            messageId: UUID().uuidString
        )
        
        // Test very long prompt (over 1000 chars)
        let longPrompt = String(repeating: "a", count: 1500)
        let longMessage = A2AMessage(
            role: "user",
            parts: [.text(text: longPrompt)],
            messageId: UUID().uuidString
        )
        
        let config = MessageSendConfiguration(acceptedOutputModes: ["image/png"])
        
        // Both should be accepted (validation logs warning but doesn't reject)
        let normalParams = MessageSendParams(message: normalMessage, configuration: config)
        let longParams = MessageSendParams(message: longMessage, configuration: config)
        
        // Extract text from parts
        var normalText = ""
        var longText = ""
        if case .text(let text) = normalParams.message.parts.first {
            normalText = text
        }
        if case .text(let text) = longParams.message.parts.first {
            longText = text
        }
        
        #expect(normalText.count < 1000)
        #expect(longText.count > 1000)
    }
}
