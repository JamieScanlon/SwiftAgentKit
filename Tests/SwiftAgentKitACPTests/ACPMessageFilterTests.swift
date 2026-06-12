//
//  ACPMessageFilterTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import Testing
@testable import SwiftAgentKitACP

@Suite("ACP Message Filter")
struct ACPMessageFilterTests {
    @Test("Valid JSON-RPC message passes through")
    func validMessage() {
        let filter = ACPMessageFilter()
        let json = #"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#.data(using: .utf8)!
        let result = filter.filterMessage(json)
        #expect(result != nil)
        #expect(String(data: result!, encoding: .utf8)?.contains("initialize") == true)
    }

    @Test("Log lines are filtered out")
    func filtersLogs() {
        let filter = ACPMessageFilter()
        let logLine = "INFO: starting server\n".data(using: .utf8)!
        #expect(filter.filterMessage(logLine) == nil)
    }

    @Test("Mixed valid and invalid lines")
    func mixedLines() {
        let filter = ACPMessageFilter()
        let mixed = """
        LOG: noise
        {"jsonrpc":"2.0","id":1,"result":{"stopReason":"end_turn"}}
        """.data(using: .utf8)!
        let result = filter.filterMessage(mixed)
        #expect(result != nil)
        #expect(String(data: result!, encoding: .utf8)?.contains("stopReason") == true)
        #expect(String(data: result!, encoding: .utf8)?.contains("LOG:") == false)
    }

    @Test("Disabled filter returns raw data")
    func disabledFilter() {
        let filter = ACPMessageFilter(configuration: .init(enabled: false))
        let raw = "not json at all".data(using: .utf8)!
        #expect(filter.filterMessage(raw) == raw)
    }

    @Test("Empty input returns nil")
    func emptyInput() {
        let filter = ACPMessageFilter()
        #expect(filter.filterMessage(Data()) == nil)
        #expect(filter.filterMessage("\n\n".data(using: .utf8)!) == nil)
    }

    @Test("Invalid UTF-8 returns nil")
    func invalidUTF8() {
        let filter = ACPMessageFilter()
        #expect(filter.filterMessage(Data([0xFF, 0xFE])) == nil)
    }

    @Test("Response messages are valid")
    func responseMessage() {
        let filter = ACPMessageFilter()
        let json = #"{"jsonrpc":"2.0","id":2,"result":{"sessionId":"s1"}}"#.data(using: .utf8)!
        #expect(filter.filterMessage(json) != nil)
    }

    @Test("Error messages are valid")
    func errorMessage() {
        let filter = ACPMessageFilter()
        let json = #"{"jsonrpc":"2.0","id":3,"error":{"code":-32601,"message":"nope"}}"#.data(using: .utf8)!
        #expect(filter.filterMessage(json) != nil)
    }
}
