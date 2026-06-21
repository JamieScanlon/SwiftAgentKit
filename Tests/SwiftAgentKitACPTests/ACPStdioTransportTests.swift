//
//  PipeStdioTransportTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import SwiftAgentKit
import Testing
@testable import SwiftAgentKitACP

@Suite("ACP Stdio Transport")
struct PipeStdioTransportTests {
    @Test("Send writes newline-delimited payload to inPipe")
    func sendAppendsNewline() async throws {
        let inPipe = Pipe()
        let outPipe = Pipe()
        let transport = PipeStdioTransport(inPipe: inPipe, outPipe: outPipe)
        try await transport.connect()

        let payload = #"{"jsonrpc":"2.0","method":"notify"}"#.data(using: .utf8)!
        try await transport.send(payload)

        try await Task.sleep(for: .milliseconds(20))
        let data = inPipe.fileHandleForReading.availableData
        #expect(data.last == UInt8(ascii: "\n"))

        await transport.disconnect()
    }

    @Test("Receive stream yields filtered messages from outPipe")
    func receiveFiltered() async throws {
        let inPipe = Pipe()
        let outPipe = Pipe()
        let transport = PipeStdioTransport(inPipe: inPipe, outPipe: outPipe)
        try await transport.connect()

        let jsonLine = #"{"jsonrpc":"2.0","id":1,"result":{"stopReason":"end_turn"}}"#
        outPipe.fileHandleForWriting.write((jsonLine + "\n").data(using: .utf8)!)

        let stream = transport.receive()
        let received = LockBox<Data?>(nil)
        let collectTask = Task {
            for try await data in stream {
                received.value = data
                break
            }
        }

        try await Task.sleep(for: .milliseconds(100))
        collectTask.cancel()
        #expect(received.value != nil)

        await transport.disconnect()
    }

    @Test("Send without connect throws")
    func sendWithoutConnect() async throws {
        let transport = PipeStdioTransport(inPipe: Pipe(), outPipe: Pipe())
        do {
            try await transport.send(Data("x".utf8))
            Issue.record("Expected notConnected")
        } catch let error as JSONRPCConnectionError {
            #expect(ACPTestHelpers.connectionErrorsEqual(error, .notConnected))
        }
    }

    @Test("Connect twice is idempotent")
    func connectTwice() async throws {
        let transport = PipeStdioTransport(inPipe: Pipe(), outPipe: Pipe())
        try await transport.connect()
        try await transport.connect()
        await transport.disconnect()
    }
}

@Suite("ACP Process Stdio Transport")
struct ProcessStdioTransportTests {
    @Test("Connect and disconnect lifecycle")
    func lifecycle() async throws {
        let transport = ProcessStdioTransport()
        try await transport.connect()
        await transport.disconnect()
    }

    @Test("Send without connect throws")
    func sendWithoutConnect() async throws {
        let transport = ProcessStdioTransport()
        do {
            try await transport.send(Data("x".utf8))
            Issue.record("Expected notConnected")
        } catch let error as JSONRPCConnectionError {
            #expect(ACPTestHelpers.connectionErrorsEqual(error, .notConnected))
        }
    }
}
