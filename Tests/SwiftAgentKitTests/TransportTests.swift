//
//  TransportTests.swift
//  SwiftAgentKitTests
//

import Foundation
import Testing
import SwiftAgentKit

@Suite("Newline Delimited Framing")
struct NewlineDelimitedFramingTests {
    @Test("Appends newline when missing")
    func appendNewline() {
        let data = Data("hello".utf8)
        let framed = NewlineDelimitedFraming.appendNewlineIfNeeded(data)
        #expect(framed.last == UInt8(ascii: "\n"))
    }

    @Test("Splits buffered lines")
    func splitLines() {
        var buffer = Data("line1\nline2\npartial".utf8)
        let lines = NewlineDelimitedFraming.splitLines(from: &buffer)
        #expect(lines.count == 2)
        #expect(String(data: lines[0], encoding: .utf8) == "line1")
        #expect(String(data: buffer, encoding: .utf8) == "partial")
    }
}

@Suite("JSON-RPC Memory Transport")
struct JSONRPCMemoryTransportTests {
    @Test("Paired transports deliver messages")
    func pairedDelivery() async throws {
        let (a, b) = JSONRPCMemoryTransport.paired()
        try await a.connect()
        try await b.connect()

        let payload = "hello".data(using: .utf8)!
        try await a.send(payload)

        let stream = b.receive()
        var received: Data?
        for try await data in stream {
            received = data
            break
        }
        #expect(received == payload)

        await a.disconnect()
        await b.disconnect()
    }
}

@Suite("Pipe Stdio Transport")
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
}

@Suite("Process Stdio Transport")
struct ProcessStdioTransportTests {
    @Test("Connect and disconnect lifecycle")
    func lifecycle() async throws {
        let transport = ProcessStdioTransport()
        try await transport.connect()
        await transport.disconnect()
    }
}
