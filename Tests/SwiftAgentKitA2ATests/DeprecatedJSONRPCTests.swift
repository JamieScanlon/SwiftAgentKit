//
//  DeprecatedJSONRPCTests.swift
//  SwiftAgentKitA2ATests
//

import SwiftAgentKit
import SwiftAgentKitA2A
import Testing

@Suite("A2A Deprecated JSON-RPC Shims")
struct DeprecatedJSONRPCTests {
    @Test("Deprecated typealiases resolve to SwiftAgentKit types")
    func typealiasesMatch() {
        let error: JSONRPCError = SwiftAgentKit.JSONRPCError(code: 1, message: "test")
        #expect(error.code == 1)
        let request = SwiftAgentKit.JSONRPCRequest(
            id: .int(1),
            method: "test",
            params: ["key": "value"] as [String: String]
        )
        let shimRequest: JSONRPCRequest = request
        #expect(shimRequest.id == .int(1))
    }
}
