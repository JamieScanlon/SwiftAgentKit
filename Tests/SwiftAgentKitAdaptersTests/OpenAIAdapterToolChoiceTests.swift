//
//  OpenAIAdapterToolChoiceTests.swift
//  SwiftAgentKitAdaptersTests
//

import Foundation
import Testing
import SwiftAgentKit
import OpenAI
@testable import SwiftAgentKitAdapters

@Suite("OpenAIAdapter tool-choice translation")
struct OpenAIAdapterToolChoiceTests {

    @Test("ToolInvocationPolicy maps to OpenAI tool_choice")
    func testToolChoiceMapping() throws {
        #expect(OpenAIAdapter.toolChoiceForOpenAI(policy: .automatic, toolsNonEmpty: true) == .auto)
        #expect(OpenAIAdapter.toolChoiceForOpenAI(policy: .required, toolsNonEmpty: true) == .required)
        #expect(OpenAIAdapter.toolChoiceForOpenAI(policy: .none, toolsNonEmpty: true) == ChatQuery.ChatCompletionFunctionCallOptionParam.none)
        #expect(OpenAIAdapter.toolChoiceForOpenAI(policy: .specific(toolName: "get_weather"), toolsNonEmpty: true) == .function("get_weather"))
    }

    @Test("tool_choice is omitted when there are no tools")
    func testToolChoiceOmittedWithoutTools() throws {
        #expect(OpenAIAdapter.toolChoiceForOpenAI(policy: .required, toolsNonEmpty: false) == nil)
        #expect(OpenAIAdapter.toolChoiceForOpenAI(policy: .specific(toolName: "x"), toolsNonEmpty: false) == nil)
    }

    @Test("OpenAI advertises support for every tool-choice mode")
    func testSupportedModes() throws {
        #expect(OpenAIAdapter.supportedToolChoiceModes == [.auto, .none, .required, .specific])
    }

    @Test("Effective tool-choice description echoes the mode (and tool name)")
    func testEffectiveToolChoiceDescription() throws {
        #expect(OpenAIAdapter.effectiveToolChoiceDescription(.automatic) == "auto")
        #expect(OpenAIAdapter.effectiveToolChoiceDescription(.required) == "required")
        #expect(OpenAIAdapter.effectiveToolChoiceDescription(.none) == "none")
        #expect(OpenAIAdapter.effectiveToolChoiceDescription(.specific(toolName: "get_weather")) == "specific:get_weather")
    }

    @Test("Configured policy is honored without clamping for supported modes")
    func testResolvedToolChoiceHonorsConfiguredPolicy() throws {
        let adapter = OpenAIAdapter(
            configuration: .init(
                apiKey: "test-key",
                toolInvocationPolicy: .specific(toolName: "get_weather")
            )
        )
        let resolved = adapter.resolvedToolChoice()
        #expect(resolved.effective == .specific(toolName: "get_weather"))
        #expect(resolved.clamped == false)
    }
}
