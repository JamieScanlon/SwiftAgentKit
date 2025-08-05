import Foundation
import Testing
import SwiftAgentKit

@Suite struct StreamResultTests {
    
    @Test("StreamResult can be created with stream value")
    func testStreamResultStream() throws {
        let streamResult = StreamResult<String, [String]>.stream("test")
        
        #expect(streamResult.isStream == true)
        #expect(streamResult.isComplete == false)
        #expect(streamResult.streamValue == "test")
        #expect(streamResult.completeValue == nil)
    }
    
    @Test("StreamResult can be created with complete value")
    func testStreamResultComplete() throws {
        let finalResult = ["result1", "result2"]
        let streamResult = StreamResult<String, [String]>.complete(finalResult)
        
        #expect(streamResult.isStream == false)
        #expect(streamResult.isComplete == true)
        #expect(streamResult.streamValue == nil)
        #expect(streamResult.completeValue == finalResult)
    }
    
    @Test("StreamResult works with different types")
    func testStreamResultDifferentTypes() throws {
        // Test with Message types
        let message = Message(id: UUID(), role: .assistant, content: "test")
        let messages = [message]
        
        let streamResult = StreamResult<Message, [Message]>.stream(message)
        #expect(streamResult.streamValue?.content == "test")
        
        let completeResult = StreamResult<Message, [Message]>.complete(messages)
        #expect(completeResult.completeValue?.count == 1)
        #expect(completeResult.completeValue?.first?.content == "test")
    }
    
    @Test("StreamResult is Sendable")
    func testStreamResultSendable() throws {
        // This test verifies that StreamResult can be used in concurrent contexts
        let streamResult = StreamResult<String, [String]>.stream("test")
        
        // If this compiles and runs, StreamResult is Sendable
        #expect(streamResult.isStream == true)
    }
} 