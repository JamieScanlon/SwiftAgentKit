//
//  ACPErrorCodeTests.swift
//  SwiftAgentKitACPTests
//

import Testing
@testable import SwiftAgentKitACP

@Suite("ACP Error Codes")
struct ACPErrorCodeTests {
    @Test("ACP-specific error codes")
    func acpCodes() {
        #expect(ACPErrorCode.authRequired.rawValue == -32001)
        #expect(ACPErrorCode.sessionNotFound.rawValue == -32002)
    }
}
