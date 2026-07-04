//
//  OAuthCallbackServerTests.swift
//  SwiftAgentKitTests
//

import Testing
import Foundation
import SwiftAgentKit

/// Tests for OAuthCallbackServer.CallbackResult and OAuthCallbackReceiver contract
struct OAuthCallbackServerTests {

    private func sendCallbackGET(port: UInt16, path: String, query: String) async throws {
        let url = URL(string: "http://127.0.0.1:\(port)\(path)?\(query)")!
        _ = try await URLSession.shared.data(from: url)
    }

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

    @Test("waitForCallback times out when no callback is delivered")
    func undeliveredWaitTimesOut() async throws {
        let server = OAuthCallbackServer(port: 19877, callbackPath: "/oauth/callback")
        let start = ContinuousClock.now

        await #expect(throws: OAuthError.self) {
            _ = try await server.waitForCallback(timeout: 0.15)
        }

        let elapsed = start.duration(to: ContinuousClock.now)
        #expect(elapsed >= .milliseconds(100))
        #expect(elapsed < .milliseconds(500))
    }

    @Test("stale timeout from completed wait does not affect successor wait")
    func staleTimeoutDoesNotAffectSuccessorWait() async throws {
        let server = OAuthCallbackServer(port: 19876, callbackPath: "/oauth/callback")

        let flow1 = Task {
            try await server.waitForCallback(timeout: 0.3)
        }

        try await Task.sleep(for: .milliseconds(75))
        try await sendCallbackGET(port: 19876, path: "/oauth/callback", query: "code=first")
        let result1 = try await flow1.value
        #expect(result1.authorizationCode == "first")

        let flow2 = Task {
            try await server.waitForCallback(timeout: 2.0)
        }

        try await Task.sleep(for: .milliseconds(75))
        try await sendCallbackGET(port: 19876, path: "/oauth/callback", query: "code=second")

        let result2 = try await flow2.value
        #expect(result2.authorizationCode == "second")
    }

}
