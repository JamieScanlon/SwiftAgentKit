import Foundation
import Testing
import SwiftAgentKit

@Suite struct OrchestrationObservationTests {
    @Test("OrchestrationObservationCoordinator emits monotonic generation")
    func testSnapshotGenerationMonotonic() async throws {
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
        let hub = AgenticLoopStateHub()
        let coord = OrchestrationObservationCoordinator(llm: llm, agenticLoopStateHub: hub)

        let stream = coord.snapshotUpdates()
        let loopID = AgenticLoopID.orchestratorSession(UUID())

        let collector = Task {
            var previous: UInt64 = 0
            for await event in stream {
                #expect(event.generation > previous)
                previous = event.generation
                if previous >= 3 { break }
            }
        }

        await Task.yield()
        hub.publish(loopID, .started)
        await Task.yield()
        hub.publish(loopID, .completed)
        await collector.value
    }

    @Test("currentSnapshot includes latest agentic and request states")
    func testCurrentSnapshotAggregation() async throws {
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
        let hub = AgenticLoopStateHub()
        let coord = OrchestrationObservationCoordinator(llm: llm, agenticLoopStateHub: hub)
        let loopID = AgenticLoopID.orchestratorSession(UUID())
        hub.publish(loopID, .executingTools)

        let rid = LLMRequestID()
        _ = try await LLMRequestID.$current.withValue(rid) {
            try await llm.send([], config: LLMRequestConfig())
        }

        let snap = coord.currentSnapshot()
        #expect(snap.agenticLoopStates[loopID] == .executingTools)
        #expect(snap.perRequestStates[rid] == .completed)
    }
}
