import Testing
import Foundation
@testable import SwiftAgentKit

@Suite("SSEParser Tests")
struct SSEParserTests {
    
    // MARK: - Basic Parsing Tests
    
    @Test("Parse single SSE message")
    func testParseSingleMessage() async throws {
        let parser = SSEParser()
        let sseData = "data: {\"message\":\"hello\"}\n\n".data(using: .utf8)!
        
        let messages = await parser.appendChunk(sseData)
        
        #expect(messages.count == 1)
        #expect(messages[0]["message"] as? String == "hello")
    }
    
    @Test("Parse multiple SSE messages")
    func testParseMultipleMessages() async throws {
        let parser = SSEParser()
        // Note: Triple-quoted strings add a trailing newline, so we need explicit \n\n for the last message
        let sseData = """
        data: {"id":1,"text":"first"}
        
        data: {"id":2,"text":"second"}
        
        data: {"id":3,"text":"third"}
        
        """.data(using: .utf8)!
        
        let messages = await parser.appendChunk(sseData)
        
        // First two messages end with \n\n, third ends with \n (from closing """)
        // So we get 2 complete messages, then finalize to get the third
        #expect(messages.count == 2)
        #expect(messages[0]["id"] as? Int == 1)
        #expect(messages[0]["text"] as? String == "first")
        #expect(messages[1]["id"] as? Int == 2)
        
        // Finalize to get the last message
        let finalMessages = await parser.finalize()
        #expect(finalMessages.count == 1)
        #expect(finalMessages[0]["id"] as? Int == 3)
    }
    
    @Test("Parse incremental chunks")
    func testParseIncrementalChunks() async throws {
        let parser = SSEParser()
        
        // First chunk - partial message
        let chunk1 = "data: {\"id\":1,\"text\":\"hello".data(using: .utf8)!
        let messages1 = await parser.appendChunk(chunk1)
        #expect(messages1.isEmpty) // No complete message yet
        
        // Second chunk - completes message
        let chunk2 = " world\"}\n\n".data(using: .utf8)!
        let messages2 = await parser.appendChunk(chunk2)
        #expect(messages2.count == 1)
        #expect(messages2[0]["text"] as? String == "hello world")
    }
    
    // MARK: - Edge Cases
    
    @Test("Handle UTF-8 character boundaries")
    func testUTF8CharacterBoundaries() async throws {
        let parser = SSEParser()
        
        // Emoji is 4 bytes in UTF-8 - split across chunks
        let emoji = "😀"
        let emojiBytes = emoji.data(using: .utf8)!
        
        // Split emoji bytes across chunks
        let chunk1 = "data: {\"text\":\"".data(using: .utf8)! + emojiBytes.prefix(2)
        let chunk2 = emojiBytes.suffix(2) + "\"}\n\n".data(using: .utf8)!
        
        let messages1 = await parser.appendChunk(chunk1)
        #expect(messages1.isEmpty) // Incomplete UTF-8 sequence
        
        let messages2 = await parser.appendChunk(chunk2)
        #expect(messages2.count == 1)
        #expect(messages2[0]["text"] as? String == emoji)
    }
    
    @Test("Handle multi-line data fields")
    func testMultiLineDataFields() async throws {
        let parser = SSEParser()
        let sseData = """
        data: {"line1":"first"}
        data: {"line2":"second"}
        
        """.data(using: .utf8)!
        
        let messages = await parser.appendChunk(sseData)
        
        // Multi-line data fields should be joined with \n
        // But this creates invalid JSON, so parser should handle gracefully
        #expect(messages.count == 0) // Invalid JSON, should be skipped
    }
    
    @Test("Handle empty data field")
    func testEmptyDataField() async throws {
        let parser = SSEParser()
        let sseData = "data:\n\n".data(using: .utf8)!
        
        let messages = await parser.appendChunk(sseData)
        
        // Empty data field should result in no message
        #expect(messages.isEmpty)
    }
    
    @Test("Handle message without trailing newlines")
    func testMessageWithoutTrailingNewlines() async throws {
        let parser = SSEParser()
        let sseData = "data: {\"message\":\"test\"}".data(using: .utf8)!
        
        let messages1 = await parser.appendChunk(sseData)
        #expect(messages1.isEmpty) // No complete message yet
        
        // Finalize should handle remaining data
        let finalMessages = await parser.finalize()
        #expect(finalMessages.count == 1)
        #expect(finalMessages[0]["message"] as? String == "test")
    }
    
