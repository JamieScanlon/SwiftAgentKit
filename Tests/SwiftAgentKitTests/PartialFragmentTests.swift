import Foundation
import Testing
import SwiftAgentKit

@Suite struct PartialFragmentTests {
    @Test("LLMResponse defaults streamingFragment to nil")
    func defaultStreamingFragmentNil() {
        let r = LLMResponse(content: "x", isComplete: false)
        #expect(r.streamingFragment == nil)
    }

    @Test("streamChunk can attach streamingFragment")
    func streamChunkWithFragment() {
        let r = LLMResponse.streamChunk("", streamingFragment: .reasoning("a"))
        #expect(r.isComplete == false)
        #expect(r.streamingFragment == .reasoning("a"))
    }

    @Test("toolCallStarted equality")
    func toolCallStartedEquality() {
        let a = PartialFragment.toolCallStarted(id: "call_1", name: "search", contentIndex: 2)
        let b = PartialFragment.toolCallStarted(id: "call_1", name: "search", contentIndex: 2)
        let c = PartialFragment.toolCallStarted(id: "call_1", name: "search", contentIndex: nil)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("toolCallCompleted equality")
    func toolCallCompletedEquality() {
        let a = PartialFragment.toolCallCompleted(id: "call_1", name: "search", arguments: "{\"q\":\"x\"}")
        let b = PartialFragment.toolCallCompleted(id: "call_1", name: "search", arguments: "{\"q\":\"x\"}")
        let c = PartialFragment.toolCallCompleted(id: "call_1", name: "search", arguments: "{}")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("streamToolCallStarted attaches streamingFragment")
    func streamToolCallStartedHelper() {
        let r = LLMResponse.streamToolCallStarted(id: "call_1", name: "search", contentIndex: 2)
        #expect(r.isComplete == false)
        #expect(r.content == "")
        #expect(r.streamingFragment == .toolCallStarted(id: "call_1", name: "search", contentIndex: 2))
    }

    @Test("streamToolCallCompleted attaches streamingFragment")
    func streamToolCallCompletedHelper() {
        let r = LLMResponse.streamToolCallCompleted(id: "call_1", name: "search", arguments: "{\"q\":\"x\"}")
        #expect(r.isComplete == false)
        #expect(r.content == "")
        #expect(r.streamingFragment == .toolCallCompleted(id: "call_1", name: "search", arguments: "{\"q\":\"x\"}"))
    }

    @Test("toolCallStarted is distinct from toolCall with empty fragment")
    func toolCallStartedDistinctFromEmptyToolCall() {
        let started = PartialFragment.toolCallStarted(id: "call_1", name: "search", contentIndex: nil)
        let emptyDelta = PartialFragment.toolCall(id: "call_1", name: "search", argumentsFragment: "")
        #expect(started != emptyDelta)
    }

    @Test("toolCallCompleted is distinct from toolCall with full JSON fragment")
    func toolCallCompletedDistinctFromFullToolCall() {
        let completed = PartialFragment.toolCallCompleted(id: "call_1", name: "search", arguments: "{\"q\":\"x\"}")
        let fullDelta = PartialFragment.toolCall(id: "call_1", name: "search", argumentsFragment: "{\"q\":\"x\"}")
        #expect(completed != fullDelta)
    }
}
