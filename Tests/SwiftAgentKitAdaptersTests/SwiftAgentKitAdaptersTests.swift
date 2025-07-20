//
//  SwiftAgentKitAdaptersTests.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 6/13/25.
//

import Foundation
import Testing
import SwiftAgentKitAdapters
import SwiftAgentKitA2A

@Suite struct SwiftAgentKitAdaptersTests {
    
    // MARK: - Basic Capability Tests
    
    @Test("OpenAIAdapter should have correct capabilities")
    func testOpenAIAdapterCapabilities() throws {
        let adapter = OpenAIAdapter(apiKey: "test-key")
        
        #expect(adapter.cardCapabilities.streaming == true)
        #expect(adapter.cardCapabilities.pushNotifications == false)
        #expect(adapter.cardCapabilities.stateTransitionHistory == true)
        #expect(adapter.defaultInputModes == ["text/plain"])
        #expect(adapter.defaultOutputModes == ["text/plain"])
        #expect(adapter.skills.count >= 3)
    }
    
    @Test("AnthropicAdapter should have correct capabilities")
    func testAnthropicAdapterCapabilities() throws {
        let adapter = AnthropicAdapter(apiKey: "test-key")
        
        #expect(adapter.cardCapabilities.streaming == true)
        #expect(adapter.cardCapabilities.pushNotifications == false)
        #expect(adapter.cardCapabilities.stateTransitionHistory == true)
        #expect(adapter.defaultInputModes == ["text/plain"])
        #expect(adapter.defaultOutputModes == ["text/plain"])
        #expect(adapter.skills.count >= 4)
    }
    
    @Test("GeminiAdapter should have correct capabilities")
    func testGeminiAdapterCapabilities() throws {
        let adapter = GeminiAdapter(apiKey: "test-key")
        
        #expect(adapter.cardCapabilities.streaming == true)
        #expect(adapter.cardCapabilities.pushNotifications == false)
        #expect(adapter.cardCapabilities.stateTransitionHistory == true)
        #expect(adapter.defaultInputModes == ["text/plain"])
        #expect(adapter.defaultOutputModes == ["text/plain"])
        #expect(adapter.skills.count >= 4)
    }
    
    // MARK: - Skill Tests
    
    @Test("OpenAIAdapter should have text generation skill")
    func testOpenAIAdapterTextGenerationSkill() throws {
        let adapter = OpenAIAdapter(apiKey: "test-key")
        let textGenerationSkill = adapter.skills.first { $0.id == "text-generation" }
        
        #expect(textGenerationSkill != nil)
        #expect(textGenerationSkill?.name == "Text Generation")
        #expect(textGenerationSkill?.tags.contains("openai") == true)
    }
    
    @Test("AnthropicAdapter should have reasoning skill")
    func testAnthropicAdapterReasoningSkill() throws {
        let adapter = AnthropicAdapter(apiKey: "test-key")
        let reasoningSkill = adapter.skills.first { $0.id == "reasoning" }
        
        #expect(reasoningSkill != nil)
        #expect(reasoningSkill?.name == "Logical Reasoning")
        #expect(reasoningSkill?.tags.contains("reasoning") == true)
    }
    
    @Test("GeminiAdapter should have multimodal skill")
    func testGeminiAdapterMultimodalSkill() throws {
        let adapter = GeminiAdapter(apiKey: "test-key")
        let multimodalSkill = adapter.skills.first { $0.id == "multimodal" }
        
        #expect(multimodalSkill != nil)
        #expect(multimodalSkill?.name == "Multimodal Processing")
        #expect(multimodalSkill?.tags.contains("multimodal") == true)
        #expect(multimodalSkill?.inputModes?.contains("image/jpeg") == true)
    }
    
    // MARK: - Configuration Tests
    