    @Test("Handle multiple messages across chunks")
    func testMultipleMessagesAcrossChunks() async throws {
        let parser = SSEParser()
        
        // First chunk - complete message + partial second
        let chunk1 = """
        data: {"id":1}
        
        data: {"id":2,"text":"incomplete
        """.data(using: .utf8)!
        
        let messages1 = await parser.appendChunk(chunk1)
        #expect(messages1.count == 1)
        if messages1.count == 1 {
            #expect(messages1[0]["id"] as? Int == 1)
        }
        
        // Second chunk - completes second message
        // Note: chunk2 ends with \n (from closing """), not \n\n, so we need to finalize
        let chunk2 = """
        message"}
        
        """.data(using: .utf8)!
        
        let messages2 = await parser.appendChunk(chunk2)
        // chunk2 doesn't end with \n\n, so message isn't complete yet
        #expect(messages2.count == 0)
        
        // Finalize to get the complete message
        let finalMessages = await parser.finalize()
        #expect(finalMessages.count == 1)
        if finalMessages.count == 1 {
            #expect(finalMessages[0]["id"] as? Int == 2)
            // Note: chunk1 ends with "incomplete and chunk2 starts with message", so combined it's "incompletemessage"
            #expect(finalMessages[0]["text"] as? String == "incompletemessage")
        }
    }
    
    @Test("Handle event and id fields")
    func testEventAndIdFields() async throws {
        let parser = SSEParser()
        // Triple-quoted string adds trailing newline, so message ends with \n (not \n\n)
        // Need to add explicit \n\n for proper SSE format
        let sseData = """
        event: message
        id: 123
        data: {"content":"test"}
        
        
        """.data(using: .utf8)!
        
        let messages = await parser.appendChunk(sseData)
        
        // Message should be parsed (now ends with \n\n)
        #expect(messages.count == 1)
        if messages.count == 1 {
            #expect(messages[0]["content"] as? String == "test")
            #expect(messages[0]["_sse_event"] as? String == "message")
            #expect(messages[0]["_sse_id"] as? String == "123")
        }
    }
    
    @Test("Handle comment lines")
    func testCommentLines() async throws {
        let parser = SSEParser()
        // Triple-quoted string adds trailing newline, so message ends with \n (not \n\n)
        // Need to add explicit \n\n for proper SSE format
        let sseData = """
        : this is a comment
        data: {"message":"hello"}
        : another comment
        
        
        """.data(using: .utf8)!
        
        let messages = await parser.appendChunk(sseData)
        
        // Message should be parsed (now ends with \n\n)
        #expect(messages.count == 1)
        if messages.count == 1 {
            #expect(messages[0]["message"] as? String == "hello")
        }
    }
    
    @Test("Handle invalid JSON")
    func testInvalidJSON() async throws {
        let parser = SSEParser()
        let sseData = "data: {invalid json}\n\n".data(using: .utf8)!
        
        let messages = await parser.appendChunk(sseData)
        
        // Invalid JSON should be skipped
        #expect(messages.isEmpty)
    }
    
    @Test("Handle empty buffer")
    func testEmptyBuffer() async throws {
        let parser = SSEParser()
        let emptyData = Data()
        
        let messages = await parser.appendChunk(emptyData)
        #expect(messages.isEmpty)
        
        let finalMessages = await parser.finalize()
        #expect(finalMessages.isEmpty)
    }
    
    @Test("Reset parser")
    func testResetParser() async throws {
        let parser = SSEParser()
        let sseData = "data: {\"message\":\"test\"}\n\n".data(using: .utf8)!
        
        let messages1 = await parser.appendChunk(sseData)
        #expect(messages1.count == 1)
        
        await parser.reset()
        
        // After reset, buffer should be empty
        let finalMessages = await parser.finalize()
        #expect(finalMessages.isEmpty)
    }
    
    // MARK: - Real-world Scenarios
    
    @Test("LM Studio streaming pattern")
    func testLMStudioStreamingPattern() async throws {
        let parser = SSEParser()
        // Triple-quoted string adds trailing newline, so first two messages end with \n\n
        let sseData = """
        data: {"choices":[{"delta":{"content":"I"}}]}
        
        data: {"choices":[{"delta":{"content":" need"}}]}
        
        data: {"choices":[{"delta":{"content":" to help"}}]}
        
        """.data(using: .utf8)!
        
        let messages = await parser.appendChunk(sseData)
        
        // First two messages end with \n\n, third ends with \n
        #expect(messages.count == 2)
        if messages.count >= 2 {
            // Each message should contain only the delta content
            if let choices1 = messages[0]["choices"] as? [[String: Any]],
               let delta1 = choices1.first?["delta"] as? [String: Any] {
                #expect(delta1["content"] as? String == "I")
            }
            
            if let choices2 = messages[1]["choices"] as? [[String: Any]],
               let delta2 = choices2.first?["delta"] as? [String: Any] {
                #expect(delta2["content"] as? String == " need")
            }
        }
        
        // Finalize to get the last message
        let finalMessages = await parser.finalize()
        #expect(finalMessages.count == 1)
        if let choices3 = finalMessages[0]["choices"] as? [[String: Any]],
           let delta3 = choices3.first?["delta"] as? [String: Any] {
            #expect(delta3["content"] as? String == " to help")
        }
    }
    
