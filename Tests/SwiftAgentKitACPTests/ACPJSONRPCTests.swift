//
//  ACPJSONRPCTests.swift
//  SwiftAgentKitACPTests
//

import Foundation
import Testing
@testable import SwiftAgentKitACP

@Suite("ACP JSON-RPC IDs")
struct ACPJSONRPCIDTests {
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

@Suite("ACP JSON-RPC Envelopes")
struct ACPJSONRPCEnvelopeTests {
    @Test("ACPJSONRPCError round-trip")
    func errorRoundTrip() throws {
        let original = ACPJSONRPCError(code: -32601, message: "Not found")
        let decoded = try ACPTestHelpers.roundTripCodable(original)
        #expect(decoded.code == -32601)
        #expect(decoded.message == "Not found")
    }

    @Test("ACPJSONRPCErrorResponse round-trip")
    func errorResponse() throws {
        let original = ACPJSONRPCErrorResponse(
            id: .int(1),
            error: ACPJSONRPCError(code: -32600, message: "Invalid")
        )
        let decoded = try ACPTestHelpers.roundTripCodable(original)
        #expect(decoded.error.code == -32600)
    }

    @Test("ACPJSONRPCRequest round-trip")
    func requestEnvelope() throws {
        let original = ACPJSONRPCRequest(
            id: .int(1),
            method: "initialize",
            params: ACPInitializeRequest(protocolVersion: 1)
        )
        let decoded = try ACPTestHelpers.roundTripCodable(original)
        #expect(decoded.method == "initialize")
    }

    @Test("ACPJSONRPCSuccessResponse round-trip")
    func successEnvelope() throws {
        let original = ACPJSONRPCSuccessResponse(
            id: .int(2),
            result: ACPPromptResponse(stopReason: .endTurn)
        )
        let decoded = try ACPTestHelpers.roundTripCodable(original)
        #expect(decoded.result.stopReason == .endTurn)
    }

    @Test("ACPJSONRPCNotification round-trip")
    func notificationEnvelope() throws {
        let original = ACPJSONRPCNotification(
            method: "session/cancel",
            params: ACPSessionCancelParams(sessionId: "s1")
        )
        let decoded = try ACPTestHelpers.roundTripCodable(original)
        #expect(decoded.method == "session/cancel")
    }
}

@Suite("ACP JSON-RPC Encoding")
struct ACPJSONRPCEncodingTests {
    @Test("Encode request")
    func encodeRequest() throws {
        let data = try ACPJSONRPCEncoding.encodeRequest(
            "initialize",
            id: .int(1),
            params: ACPInitializeRequest(protocolVersion: 1)
        )
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["jsonrpc"] as? String == "2.0")
        #expect(object?["method"] as? String == "initialize")
        #expect(object?["id"] as? Int == 1)
    }

    @Test("Encode notification")
    func encodeNotification() throws {
        let data = try ACPJSONRPCEncoding.encodeNotification(
            "session/cancel",
            params: ACPSessionCancelParams(sessionId: "s1")
        )
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["method"] as? String == "session/cancel")
        #expect(object?["id"] == nil)
    }

    @Test("Encode success")
    func encodeSuccess() throws {
        let data = try ACPJSONRPCEncoding.encodeSuccess(
            id: .string("abc"),
            result: ACPPromptResponse(stopReason: .endTurn)
        )
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["id"] as? String == "abc")
        #expect((object?["result"] as? [String: Any])?["stopReason"] as? String == "end_turn")
    }

    @Test("Encode error")
    func encodeError() throws {
        let data = try ACPJSONRPCEncoding.encodeError(id: .int(3), code: .methodNotFound, message: "missing")
        let decoded = try JSONDecoder().decode(ACPJSONRPCErrorResponse.self, from: data)
        #expect(decoded.error.code == ACPErrorCode.methodNotFound.rawValue)
    }
}