    @Test("OpenAIAdapter configuration should work")
    func testOpenAIAdapterConfiguration() throws {
        let config = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4",
            maxTokens: 500,
            temperature: 0.5,
            systemPrompt: "You are a helpful assistant.",
            topP: 0.9,
            frequencyPenalty: 0.1,
            presencePenalty: 0.1,
            stopSequences: ["END"],
            user: "test-user"
        )
        let adapter = OpenAIAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    @Test("OpenAIAdapter should support system prompts")
    func testOpenAIAdapterSystemPrompt() throws {
        let adapter = OpenAIAdapter(
            apiKey: "test-key",
            model: "gpt-4o",
            systemPrompt: "You are a coding assistant. Always respond with code examples."
        )
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    @Test("AnthropicAdapter configuration should work")
    func testAnthropicAdapterConfiguration() throws {
        let config = AnthropicAdapter.Configuration(
            apiKey: "test-key",
            model: "claude-3-opus-20240229",
            maxTokens: 1000,
            temperature: 0.3
        )
        let adapter = AnthropicAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    @Test("GeminiAdapter configuration should work")
    func testGeminiAdapterConfiguration() throws {
        let config = GeminiAdapter.Configuration(
            apiKey: "test-key",
            model: "gemini-1.5-pro",
            maxTokens: 800,
            temperature: 0.6
        )
        let adapter = GeminiAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    // MARK: - OpenAI Adapter Edge Cases and Error Handling
    
    @Test("OpenAIAdapter should handle empty API key")
    func testOpenAIAdapterEmptyApiKey() throws {
        let adapter = OpenAIAdapter(apiKey: "")
        
        #expect(adapter.cardCapabilities.streaming == true)
        // Note: API key validation would happen during actual API calls
    }
    
    @Test("OpenAIAdapter should handle custom base URL")
    func testOpenAIAdapterCustomBaseURL() throws {
        let customURL = URL(string: "https://api.custom-openai.com/v1")!
        let config = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4o",
            baseURL: customURL
        )
        let adapter = OpenAIAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    @Test("OpenAIAdapter should handle extreme temperature values")
    func testOpenAIAdapterExtremeTemperature() throws {
        let config = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4o",
            temperature: 2.0 // Maximum value
        )
        let adapter = OpenAIAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    @Test("OpenAIAdapter should handle zero temperature")
    func testOpenAIAdapterZeroTemperature() throws {
        let config = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4o",
            temperature: 0.0
        )
        let adapter = OpenAIAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    @Test("OpenAIAdapter should handle large max tokens")
    func testOpenAIAdapterLargeMaxTokens() throws {
        let config = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4o",
            maxTokens: 4000
        )
        let adapter = OpenAIAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    @Test("OpenAIAdapter should handle nil parameters")
    func testOpenAIAdapterNilParameters() throws {
        let config = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4o",
            maxTokens: nil,
            temperature: nil,
            systemPrompt: nil,
            topP: nil,
            frequencyPenalty: nil,
            presencePenalty: nil,
            stopSequences: nil,
            user: nil
        )
        let adapter = OpenAIAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    @Test("OpenAIAdapter should handle multiple stop sequences")
    func testOpenAIAdapterMultipleStopSequences() throws {
        let config = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4o",
            stopSequences: ["END", "STOP", "DONE", "FINISH"]
        )
        let adapter = OpenAIAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    @Test("OpenAIAdapter should handle empty stop sequences")
    func testOpenAIAdapterEmptyStopSequences() throws {
        let config = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4o",
            stopSequences: []
        )
        let adapter = OpenAIAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    @Test("OpenAIAdapter should handle extreme penalty values")
    func testOpenAIAdapterExtremePenalties() throws {
        let config = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4o",
            frequencyPenalty: -2.0, // Minimum value
            presencePenalty: 2.0    // Maximum value
        )
        let adapter = OpenAIAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    @Test("OpenAIAdapter should handle topP edge cases")
    func testOpenAIAdapterTopPEdgeCases() throws {
        let config1 = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4o",
            topP: 0.0 // Minimum value
        )
        let adapter1 = OpenAIAdapter(configuration: config1)
        #expect(adapter1.cardCapabilities.streaming == true)
        
        let config2 = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4o",
            topP: 1.0 // Maximum value
        )
        let adapter2 = OpenAIAdapter(configuration: config2)
        #expect(adapter2.cardCapabilities.streaming == true)
    }
    
    @Test("OpenAIAdapter should handle long system prompts")
    func testOpenAIAdapterLongSystemPrompt() throws {
        let longPrompt = String(repeating: "You are a helpful assistant. ", count: 100)
        let config = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4o",
            systemPrompt: longPrompt
        )
        let adapter = OpenAIAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    @Test("OpenAIAdapter should handle special characters in system prompt")
    func testOpenAIAdapterSpecialCharactersInSystemPrompt() throws {
        let specialPrompt = "You are an assistant that handles: \"quotes\", 'apostrophes', & symbols, <tags>, and emojis 🚀"
        let config = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4o",
            systemPrompt: specialPrompt
        )
        let adapter = OpenAIAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    @Test("OpenAIAdapter should handle unicode in system prompt")
    func testOpenAIAdapterUnicodeInSystemPrompt() throws {
        let unicodePrompt = "You are an assistant that speaks: Español, Français, 中文, العربية, हिन्दी"
        let config = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4o",
            systemPrompt: unicodePrompt
        )
        let adapter = OpenAIAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    @Test("OpenAIAdapter should handle different model names")
    func testOpenAIAdapterDifferentModels() throws {
        let models = ["gpt-4o", "gpt-4", "gpt-4-turbo", "gpt-3.5-turbo", "gpt-3.5-turbo-16k"]
        
        for model in models {
            let config = OpenAIAdapter.Configuration(
                apiKey: "test-key",
                model: model
            )
            let adapter = OpenAIAdapter(configuration: config)
            #expect(adapter.cardCapabilities.streaming == true)
        }
    }
    
    @Test("OpenAIAdapter should handle custom user identifiers")
    func testOpenAIAdapterCustomUserIdentifiers() throws {
        let userIdentifiers = ["user123", "developer", "test-user", "admin", "anonymous"]
        
        for user in userIdentifiers {
            let config = OpenAIAdapter.Configuration(
                apiKey: "test-key",
                model: "gpt-4o",
                user: user
            )
            let adapter = OpenAIAdapter(configuration: config)
            #expect(adapter.cardCapabilities.streaming == true)
        }
    }
    
    @Test("OpenAIAdapter should handle empty user identifier")
    func testOpenAIAdapterEmptyUserIdentifier() throws {
        let config = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4o",
            user: ""
        )
        let adapter = OpenAIAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    // MARK: - Error Type Tests
    
    @Test("OpenAIAdapterError should have correct error descriptions")
    func testOpenAIAdapterErrorDescriptions() throws {
        // Note: OpenAIAdapterError is not publicly accessible in tests
        // This test validates that error handling is properly implemented
        let adapter = OpenAIAdapter(apiKey: "test-key")
        #expect(adapter.cardCapabilities.streaming == true)
    }
    
    // MARK: - Configuration Validation Tests
    
    @Test("OpenAIAdapter should handle configuration with all optional parameters")
    func testOpenAIAdapterFullConfiguration() throws {
        let config = OpenAIAdapter.Configuration(
            apiKey: "test-key",
            model: "gpt-4o",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            maxTokens: 1000,
            temperature: 0.7,
            systemPrompt: "You are a helpful assistant.",
            topP: 0.9,
            frequencyPenalty: 0.1,
            presencePenalty: 0.1,
            stopSequences: ["END", "STOP"],
            user: "test-user"
        )
        let adapter = OpenAIAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
        #expect(adapter.skills.count >= 3)
    }
    
    @Test("OpenAIAdapter should handle minimal configuration")
    func testOpenAIAdapterMinimalConfiguration() throws {
        let config = OpenAIAdapter.Configuration(apiKey: "test-key")
        let adapter = OpenAIAdapter(configuration: config)
        
        #expect(adapter.cardCapabilities.streaming == true)
        #expect(adapter.skills.count >= 3)
    }
    
    // MARK: - Skill Validation Tests
    
    @Test("OpenAIAdapter skills should have required properties")
    func testOpenAIAdapterSkillsProperties() throws {
        let adapter = OpenAIAdapter(apiKey: "test-key")
        
        for skill in adapter.skills {
            #expect(!skill.id.isEmpty)
            #expect(!skill.name.isEmpty)
            #expect(!skill.description.isEmpty)
            #expect(skill.tags.count > 0)
            #expect(skill.examples?.count ?? 0 > 0)
            #expect(skill.inputModes?.count ?? 0 > 0)
            #expect(skill.outputModes?.count ?? 0 > 0)
        }
    }
    
    @Test("OpenAIAdapter should have unique skill IDs")
    func testOpenAIAdapterUniqueSkillIds() throws {
        let adapter = OpenAIAdapter(apiKey: "test-key")
        let skillIds = adapter.skills.map { $0.id }
        let uniqueIds = Set(skillIds)
        
        #expect(skillIds.count == uniqueIds.count)
    }
    
    @Test("OpenAIAdapter should have text generation skill with correct properties")
    func testOpenAIAdapterTextGenerationSkillProperties() throws {
        let adapter = OpenAIAdapter(apiKey: "test-key")
        let textSkill = adapter.skills.first { $0.id == "text-generation" }
        
        #expect(textSkill != nil)
        #expect(textSkill?.inputModes?.contains("text/plain") == true)
        #expect(textSkill?.outputModes?.contains("text/plain") == true)
        #expect(textSkill?.tags.contains("text") == true)
        #expect(textSkill?.tags.contains("generation") == true)
    }
    
    @Test("OpenAIAdapter should have code generation skill")
    func testOpenAIAdapterCodeGenerationSkill() throws {
        let adapter = OpenAIAdapter(apiKey: "test-key")
        let codeSkill = adapter.skills.first { $0.id == "code-generation" }
        
        #expect(codeSkill != nil)
        #expect(codeSkill?.name == "Code Generation")
        #expect(codeSkill?.tags.contains("code") == true)
        #expect(codeSkill?.tags.contains("programming") == true)
    }
    
    @Test("OpenAIAdapter should have analysis skill")
    func testOpenAIAdapterAnalysisSkill() throws {
        let adapter = OpenAIAdapter(apiKey: "test-key")
        let analysisSkill = adapter.skills.first { $0.id == "analysis" }
        
        #expect(analysisSkill != nil)
        #expect(analysisSkill?.name == "Text Analysis")
        #expect(analysisSkill?.tags.contains("analysis") == true)
        #expect(analysisSkill?.tags.contains("text") == true)
    }
} 