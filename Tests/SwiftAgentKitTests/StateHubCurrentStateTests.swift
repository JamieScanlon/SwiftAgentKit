import Foundation
import Testing
import SwiftAgentKit

@Suite struct StateHubCurrentStateTests {
    @Test("LLMRequestStateHub records currentState and currentStates")
    func testLLMRequestStateHubSnapshot() {
        let hub = LLMRequestStateHub()
        let id = LLMRequestID()
        #expect(hub.currentState(for: id) == nil)
        #expect(hub.currentStates.isEmpty)

        hub.publish(id, .active)
        #expect(hub.currentState(for: id) == .active)
        #expect(hub.currentStates[id] == .active)
        #expect(hub.currentStates.count == 1)

        hub.publish(id, .completed)
        #expect(hub.currentState(for: id) == .completed)
        #expect(hub.currentStates[id] == .completed)
    }

    @Test("AgenticLoopStateHub records currentState and currentStates")
    func testAgenticLoopStateHubSnapshot() {
        let hub = AgenticLoopStateHub()
        let id = AgenticLoopID.orchestratorSession(UUID())
        #expect(hub.currentState(for: id) == nil)
        #expect(hub.currentStates.isEmpty)

        hub.publish(id, .started)
        #expect(hub.currentState(for: id) == .started)

        hub.publish(id, .executingTools)
        #expect(hub.currentState(for: id) == .executingTools)
        #expect(hub.currentStates[id] == .executingTools)
    }

    @Test("StatefulLLM forwards currentRequestState to effective hub")
    func testStatefulLLMCurrentRequestState() async throws {
        struct MinimalLLM: LLMProtocol {
            func getModelName() -> String { "minimal" }
            func getCapabilities() -> [LLMCapability] { [.completion] }
            func send(_ messages: [Message], config: LLMRequestConfig) async throws -> LLMResponse {
                .complete(content: "ok")
            }
            func stream(_ messages: [Message], config: LLMRequestConfig) -> AsyncThrowingStream<StreamResult<LLMResponse, LLMResponse>, Error> {
                AsyncThrowingStream { $0.finish() }
            }
        }

        let llm = StatefulLLM(baseLLM: MinimalLLM())
        let rid = LLMRequestID()
        _ = try await LLMRequestID.$current.withValue(rid) {
            try await llm.send([], config: LLMRequestConfig())
        }
        #expect(llm.currentRequestState(for: rid) == .completed)
        #expect(llm.currentRequestStates[rid] == .completed)
    }
}