    @Test("Large message handling")
    func testLargeMessage() async throws {
        let parser = SSEParser()
        let largeContent = String(repeating: "a", count: 10000)
        let sseData = "data: {\"content\":\"\(largeContent)\"}\n\n".data(using: .utf8)!
        
        let messages = await parser.appendChunk(sseData)
        
        #expect(messages.count == 1)
        #expect((messages[0]["content"] as? String)?.count == 10000)
    }
    
    @Test("Rapid successive messages")
    func testRapidSuccessiveMessages() async throws {
        let parser = SSEParser()
        
        // Send many small messages rapidly
        var allMessages: [[String: Sendable]] = []
        for i in 1...100 {
            let sseData = "data: {\"id\":\(i)}\n\n".data(using: .utf8)!
            let messages = await parser.appendChunk(sseData)
            allMessages.append(contentsOf: messages)
        }
        
        #expect(allMessages.count == 100)
        #expect((allMessages.last?["id"] as? Int) == 100)
    }
}

@Suite("SSEJSONParser Tests")
struct SSEJSONParserTests {
    
    @Test("Parse single SSE message to JSON")
    func testParseSingleMessage() async throws {
        let parser = SSEJSONParser()
        let sseData = "data: {\"message\":\"hello\"}\n\n".data(using: .utf8)!
        
        let messages = await parser.appendChunk(sseData)
        
        #expect(messages.count == 1)
        if case .object(let dict) = messages[0],
           case .string(let message) = dict["message"] {
            #expect(message == "hello")
        } else {
            Issue.record("Failed to parse message")
        }
    }
    
    @Test("Parse multiple SSE messages to JSON")
    func testParseMultipleMessages() async throws {
        let parser = SSEJSONParser()
        // Triple-quoted string adds trailing newline, so first message ends with \n\n
        let sseData = """
        data: {"id":1,"text":"first"}
        
        data: {"id":2,"text":"second"}
        
        """.data(using: .utf8)!
        
        let messages = await parser.appendChunk(sseData)
        
        // First message ends with \n\n, second ends with \n
        #expect(messages.count == 1)
        if messages.count >= 1 {
            if case .object(let dict1) = messages[0],
               case .integer(let id1) = dict1["id"],
               case .string(let text1) = dict1["text"] {
                #expect(id1 == 1)
                #expect(text1 == "first")
            } else {
                Issue.record("Failed to parse first message")
            }
        }
        
        // Finalize to get the second message
        let finalMessages = await parser.finalize()
        #expect(finalMessages.count == 1)
        if case .object(let dict2) = finalMessages[0],
           case .integer(let id2) = dict2["id"],
           case .string(let text2) = dict2["text"] {
            #expect(id2 == 2)
            #expect(text2 == "second")
        }
    }
    
    @Test("Handle incremental chunks with JSON parser")
    func testIncrementalChunks() async throws {
        let parser = SSEJSONParser()
        
        let chunk1 = "data: {\"id\":1,\"text\":\"hello".data(using: .utf8)!
        let messages1 = await parser.appendChunk(chunk1)
        #expect(messages1.isEmpty)
        
        let chunk2 = " world\"}\n\n".data(using: .utf8)!
        let messages2 = await parser.appendChunk(chunk2)
        #expect(messages2.count == 1)
        
        if case .object(let dict) = messages2[0],
           case .string(let text) = dict["text"] {
            #expect(text == "hello world")
        } else {
            Issue.record("Failed to parse incremental message")
        }
    }
    
    @Test("Finalize with JSON parser")
    func testFinalizeJSONParser() async throws {
        let parser = SSEJSONParser()
        let sseData = "data: {\"message\":\"test\"}".data(using: .utf8)!
        
        let messages1 = await parser.appendChunk(sseData)
        #expect(messages1.isEmpty)
        
        let finalMessages = await parser.finalize()
        #expect(finalMessages.count == 1)
        
        if case .object(let dict) = finalMessages[0],
           case .string(let message) = dict["message"] {
            #expect(message == "test")
        } else {
            Issue.record("Failed to parse finalized message")
        }
    }
}

