//
//  ToolCall.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 5/31/25.
//

import Foundation

public struct ToolCall: Sendable {
    public let name: String
    public let arguments: [String: Sendable]
    public let instructions: String?
    public init(name: String, arguments: [String: Sendable] = [:], instructions: String? = nil) {
        self.name = name
        self.arguments = arguments
        self.instructions = instructions
    }
    
    public static func processToolCalls(content: String) -> (toolCall: String?, range: Range<String.Index>?) {
        guard !content.isEmpty else {
            return (nil, nil)
        }
        
        guard let range1 = content.ranges(of: "<|python_tag|>").first else {
            return (nil, nil)
        }
        let startIndex = range1.upperBound
        let range2Attempt = content.ranges(of: "<|eom_id|>").first ?? content.ranges(of: "<|python_tag|>").last
        guard let range2 = range2Attempt else {
            let endIndex = content.endIndex
            return (toolCall: String(content[startIndex..<endIndex]), range: range1.lowerBound..<endIndex)
        }
        let endIndex = range2.lowerBound
        return (toolCall: String(content[startIndex..<endIndex]), range: range1.lowerBound..<range2.upperBound)
    }
    
    public static func processModelResponse(content: String) -> (message: String, toolCall: String?) {
        
        let (toolCall, range) = processToolCalls(content: content)
        if let toolCall, let range {
            // Create a new string without the tool call range
            let beforeRange = String(content[..<range.lowerBound])
            let afterRange = String(content[range.upperBound...])
            let message = beforeRange + afterRange
            return (message: message, toolCall: toolCall)
        } else {
            return (message: content, toolCall: nil)
        }
    }
}


