//
//  OAuthCallbackServerTests.swift
//  SwiftAgentKitTests
//

import Testing
import Foundation
import SwiftAgentKit

/// Tests for OAuthCallbackServer.CallbackResult and OAuthCallbackReceiver contract
struct OAuthCallbackServerTests {

    @Test("CallbackResult isSuccess is true when code present and no error")
    func callbackResultSuccess() throws {
        let result = OAuthCallbackServer.CallbackResult(
            authorizationCode: "abc123",
            state: "xyz",
            error: nil,
            errorDescription: nil
        )
        #expect(result.isSuccess == true)
        #expect(result.authorizationCode == "abc123")
        #expect(result.state == "xyz")
        #expect(result.error == nil)
        #expect(result.errorDescription == nil)
    }

    @Test("CallbackResult isSuccess is false when error present")
    func callbackResultError() throws {
        let result = OAuthCallbackServer.CallbackResult(
            authorizationCode: nil,
            state: nil,
            error: "access_denied",
            errorDescription: "User denied access"
        )
        #expect(result.isSuccess == false)
        #expect(result.authorizationCode == nil)
        #expect(result.error == "access_denied")
        #expect(result.errorDescription == "User denied access")
    }

    @Test("CallbackResult isSuccess is false when code missing and no error")
    func callbackResultNoCodeNoError() throws {
        let result = OAuthCallbackServer.CallbackResult(
            authorizationCode: nil,
            state: "state",
            error: nil,
            errorDescription: nil
        )
        #expect(result.isSuccess == false)
    }

    @Test("CallbackResult isSuccess is false when both code and error present")
    func callbackResultCodeAndError() throws {
        let result = OAuthCallbackServer.CallbackResult(
            authorizationCode: "code",
            state: nil,
            error: "error",
            errorDescription: nil
        )
        #expect(result.isSuccess == false)
    }

}