@Suite("ACP JSON-RPC Parsing")
struct ACPJSONRPCParsingTests {
    @Test("Parse request")
    func parseRequest() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{"fs":{"readTextFile":true,"writeTextFile":false},"terminal":false}}}
        """.data(using: .utf8)!
        let message = try ACPJSONRPCParsing.parse(json)
        if case .request(let id, let method, _) = message {
            #expect(method == "initialize")
            if case .int(1) = id {} else { Issue.record("Expected int id") }
        } else {
            Issue.record("Expected request")
        }
    }

    @Test("Parse notification")
    func parseNotification() throws {
        let json = """
        {"jsonrpc":"2.0","method":"session/cancel","params":{"sessionId":"sess-1"}}
        """.data(using: .utf8)!
        let message = try ACPJSONRPCParsing.parse(json)
        if case .notification(let method, _) = message {
            #expect(method == "session/cancel")
        } else {
            Issue.record("Expected notification")
        }
    }

    @Test("Parse success response")
    func parseSuccess() throws {
        let json = """
        {"jsonrpc":"2.0","id":2,"result":{"stopReason":"end_turn"}}
        """.data(using: .utf8)!
        let message = try ACPJSONRPCParsing.parse(json)
        if case .success(let id, let result) = message {
            if case .int(2) = id {} else { Issue.record("Expected int id") }
            let decoded = try JSONDecoder().decode(ACPPromptResponse.self, from: result)
            #expect(decoded.stopReason == .endTurn)
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("Parse error response")
    func parseError() throws {
        let json = """
        {"jsonrpc":"2.0","id":3,"error":{"code":-32601,"message":"Method not found"}}
        """.data(using: .utf8)!
        let message = try ACPJSONRPCParsing.parse(json)
        if case .error(let id, let error) = message {
            if case .int(3) = id! {} else { Issue.record("Expected int id") }
            #expect(error.code == -32601)
        } else {
            Issue.record("Expected error")
        }
    }

    @Test("Parse invalid jsonrpc version throws")
    func invalidVersion() {
        let json = #"{"jsonrpc":"1.0","id":1,"method":"initialize"}"#.data(using: .utf8)!
        #expect(throws: ACPConnectionError.self) {
            _ = try ACPJSONRPCParsing.parse(json)
        }
    }

    @Test("Parse malformed JSON throws")
    func malformedJSON() {
        #expect(throws: (any Error).self) {
            _ = try ACPJSONRPCParsing.parse("{not json}".data(using: .utf8)!)
        }
    }
}

@Suite("ACP Error Codes")
struct ACPErrorCodeTests {
    @Test("Standard JSON-RPC error codes")
    func standardCodes() {
        #expect(ACPErrorCode.parseError.rawValue == -32700)
        #expect(ACPErrorCode.invalidRequest.rawValue == -32600)
        #expect(ACPErrorCode.methodNotFound.rawValue == -32601)
        #expect(ACPErrorCode.invalidParams.rawValue == -32602)
        #expect(ACPErrorCode.internalError.rawValue == -32603)
    }

    @Test("ACP-specific error codes")
    func acpCodes() {
        #expect(ACPErrorCode.authRequired.rawValue == -32001)
        #expect(ACPErrorCode.sessionNotFound.rawValue == -32002)
    }
}

@Suite("ACP Connection Errors")
struct ACPConnectionErrorTests {
    @Test("Error descriptions are non-empty")
    func descriptions() {
        #expect(ACPConnectionError.notConnected.errorDescription?.isEmpty == false)
        #expect(ACPConnectionError.parseError.errorDescription?.isEmpty == false)
        #expect(ACPConnectionError.invalidRequest.errorDescription?.isEmpty == false)
        #expect(ACPConnectionError.methodNotFound("test").errorDescription?.contains("test") == true)
        #expect(ACPConnectionError.remoteError(ACPJSONRPCError(code: 1, message: "fail")).errorDescription?.contains("fail") == true)
        #expect(ACPConnectionError.disconnected.errorDescription?.isEmpty == false)
    }
}
