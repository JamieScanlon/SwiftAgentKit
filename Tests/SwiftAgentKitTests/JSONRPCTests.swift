//
//  JSONRPCTests.swift
//  SwiftAgentKitTests
//

import Foundation
import Testing
import SwiftAgentKit

@Suite("JSON-RPC IDs")
struct JSONRPCIDTests {
    @Test("Integer ID round-trip")
    func intID() throws {
        let data = try JSONEncoder().encode(JSONRPCID.int(42))
        let decoded = try JSONDecoder().decode(JSONRPCID.self, from: data)
        #expect(decoded == .int(42))
    }

    @Test("String ID round-trip")
    func stringID() throws {
        let data = try JSONEncoder().encode(JSONRPCID.string("req-1"))
        let decoded = try JSONDecoder().decode(JSONRPCID.self, from: data)
        #expect(decoded == .string("req-1"))
    }

    @Test("Invalid ID throws")
    func invalidID() {
        let json = "true".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(JSONRPCID.self, from: json)
        }
    }
}

@Suite("JSON-RPC Envelopes")
struct JSONRPCEnvelopeTests {
    @Test("JSONRPCError round-trip")
    func errorRoundTrip() throws {
        let original = JSONRPCError(code: -32601, message: "Not found")
        let decoded = try JSONRPCTestHelpers.roundTripCodable(original)
        #expect(decoded.code == -32601)
        #expect(decoded.message == "Not found")
    }

    @Test("JSONRPCErrorResponse round-trip")
    func errorResponse() throws {
        let original = JSONRPCErrorResponse(
            id: .int(1),
            error: JSONRPCError(code: -32600, message: "Invalid")
        )
        let decoded = try JSONRPCTestHelpers.roundTripCodable(original)
        #expect(decoded.error.code == -32600)
    }
}

@Suite("JSON-RPC Encoding")
struct JSONRPCEncodingTests {
    @Test("Encode request")
    func encodeRequest() throws {
        struct Params: Codable, Sendable { let value: Int }
        let data = try JSONRPCEncoding.encodeRequest("test", id: .int(1), params: Params(value: 42))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["jsonrpc"] as? String == "2.0")
        #expect(object?["method"] as? String == "test")
        #expect(object?["id"] as? Int == 1)
    }

    @Test("Encode notification")
    func encodeNotification() throws {
        struct Params: Codable, Sendable { let sessionId: String }
        let data = try JSONRPCEncoding.encodeNotification("notify", params: Params(sessionId: "s1"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["method"] as? String == "notify")
        #expect(object?["id"] == nil)
    }

    @Test("Encode error")
    func encodeError() throws {
        let data = try JSONRPCEncoding.encodeError(id: .int(3), code: .methodNotFound, message: "missing")
        let decoded = try JSONDecoder().decode(JSONRPCErrorResponse.self, from: data)
        #expect(decoded.error.code == JSONRPCErrorCode.methodNotFound.rawValue)
    }
}

@Suite("JSON-RPC Parsing")
struct JSONRPCParsingTests {
    @Test("Parse request")
    func parseRequest() throws {
        let json = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}"#.data(using: .utf8)!
        let message = try JSONRPCParsing.parse(json)
        if case .request(let id, let method, _) = message {
            #expect(method == "initialize")
            #expect(id == .int(1))
        } else {
            Issue.record("Expected request")
        }
    }

    @Test("Parse notification")
    func parseNotification() throws {
        let json = #"{"jsonrpc":"2.0","method":"session/cancel","params":{"sessionId":"sess-1"}}"#.data(using: .utf8)!
        let message = try JSONRPCParsing.parse(json)
        if case .notification(let method, _) = message {
            #expect(method == "session/cancel")
        } else {
            Issue.record("Expected notification")
        }
    }

    @Test("Parse invalid jsonrpc version throws")
    func invalidVersion() {
        let json = #"{"jsonrpc":"1.0","id":1,"method":"initialize"}"#.data(using: .utf8)!
        #expect(throws: JSONRPCConnectionError.self) {
            _ = try JSONRPCParsing.parse(json)
        }
    }
}

@Suite("JSON-RPC Message Filter")
struct JSONRPCMessageFilterTests {
    @Test("Valid JSON-RPC message passes through")
    func validMessage() {
        let filter = JSONRPCMessageFilter()
        let json = #"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#.data(using: .utf8)!
        #expect(filter.filterMessage(json) != nil)
    }

    @Test("Log lines are filtered out")
    func filtersLogs() {
        let filter = JSONRPCMessageFilter()
        let logLine = "INFO: starting server\n".data(using: .utf8)!
        #expect(filter.filterMessage(logLine) == nil)
    }

    @Test("Disabled filter returns raw data")
    func disabledFilter() {
        let filter = JSONRPCMessageFilter(configuration: .disabled)
        let raw = "not json at all".data(using: .utf8)!
        #expect(filter.filterMessage(raw) == raw)
    }
}

@Suite("JSON-RPC Connection")
struct JSONRPCConnectionTests {
    @Test("Call and response round-trip")
    func callResponse() async throws {
        let (clientTransport, serverTransport) = JSONRPCMemoryTransport.paired()
        let server = JSONRPCConnection(transport: serverTransport)
        let client = JSONRPCConnection(transport: clientTransport)

        await server.registerMethod("echo") { _ in
            let response = ["ok": true]
            return try JSONSerialization.data(withJSONObject: response)
        }

        try await server.connect()
        try await client.connect()

        struct Result: Decodable, Sendable { let ok: Bool }
        struct Params: Encodable, Sendable { let text: String }
        let response: Result = try await client.call("echo", params: Params(text: "hi"))
        #expect(response.ok == true)

        await client.disconnect()
        await server.disconnect()
    }

    @Test("Call when not connected throws")
    func notConnected() async throws {
        let transport = JSONRPCMemoryTransport()
        let connection = JSONRPCConnection(transport: transport)
        struct Params: Encodable, Sendable { let x: Int }
        struct Result: Decodable, Sendable { let x: Int }
        do {
            let _: Result = try await connection.call("initialize", params: Params(x: 1))
            Issue.record("Expected notConnected")
        } catch let error as JSONRPCConnectionError {
            #expect(JSONRPCTestHelpers.connectionErrorsEqual(error, .notConnected))
        }
    }
}

@Suite("JSON-RPC Error Codes")
struct JSONRPCErrorCodeTests {
    @Test("Standard JSON-RPC error codes")
    func standardCodes() {
        #expect(JSONRPCErrorCode.parseError.rawValue == -32700)
        #expect(JSONRPCErrorCode.invalidRequest.rawValue == -32600)
        #expect(JSONRPCErrorCode.methodNotFound.rawValue == -32601)
        #expect(JSONRPCErrorCode.invalidParams.rawValue == -32602)
        #expect(JSONRPCErrorCode.internalError.rawValue == -32603)
    }
}

@Suite("JSON-RPC Connection Errors")
struct JSONRPCConnectionErrorTests {
    @Test("Error descriptions are non-empty")
    func descriptions() {
        #expect(JSONRPCConnectionError.notConnected.errorDescription?.isEmpty == false)
        #expect(JSONRPCConnectionError.remoteError(JSONRPCError(code: 1, message: "fail")).errorDescription?.contains("fail") == true)
    }
}
