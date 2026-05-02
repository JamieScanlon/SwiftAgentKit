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
}
