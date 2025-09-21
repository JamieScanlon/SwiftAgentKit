//
//  ResourceIndicatorUtilitiesTests.swift
//  SwiftAgentKitTests
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Testing
import Foundation
@testable import SwiftAgentKit

/// Tests for RFC 8707 Resource Indicators for OAuth 2.0 implementation
struct ResourceIndicatorUtilitiesTests {
    
    // MARK: - Canonical URI Validation Tests
    
    @Test("Valid canonical URIs should be normalized correctly")
    func testValidCanonicalURIs() throws {
        let testCases: [(input: String, expected: String)] = [
            // Basic cases
            ("https://mcp.example.com/mcp", "https://mcp.example.com/mcp"),
            ("https://mcp.example.com", "https://mcp.example.com"),
            ("https://mcp.example.com:8443", "https://mcp.example.com:8443"),
            ("https://mcp.example.com/server/mcp", "https://mcp.example.com/server/mcp"),
            
            // Normalization cases
            ("HTTPS://MCP.EXAMPLE.COM/MCP", "https://mcp.example.com/MCP"), // scheme and host lowercase
            ("https://MCP.EXAMPLE.COM:8443/MCP", "https://mcp.example.com:8443/MCP"),
            
            // Trailing slash handling
            ("https://mcp.example.com/", "https://mcp.example.com"),
            ("https://mcp.example.com/mcp/", "https://mcp.example.com/mcp"),
            
            // Default port removal
            ("https://mcp.example.com:443", "https://mcp.example.com"),
            ("http://mcp.example.com:80", "http://mcp.example.com"),
            
            // Query parameters
            ("https://mcp.example.com/mcp?version=1.0", "https://mcp.example.com/mcp?version=1.0"),
            ("https://mcp.example.com?api=v2", "https://mcp.example.com?api=v2")
        ]
        
        for (input, expected) in testCases {
            let result = try ResourceIndicatorUtilities.canonicalizeResourceURI(input)
            #expect(result == expected, "Input: \(input), Expected: \(expected), Got: \(result)")
        }
    }
    
