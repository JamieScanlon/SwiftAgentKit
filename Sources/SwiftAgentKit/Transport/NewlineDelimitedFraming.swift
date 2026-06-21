//
//  NewlineDelimitedFraming.swift
//  SwiftAgentKit
//

import Foundation

public enum NewlineDelimitedFraming: Sendable {
    public static func appendNewlineIfNeeded(_ data: Data) -> Data {
        var payload = data
        if payload.last != UInt8(ascii: "\n") {
            payload.append(UInt8(ascii: "\n"))
        }
        return payload
    }

    public static func splitLines(from buffer: inout Data) -> [Data] {
        var lines: [Data] = []
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[..<newlineIndex]
            buffer = buffer[(newlineIndex + 1)...]
            lines.append(Data(lineData))
        }
        return lines
    }
}
