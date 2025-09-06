//
//  MessageFilterTests.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 5/17/25.
//

import Testing
import Foundation
@testable import SwiftAgentKitMCP

struct MessageFilterTests {
    
    @Test("MessageFilter validates JSON-RPC messages correctly")
    func testValidJSONRPCMessages() async throws {
        let filter = MessageFilter()
        
        // Valid JSON-RPC request
        let validRequest = """
        {"jsonrpc": "2.0", "method": "initialize", "params": {}, "id": 1}
        """
        let requestData = validRequest.data(using: .utf8)!
        let filteredRequest = filter.filterMessage(requestData)
        #expect(filteredRequest != nil)
        
        // Valid JSON-RPC response
        let validResponse = """
        {"jsonrpc": "2.0", "result": {"capabilities": {}}, "id": 1}
        """
        let responseData = validResponse.data(using: .utf8)!
        let filteredResponse = filter.filterMessage(responseData)
        #expect(filteredResponse != nil)
        
        // Valid JSON-RPC error
        let validError = """
        {"jsonrpc": "2.0", "error": {"code": -32601, "message": "Method not found"}, "id": 1}
        """
        let errorData = validError.data(using: .utf8)!
        let filteredError = filter.filterMessage(errorData)
        #expect(filteredError != nil)
    }
    
    @Test("MessageFilter rejects non-JSON messages")
    func testNonJSONMessages() async throws {
        let filter = MessageFilter()
        
        // Plain text log message
        let logMessage = "2024-01-01T12:00:00Z [INFO] Server started successfully"
        let logData = logMessage.data(using: .utf8)!
        let filteredLog = filter.filterMessage(logData)
        #expect(filteredLog == nil)
        
        // Invalid JSON
        let invalidJson = "{invalid json content"
        let invalidData = invalidJson.data(using: .utf8)!
        let filteredInvalid = filter.filterMessage(invalidData)
        #expect(filteredInvalid == nil)
    }
    
    @Test("MessageFilter rejects JSON without JSON-RPC structure")
    func testNonJSONRPCMessages() async throws {
        let filter = MessageFilter()
        
        // Valid JSON but not JSON-RPC
        let nonJsonRpc = """
        {"level": "info", "message": "Server started", "timestamp": "2024-01-01T12:00:00Z"}
        """
        let nonJsonRpcData = nonJsonRpc.data(using: .utf8)!
        let filteredNonJsonRpc = filter.filterMessage(nonJsonRpcData)
        #expect(filteredNonJsonRpc == nil)
        
        // JSON with wrong jsonrpc version
        let wrongVersion = """
        {"jsonrpc": "1.0", "method": "initialize", "params": {}, "id": 1}
        """
        let wrongVersionData = wrongVersion.data(using: .utf8)!
        let filteredWrongVersion = filter.filterMessage(wrongVersionData)
        #expect(filteredWrongVersion == nil)
        
        // JSON without required fields
        let missingFields = """
        {"jsonrpc": "2.0", "id": 1}
        """
        let missingFieldsData = missingFields.data(using: .utf8)!
        let filteredMissingFields = filter.filterMessage(missingFieldsData)
        #expect(filteredMissingFields == nil)
    }
    
    @Test("MessageFilter handles multiple messages correctly")
    func testMultipleMessages() async throws {
        let filter = MessageFilter()
        
        // Mix of valid JSON-RPC and log messages
        let mixedMessages = """
        {"jsonrpc": "2.0", "method": "initialize", "params": {}, "id": 1}
        [INFO] Server processing request
        {"jsonrpc": "2.0", "result": {"capabilities": {}}, "id": 1}
        [DEBUG] Request completed successfully
        """
        let mixedData = mixedMessages.data(using: .utf8)!
        let filteredMixed = filter.filterMessage(mixedData)
        #expect(filteredMixed != nil)
        
        let filteredString = String(data: filteredMixed!, encoding: .utf8)!
        let lines = filteredString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        #expect(lines.count == 2) // Only the two JSON-RPC messages should remain
        
        // Verify the filtered content contains only JSON-RPC messages
        for line in lines {
            let data = line.data(using: .utf8)!
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json != nil)
            #expect(json?["jsonrpc"] as? String == "2.0")
        }
    }
    
    @Test("MessageFilter configuration works correctly")
    func testMessageFilterConfiguration() async throws {
        // Test with filtering disabled
        let disabledConfig = MessageFilter.Configuration.disabled
        let disabledFilter = MessageFilter(configuration: disabledConfig)
        
        let logMessage = "[INFO] This should not be filtered when disabled"
        let logData = logMessage.data(using: .utf8)!
        let filteredDisabled = disabledFilter.filterMessage(logData)
        #expect(filteredDisabled != nil) // Should not filter when disabled
        
        // Test with filtering enabled (default)
        let enabledConfig = MessageFilter.Configuration.default
        let enabledFilter = MessageFilter(configuration: enabledConfig)
        
        let filteredEnabled = enabledFilter.filterMessage(logData)
        #expect(filteredEnabled == nil) // Should filter when enabled
    }
    
    @Test("MessageFilter handles empty and whitespace-only messages")
    func testEmptyAndWhitespaceMessages() async throws {
        let filter = MessageFilter()
        
        // Empty data
        let emptyData = Data()
        let filteredEmpty = filter.filterMessage(emptyData)
        #expect(filteredEmpty == nil)
        
        // Whitespace only
        let whitespaceData = "   \n\t  ".data(using: .utf8)!
        let filteredWhitespace = filter.filterMessage(whitespaceData)
        #expect(filteredWhitespace == nil)
        
        // Mixed whitespace and valid message
        let mixedWhitespace = """
        
        {"jsonrpc": "2.0", "method": "test", "id": 1}
        
        """
        let mixedWhitespaceData = mixedWhitespace.data(using: .utf8)!
        let filteredMixedWhitespace = filter.filterMessage(mixedWhitespaceData)
        #expect(filteredMixedWhitespace != nil)
    }
}