    @Test("Invalid URIs should throw appropriate errors")
    func testInvalidCanonicalURIs() {
        let invalidURIs = [
            "mcp.example.com", // Missing scheme
            "://mcp.example.com", // Empty scheme
            "https://", // Missing host
            "https:///mcp", // Missing host
            "https://mcp.example.com#fragment", // Contains fragment
            "https://mcp.example.com/mcp#section", // Contains fragment with path
            "not-a-uri", // Invalid format
            "", // Empty string
            "ftp://mcp.example.com" // Valid URI but we might want to restrict schemes
        ]
        
        for invalidURI in invalidURIs {
            #expect(throws: ResourceIndicatorError.self) {
                try ResourceIndicatorUtilities.canonicalizeResourceURI(invalidURI)
            }
        }
    }
    
    @Test("URI validation helper should work correctly")
    func testIsValidResourceURI() {
        let validURIs = [
            "https://mcp.example.com/mcp",
            "https://mcp.example.com",
            "http://localhost:8080/api",
            "https://api.example.com:9443/v1/mcp"
        ]
        
        let invalidURIs = [
            "mcp.example.com",
            "https://mcp.example.com#fragment",
            "not-a-uri",
            ""
        ]
        
        for uri in validURIs {
            #expect(ResourceIndicatorUtilities.isValidResourceURI(uri), "Should be valid: \(uri)")
        }
        
        for uri in invalidURIs {
            #expect(!ResourceIndicatorUtilities.isValidResourceURI(uri), "Should be invalid: \(uri)")
        }
    }
    
    // MARK: - Resource Parameter Creation Tests
    
    @Test("Resource parameter encoding should work correctly")
    func testCreateResourceParameter() {
        let testCases: [(input: String, expectedContains: String)] = [
            ("https://mcp.example.com/mcp", "https%3A%2F%2Fmcp.example.com%2Fmcp"),
            ("https://mcp.example.com", "https%3A%2F%2Fmcp.example.com"),
            ("https://mcp.example.com:8443/api", "https%3A%2F%2Fmcp.example.com%3A8443%2Fapi"),
            ("https://mcp.example.com/path?query=value", "query%3Dvalue")
        ]
        
        for (input, expectedContains) in testCases {
            let result = ResourceIndicatorUtilities.createResourceParameter(canonicalURI: input)
            #expect(result.contains(expectedContains), "Input: \(input), Expected to contain: \(expectedContains), Got: \(result)")
        }
    }
    
    // MARK: - MCP Server URI Extraction Tests
    
    @Test("MCP server canonical URI extraction should work correctly")
    func testExtractMCPServerCanonicalURI() throws {
        let testCases: [(input: String, expected: String)] = [
            // Basic MCP server URLs
            ("https://mcp.example.com/mcp", "https://mcp.example.com/mcp"),
            ("https://mcp.example.com", "https://mcp.example.com"),
            ("https://api.example.com:8443/v1/mcp", "https://api.example.com:8443/v1/mcp"),
            
            // URLs with trailing slashes
            ("https://mcp.example.com/", "https://mcp.example.com"),
            ("https://mcp.example.com/mcp/", "https://mcp.example.com/mcp"),
            
            // URLs with query parameters
            ("https://mcp.example.com/mcp?version=1.0", "https://mcp.example.com/mcp?version=1.0")
        ]
        
        for (input, expected) in testCases {
            guard let url = URL(string: input) else {
                Issue.record("Invalid URL: \(input)")
                continue
            }
            
            let result = try ResourceIndicatorUtilities.extractMCPServerCanonicalURI(from: url)
            #expect(result == expected, "Input: \(input), Expected: \(expected), Got: \(result)")
        }
    }
    
    @Test("MCP server URI extraction should handle edge cases")
    func testExtractMCPServerCanonicalURIEdgeCases() throws {
        // Test with localhost
        let localhostURL = URL(string: "http://localhost:8080/mcp")!
        let result = try ResourceIndicatorUtilities.extractMCPServerCanonicalURI(from: localhostURL)
        #expect(result == "http://localhost:8080/mcp")
        
        // Test with IP address
        let ipURL = URL(string: "https://192.168.1.100:9443/api/mcp")!
        let ipResult = try ResourceIndicatorUtilities.extractMCPServerCanonicalURI(from: ipURL)
        #expect(ipResult == "https://192.168.1.100:9443/api/mcp")
        
        // Test with complex path
        let complexURL = URL(string: "https://api.example.com/v2/services/mcp/endpoint")!
        let complexResult = try ResourceIndicatorUtilities.extractMCPServerCanonicalURI(from: complexURL)
        #expect(complexResult == "https://api.example.com/v2/services/mcp/endpoint")
    }
    
    // MARK: - Error Handling Tests
    
    @Test("ResourceIndicatorError should provide meaningful descriptions")
    func testErrorDescriptions() {
        let invalidURIError = ResourceIndicatorError.invalidURI("Test message")
        #expect(invalidURIError.localizedDescription.contains("Invalid resource URI"))
        #expect(invalidURIError.localizedDescription.contains("Test message"))
        
        let canonicalizationError = ResourceIndicatorError.canonicalizationFailed("Canonicalization message")
        #expect(canonicalizationError.localizedDescription.contains("Failed to canonicalize URI"))
        #expect(canonicalizationError.localizedDescription.contains("Canonicalization message"))
    }
    
    // MARK: - RFC 8707 Compliance Tests
    
    @Test("RFC 8707 examples should be handled correctly")
    func testRFC8707Examples() throws {
        // Examples from RFC 8707
        let validExamples = [
            "https://mcp.example.com/mcp",
            "https://mcp.example.com",
            "https://mcp.example.com:8443",
            "https://mcp.example.com/server/mcp"
        ]
        
        for example in validExamples {
            let result = try ResourceIndicatorUtilities.canonicalizeResourceURI(example)
            #expect(ResourceIndicatorUtilities.isValidResourceURI(result))
            
            // Should not contain fragments
            #expect(!result.contains("#"))
            
            // Should have lowercase scheme and host (if applicable)
            if let url = URL(string: result) {
                #expect(url.scheme?.lowercased() == url.scheme)
                #expect(url.host?.lowercased() == url.host)
            }
        }
        
        // Invalid examples from RFC 8707
        let invalidExamples = [
            "mcp.example.com", // missing scheme
            "https://mcp.example.com#fragment" // contains fragment
        ]
        
        for example in invalidExamples {
            #expect(throws: ResourceIndicatorError.self) {
                try ResourceIndicatorUtilities.canonicalizeResourceURI(example)
            }
        }
    }
    
    @Test("Interoperability with uppercase schemes and hosts")
    func testInteroperability() throws {
        // RFC 8707 states implementations SHOULD accept uppercase for robustness
        let testCases: [(input: String, expected: String)] = [
            ("HTTPS://MCP.EXAMPLE.COM", "https://mcp.example.com"),
            ("HTTP://LOCALHOST:8080", "http://localhost:8080"),
            ("https://API.EXAMPLE.COM:9443/MCP", "https://api.example.com:9443/MCP") // Path case preserved
        ]
        
        for (input, expected) in testCases {
            let result = try ResourceIndicatorUtilities.canonicalizeResourceURI(input)
            #expect(result == expected, "Input: \(input), Expected: \(expected), Got: \(result)")
        }
    }
}
