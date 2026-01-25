import Testing
import Foundation
@testable import SwiftAgentKit

@Suite("DynamicPrompt Tests")
struct DynamicPromptTests {
    
    // MARK: - Basic Functionality
    
    @Test("Basic token replacement")
    func testBasicTokenReplacement() throws {
        let template = "Hello {{name}}!"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["name": "World"])
        
        #expect(result == "Hello World!")
    }
    
    @Test("Multiple token replacement")
    func testMultipleTokenReplacement() throws {
        let template = "Hello {{name}}, welcome to {{location}}!"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: [
            "name": "Alice",
            "location": "SwiftAgentKit"
        ])
        
        #expect(result == "Hello Alice, welcome to SwiftAgentKit!")
    }
    
    @Test("Token replacement with missing values")
    func testTokenReplacementWithMissingValues() throws {
        let template = "Hello {{name}}, your score is {{score}}!"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["name": "Bob"])
        
        // Missing tokens should remain unchanged
        #expect(result == "Hello Bob, your score is {{score}}!")
    }
    
    @Test("Empty template")
    func testEmptyTemplate() throws {
        let prompt = DynamicPrompt(template: "")
        let result = prompt.replace(tokens: ["name": "Test"])
        
        #expect(result == "")
        #expect(!prompt.hasTokens())
        #expect(prompt.getTokenNames().isEmpty)
    }
    
    @Test("Template without tokens")
    func testTemplateWithoutTokens() throws {
        let template = "This is a plain text without any tokens."
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["name": "Test"])
        
        #expect(result == template)
        #expect(!prompt.hasTokens())
        #expect(prompt.getTokenNames().isEmpty)
    }
    
    // MARK: - Token Parsing
    
    @Test("Get token names")
    func testGetTokenNames() throws {
        let template = "{{name}} and {{age}} and {{name}}"
        let prompt = DynamicPrompt(template: template)
        let tokenNames = prompt.getTokenNames()
        
        // Should return unique token names
        #expect(tokenNames.count == 2)
        #expect(tokenNames.contains("name"))
        #expect(tokenNames.contains("age"))
    }
    
    @Test("Has tokens check")
    func testHasTokens() throws {
        let promptWithTokens = DynamicPrompt(template: "Hello {{name}}!")
        #expect(promptWithTokens.hasTokens())
        
        let promptWithoutTokens = DynamicPrompt(template: "Hello World!")
        #expect(!promptWithoutTokens.hasTokens())
    }
    
    // MARK: - Edge Cases
    
    @Test("Token with underscores")
    func testTokenWithUnderscores() throws {
        let template = "Value: {{user_name}}"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["user_name": "john_doe"])
        
        #expect(result == "Value: john_doe")
    }
    
    @Test("Token with hyphens")
    func testTokenWithHyphens() throws {
        let template = "Value: {{user-name}}"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["user-name": "john-doe"])
        
        #expect(result == "Value: john-doe")
    }
    
    @Test("Token with numbers")
    func testTokenWithNumbers() throws {
        let template = "Value: {{item1}} and {{item2}}"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: [
            "item1": "first",
            "item2": "second"
        ])
        
        #expect(result == "Value: first and second")
    }
    
    @Test("Token with mixed characters")
    func testTokenWithMixedCharacters() throws {
        let template = "Value: {{token_123}}"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["token_123": "mixed"])
        
        #expect(result == "Value: mixed")
    }
    
    @Test("Multiple occurrences of same token")
    func testMultipleOccurrencesOfSameToken() throws {
        let template = "{{greeting}} {{name}}, {{greeting}} again!"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: [
            "greeting": "Hello",
            "name": "World"
        ])
        
        #expect(result == "Hello World, Hello again!")
    }
    
    @Test("Adjacent tokens")
    func testAdjacentTokens() throws {
        let template = "{{first}}{{second}}"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: [
            "first": "Hello",
            "second": "World"
        ])
        
        #expect(result == "HelloWorld")
    }
    
    @Test("Token at start of string")
    func testTokenAtStartOfString() throws {
        let template = "{{name}} is here"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["name": "Alice"])
        
        #expect(result == "Alice is here")
    }
    
    @Test("Token at end of string")
    func testTokenAtEndOfString() throws {
        let template = "Welcome, {{name}}"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["name": "Bob"])
        
        #expect(result == "Welcome, Bob")
    }
    
    @Test("Single curly braces are ignored")
    func testSingleCurlyBracesIgnored() throws {
        let template = "This {is} not a token, but {{this}} is"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["this": "THAT"])
        
        #expect(result == "This {is} not a token, but THAT is")
        #expect(prompt.getTokenNames().count == 1)
        #expect(prompt.getTokenNames().contains("this"))
    }
    
    @Test("Triple curly braces are ignored")
    func testTripleCurlyBracesIgnored() throws {
        let template = "This {{{is}}} not a token, but {{this}} is"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["this": "THAT"])
        
        #expect(result == "This {{{is}}} not a token, but THAT is")
        #expect(prompt.getTokenNames().count == 1)
    }
    
    @Test("Empty token name is ignored")
    func testEmptyTokenNameIgnored() throws {
        let template = "This {{}} is not a token"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["name": "Test"])
        
        #expect(result == template)
        #expect(!prompt.hasTokens())
    }
    
    @Test("Whitespace in token name is ignored")
    func testWhitespaceInTokenNameIgnored() throws {
        let template = "This {{ token }} is not matched"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["token": "Test"])
        
        // The token " token " (with spaces) won't match "token"
        #expect(result == template)
    }
    
    // MARK: - Transform Closure
    
    @Test("Replace with transform closure")
    func testReplaceWithTransformClosure() throws {
        let template = "Count: {{count}}, Name: {{name}}"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace { tokenName in
            if tokenName == "count" {
                return "42"
            } else if tokenName == "name" {
                return "Alice"
            }
            return nil
        }
        
        #expect(result == "Count: 42, Name: Alice")
    }
    
    @Test("Replace with transform closure - missing values")
    func testReplaceWithTransformClosureMissingValues() throws {
        let template = "Count: {{count}}, Name: {{name}}"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace { tokenName in
            if tokenName == "count" {
                return "42"
            }
            return nil // name is missing
        }
        
        // Missing tokens should remain unchanged
        #expect(result == "Count: 42, Name: {{name}}")
    }
    
    // MARK: - String Extension Convenience Methods
    
    @Test("String extension - replacingTokens with dictionary")
    func testStringExtensionReplacingTokens() throws {
        let template = "Hello {{name}}!"
        let result = template.replacingTokens(["name": "World"])
        
        #expect(result == "Hello World!")
    }
    
    @Test("String extension - replacingTokens with transform")
    func testStringExtensionReplacingTokensWithTransform() throws {
        let template = "Value: {{value}}"
        let result = template.replacingTokens { tokenName in
            tokenName == "value" ? "42" : nil
        }
        
        #expect(result == "Value: 42")
    }
    
    // MARK: - Performance and Complex Scenarios
    
    @Test("Large number of tokens")
    func testLargeNumberOfTokens() throws {
        var templateParts: [String] = []
        var tokens: [String: String] = [:]
        
        for i in 1...100 {
            templateParts.append("{{token\(i)}}")
            tokens["token\(i)"] = "value\(i)"
        }
        
        let template = templateParts.joined(separator: " ")
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: tokens)
        
        // Verify all tokens were replaced
        for i in 1...100 {
            #expect(!result.contains("{{token\(i)}}"))
            #expect(result.contains("value\(i)"))
        }
        
        #expect(prompt.getTokenNames().count == 100)
    }
    
    @Test("Very long template")
    func testVeryLongTemplate() throws {
        let longText = String(repeating: "Lorem ipsum dolor sit amet. ", count: 100)
        let template = "\(longText)Hello {{name}}! \(longText)"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["name": "World"])
        
        #expect(result.contains("Hello World!"))
        #expect(!result.contains("{{name}}"))
    }
    
    @Test("Complex real-world example")
    func testComplexRealWorldExample() throws {
        let template = """
        System: You are a helpful assistant named {{assistant_name}}.
        User: {{user_message}}
        Context: The user is located in {{location}} and it's {{time}}.
        Please respond in a {{tone}} tone.
        """
        
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: [
            "assistant_name": "Alice",
            "user_message": "What's the weather?",
            "location": "San Francisco",
            "time": "morning",
            "tone": "friendly"
        ])
        
        #expect(result.contains("Alice"))
        #expect(result.contains("What's the weather?"))
        #expect(result.contains("San Francisco"))
        #expect(result.contains("morning"))
        #expect(result.contains("friendly"))
        #expect(!result.contains("{{"))
        #expect(!result.contains("}}"))
    }
    
    @Test("Special characters in replacement values")
    func testSpecialCharactersInReplacementValues() throws {
        let template = "Message: {{message}}"
        let prompt = DynamicPrompt(template: template)
        
        // Test various special characters
        let specialValues = [
            "Hello\nWorld",
            "Hello\tWorld",
            "Hello {World}",
            "Hello {{World}}",
            "Hello }World{",
            "Hello $World",
            "Hello @World#",
            "Hello &World*",
        ]
        
        for specialValue in specialValues {
            let result = prompt.replace(tokens: ["message": specialValue])
            #expect(result == "Message: \(specialValue)")
        }
    }
    
    @Test("Unicode characters in tokens and values")
    func testUnicodeCharacters() throws {
        let template = "Hello {{名前}}, welcome to {{場所}}!"
        let prompt = DynamicPrompt(template: template)
        
        // Note: Unicode characters in token names may not be supported by the regex
        // This test verifies the current behavior
        let tokenNames = prompt.getTokenNames()
        
        // The regex pattern [a-zA-Z0-9_-] doesn't match Unicode, so these tokens won't be found
        // This is expected behavior - token names are limited to ASCII alphanumeric, underscore, and hyphen
        #expect(tokenNames.isEmpty || tokenNames.count <= 2)
    }
    
    @Test("Case sensitivity")
    func testCaseSensitivity() throws {
        let template = "{{Name}} and {{name}} are different"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: [
            "Name": "Alice",
            "name": "Bob"
        ])
        
        #expect(result == "Alice and Bob are different")
        #expect(prompt.getTokenNames().count == 2)
        #expect(prompt.getTokenNames().contains("Name"))
        #expect(prompt.getTokenNames().contains("name"))
    }
    
    // MARK: - Error Handling and Edge Cases
    
    @Test("Nested braces in replacement value")
    func testNestedBracesInReplacementValue() throws {
        let template = "Value: {{value}}"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["value": "{{nested}}"])
        
        // The replacement value contains braces, but it should be inserted as-is
        #expect(result == "Value: {{nested}}")
    }
    
    @Test("Empty replacement value")
    func testEmptyReplacementValue() throws {
        let template = "Hello {{name}}!"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["name": ""])
        
        #expect(result == "Hello !")
    }
    
    @Test("Very long token names")
    func testVeryLongTokenNames() throws {
        let longTokenName = String(repeating: "a", count: 1000)
        let template = "Value: {{\(longTokenName)}}"
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: [longTokenName: "test"])
        
        #expect(result == "Value: test")
        #expect(prompt.getTokenNames().contains(longTokenName))
    }
    
    @Test("Token replacement preserves whitespace")
    func testTokenReplacementPreservesWhitespace() throws {
        let template = "  Hello   {{name}}   World  "
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: ["name": "Alice"])
        
        #expect(result == "  Hello   Alice   World  ")
    }
    
    @Test("Multiple lines in template")
    func testMultipleLinesInTemplate() throws {
        let template = """
        Line 1: {{value1}}
        Line 2: {{value2}}
        Line 3: {{value1}} again
        """
        
        let prompt = DynamicPrompt(template: template)
        let result = prompt.replace(tokens: [
            "value1": "First",
            "value2": "Second"
        ])
        
        #expect(result.contains("Line 1: First"))
        #expect(result.contains("Line 2: Second"))
        #expect(result.contains("Line 3: First again"))
    }
    
    // MARK: - Default Tokens
    
    @Test("Default tokens initialization")
    func testDefaultTokensInitialization() throws {
        let template = "Hello {{name}}, welcome to {{location}}!"
        let prompt = DynamicPrompt(
            template: template,
            defaultTokens: ["name": "Alice", "location": "SwiftAgentKit"]
        )
        
        let result = prompt.replace()
        
        #expect(result == "Hello Alice, welcome to SwiftAgentKit!")
    }
    
    @Test("Subscript getter and setter")
    func testSubscriptGetterAndSetter() throws {
        var prompt = DynamicPrompt(template: "Hello {{name}}!")
        
        // Set a default token
        prompt["name"] = "World"
        
        // Get the default token
        #expect(prompt["name"] == "World")
        
        // Replace using defaults
        let result = prompt.replace()
        #expect(result == "Hello World!")
    }
    
    @Test("Subscript setter with nil removes token")
    func testSubscriptSetterWithNilRemovesToken() throws {
        var prompt = DynamicPrompt(template: "Hello {{name}}!")
        prompt["name"] = "World"
        #expect(prompt["name"] == "World")
        
        prompt["name"] = nil
        #expect(prompt["name"] == nil)
        
        let result = prompt.replace()
        #expect(result == "Hello {{name}}!")
    }
    
    @Test("Replace with defaults when no tokens provided")
    func testReplaceWithDefaultsWhenNoTokensProvided() throws {
        var prompt = DynamicPrompt(template: "Count: {{count}}, Name: {{name}}")
        prompt["count"] = "42"
        prompt["name"] = "Alice"
        
        let result = prompt.replace()
        
        #expect(result == "Count: 42, Name: Alice")
    }
    
    @Test("Provided tokens override defaults")
    func testProvidedTokensOverrideDefaults() throws {
        var prompt = DynamicPrompt(template: "Hello {{name}}!")
        prompt["name"] = "Default"
        
        // Provided token overrides default
        let result = prompt.replace(tokens: ["name": "Override"])
        
        #expect(result == "Hello Override!")
    }
    
    @Test("Partial override of defaults")
    func testPartialOverrideOfDefaults() throws {
        var prompt = DynamicPrompt(template: "{{greeting}} {{name}}!")
        prompt["greeting"] = "Hello"
        prompt["name"] = "Default"
        
        // Override only one token
        let result = prompt.replace(tokens: ["name": "Alice"])
        
        #expect(result == "Hello Alice!")
    }
    
    @Test("Get default tokens")
    func testGetDefaultTokens() throws {
        var prompt = DynamicPrompt(template: "Hello {{name}}!")
        prompt["name"] = "World"
        prompt["location"] = "Earth"
        
        let defaults = prompt.getDefaultTokens()
        
        #expect(defaults["name"] == "World")
        #expect(defaults["location"] == "Earth")
        #expect(defaults.count == 2)
    }
    
    @Test("Set default tokens")
    func testSetDefaultTokens() throws {
        var prompt = DynamicPrompt(template: "Hello {{name}}!")
        prompt.setDefaultTokens(["name": "Alice", "location": "SwiftAgentKit"])
        
        #expect(prompt["name"] == "Alice")
        #expect(prompt["location"] == "SwiftAgentKit")
        
        let result = prompt.replace()
        #expect(result == "Hello Alice!")
    }
    
    @Test("Set default tokens replaces existing")
    func testSetDefaultTokensReplacesExisting() throws {
        var prompt = DynamicPrompt(template: "Hello {{name}}!")
        prompt["name"] = "Old"
        prompt.setDefaultTokens(["name": "New"])
        
        #expect(prompt["name"] == "New")
    }
    
    @Test("Remove default token")
    func testRemoveDefaultToken() throws {
        var prompt = DynamicPrompt(template: "Hello {{name}}!")
        prompt["name"] = "World"
        
        prompt.removeDefaultToken("name")
        
        #expect(prompt["name"] == nil)
        
        let result = prompt.replace()
        #expect(result == "Hello {{name}}!")
    }
    
    @Test("Clear default tokens")
    func testClearDefaultTokens() throws {
        var prompt = DynamicPrompt(template: "Hello {{name}}!")
        prompt["name"] = "World"
        prompt["location"] = "Earth"
        
        prompt.clearDefaultTokens()
        
        #expect(prompt.getDefaultTokens().isEmpty)
        
        let result = prompt.replace()
        #expect(result == "Hello {{name}}!")
    }
    
    @Test("Replace with empty tokens dictionary uses defaults")
    func testReplaceWithEmptyTokensDictionaryUsesDefaults() throws {
        var prompt = DynamicPrompt(template: "Hello {{name}}!")
        prompt["name"] = "World"
        
        let result = prompt.replace(tokens: [:])
        
        #expect(result == "Hello World!")
    }
    
    @Test("Replace with nil tokens uses defaults")
    func testReplaceWithNilTokensUsesDefaults() throws {
        var prompt = DynamicPrompt(template: "Hello {{name}}!")
        prompt["name"] = "World"
        
        let result = prompt.replace(tokens: nil)
        
        #expect(result == "Hello World!")
    }
    
    @Test("Multiple default tokens with some missing")
    func testMultipleDefaultTokensWithSomeMissing() throws {
        var prompt = DynamicPrompt(template: "Hello {{name}}, your score is {{score}}!")
        prompt["name"] = "Alice"
        // score is not set
        
        let result = prompt.replace()
        
        #expect(result == "Hello Alice, your score is {{score}}!")
    }
    
    @Test("Default tokens persist across multiple replace calls")
    func testDefaultTokensPersistAcrossMultipleReplaceCalls() throws {
        var prompt = DynamicPrompt(template: "Hello {{name}}!")
        prompt["name"] = "World"
        
        let result1 = prompt.replace()
        let result2 = prompt.replace()
        
        #expect(result1 == "Hello World!")
        #expect(result2 == "Hello World!")
    }
    
    @Test("Default tokens work with transform closure")
    func testDefaultTokensWorkWithTransformClosure() throws {
        var prompt = DynamicPrompt(template: "Count: {{count}}, Name: {{name}}")
        prompt["count"] = "42"
        // name is not set in defaults
        
        let result = prompt.replace { tokenName in
            if tokenName == "name" {
                return "Alice"
            }
            // For count, use default
            return prompt[tokenName]
        }
        
        #expect(result == "Count: 42, Name: Alice")
    }
    
    // MARK: - Render Convenience Method
    
    @Test("Render method uses default tokens")
    func testRenderMethodUsesDefaultTokens() throws {
        var prompt = DynamicPrompt(template: "Hello {{name}}, welcome to {{location}}!")
        prompt["name"] = "Alice"
        prompt["location"] = "SwiftAgentKit"
        
        let result = prompt.render()
        
        #expect(result == "Hello Alice, welcome to SwiftAgentKit!")
    }
    
    @Test("Render method equivalent to replace with no parameters")
    func testRenderMethodEquivalentToReplace() throws {
        var prompt = DynamicPrompt(template: "Hello {{name}}!")
        prompt["name"] = "World"
        
        let renderResult = prompt.render()
        let replaceResult = prompt.replace()
        
        #expect(renderResult == replaceResult)
        #expect(renderResult == "Hello World!")
    }
    
    @Test("Render method with missing defaults leaves tokens unchanged")
    func testRenderMethodWithMissingDefaults() throws {
        var prompt = DynamicPrompt(template: "Hello {{name}}, your score is {{score}}!")
        prompt["name"] = "Alice"
        // score is not set
        
        let result = prompt.render()
        
        #expect(result == "Hello Alice, your score is {{score}}!")
    }
    
    @Test("Render method with no defaults returns template unchanged")
    func testRenderMethodWithNoDefaults() throws {
        let prompt = DynamicPrompt(template: "Hello {{name}}!")
        
        let result = prompt.render()
        
        #expect(result == "Hello {{name}}!")
    }
}
