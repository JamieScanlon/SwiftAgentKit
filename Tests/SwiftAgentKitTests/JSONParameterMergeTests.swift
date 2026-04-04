import Foundation
import Testing
import SwiftAgentKit
import EasyJSON

@Suite("JSON parameter merge")
struct JSONParameterMergeTests {
    @Test("mergeJSONObjectParameters combines object keys with override winning")
    func testMergeObjects() throws {
        let base = JSON.object(["a": .string("1"), "b": .string("2")])
        let override = JSON.object(["b": .string("override"), "c": .string("3")])
        let merged = mergeJSONObjectParameters(base, override)
        guard case .object(let dict) = merged else {
            Issue.record("Expected object")
            return
        }
        guard case .string(let a) = dict["a"], a == "1" else {
            Issue.record("a")
            return
        }
        guard case .string(let b) = dict["b"], b == "override" else {
            Issue.record("b")
            return
        }
        guard case .string(let c) = dict["c"], c == "3" else {
            Issue.record("c")
            return
        }
    }
}
