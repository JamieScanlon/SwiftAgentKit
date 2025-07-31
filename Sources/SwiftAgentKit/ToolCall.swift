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
    
    /// Processes a string to extract tool calls in various formats.
    ///
    /// This function can detect and extract tool calls from text content in two main formats:
    /// 1. **Direct format**: Tool calls that appear directly in the content (e.g., `"search_tool(query)"`)
    /// 2. **Wrapped format**: Tool calls wrapped in special tags (e.g., `"<|python_tag|>search_tool(query)<|eom_id|>"`)
    ///
    /// The function handles various edge cases including:
    /// - Leading/trailing whitespace
    /// - Tool calls with complex arguments (quotes, nested parentheses)
    /// - Incomplete tool calls (missing parentheses, only opening tags)
    /// - Tool calls not in the available tools list
    ///
    /// ## Usage Examples
    ///
    /// ### Direct Tool Call
    /// ```swift
    /// let result = ToolCall.processToolCalls(
    ///     content: "search_tool(query=\"test\")",
    ///     availableTools: ["search_tool"]
    /// )
    /// // result.toolCall == "search_tool(query=\"test\")"
    /// // result.range != nil
    /// ```
    ///
    /// ### Wrapped Tool Call
    /// ```swift
    /// let result = ToolCall.processToolCalls(
    ///     content: "Some text <|python_tag|>search_tool(query)<|eom_id|> more text",
    ///     availableTools: ["search_tool"]
    /// )
    /// // result.toolCall == "search_tool(query)"
    /// // result.range != nil
    /// ```
    ///
    /// ### Tool Call with Spaces
    /// ```swift
    /// let result = ToolCall.processToolCalls(
    ///     content: "  search_tool(query)  ",
    ///     availableTools: ["search_tool"]
    /// )
    /// // result.toolCall == "search_tool(query)"
    /// // result.range == nil (because of leading/trailing spaces)
    /// ```
    ///
    /// ### No Tool Call Found
    /// ```swift
    /// let result = ToolCall.processToolCalls(
    ///     content: "This is just regular text",
    ///     availableTools: ["search_tool"]
    /// )
    /// // result.toolCall == nil
    /// // result.range == nil
    /// ```
    ///
    /// - Parameters:
    ///   - content: The string content to process for tool calls. Can contain direct tool calls,
    ///     wrapped tool calls, or regular text without any tool calls.
    ///   - availableTools: An array of tool names that are considered valid for direct tool calls.
    ///     If empty, only wrapped tool calls will be detected. For wrapped tool calls, this parameter
    ///     is used to extract the tool call content when only the opening tag is present.
    ///
    /// - Returns: A tuple containing:
    ///   - `toolCall`: The extracted tool call string, or `nil` if no valid tool call is found.
    ///     For direct tool calls, this includes the full tool call with arguments.
    ///     For wrapped tool calls, this includes only the tool call content between the tags.
    ///   - `range`: The range in the original content where the tool call was found, or `nil` if:
    ///     - No tool call was found
    ///     - The tool call had leading/trailing spaces (for direct tool calls)
    ///     - The tool call was not in the available tools list
    ///
    /// - Note: The function prioritizes direct tool calls over wrapped tool calls. If a direct tool call
    ///   is found and it's in the available tools list, it will be returned even if wrapped tool calls
    ///   are also present in the content.
    ///
    /// - Warning: For wrapped tool calls with only an opening tag (no closing `<|eom_id|>` tag),
    ///   the function will attempt to extract just the tool call content, but this may include
    ///   extra text if the tool call format is not properly structured.
    public static func processToolCalls(content: String, availableTools: [String] = []) -> (toolCall: String?, range: Range<String.Index>?) {
        guard !content.isEmpty else {
            return (nil, nil)
        }

        // Check for tool calls that are not wrapped in <|python_tag|>...<|eom_id|>
        // The tool call must be in the available tools list
        for toolName in availableTools {
            // First check if the entire content (trimmed) is a tool call
            let trimmedContent = content.trimmingCharacters(in: .whitespaces)
            if trimmedContent.hasPrefix("\(toolName)("), trimmedContent.hasSuffix(")") {
                // If the original content has leading/trailing spaces, return nil range
                if content != trimmedContent {
                    return (toolCall: trimmedContent, range: nil)
                }
                return (toolCall: trimmedContent, range: content.startIndex..<content.endIndex)
            }
            
            // Search for tool calls within the content
            if let range = content.range(of: "\(toolName)(") {
                let startIndex = range.lowerBound
                var parenCount = 0
                var endIndex = startIndex
                
                // Find the matching closing parenthesis
                for (index, char) in content[startIndex...].enumerated() {
                    if char == "(" {
                        parenCount += 1
                    } else if char == ")" {
                        parenCount -= 1
                        if parenCount == 0 {
                            endIndex = content.index(startIndex, offsetBy: index + 1)
                            break
                        }
                    }
                }
                
                if parenCount == 0 {
                    let toolCall = String(content[startIndex..<endIndex])
                    return (toolCall: toolCall, range: startIndex..<endIndex)
                }
            }
        }
        
        // Check for direct JSON format tool calls (not wrapped in tags)
        if let jsonRange = findDirectJsonToolCall(in: content, availableTools: availableTools) {
            let jsonContent = String(content[jsonRange])
            return (toolCall: jsonContent, range: jsonRange)
        }
        
        // Check for JSON format tool calls with <|python_start|>...<|python_end|>
        if let range1 = content.ranges(of: "<|python_start|>").first {
            let startIndex = range1.upperBound
            
            // Look for the closing tag after the opening tag
            let range2Attempt = content.ranges(of: "<|python_end|>").first { range in
                range.lowerBound >= startIndex
            }
            
            if let range2 = range2Attempt {
                let endIndex = range2.lowerBound
                let toolCallContent = String(content[startIndex..<endIndex])
                return (toolCall: toolCallContent, range: range1.lowerBound..<range2.upperBound)
            } else {
                // Only opening tag is present, try to extract just the JSON content
                let endIndex = content.endIndex
                let toolCallContent = String(content[startIndex..<endIndex])
                
                // Try to find the end of the JSON object
                if let jsonEndIndex = findJsonEndIndex(in: toolCallContent) {
                    let jsonContent = String(toolCallContent[..<jsonEndIndex])
                    return (toolCall: jsonContent, range: range1.lowerBound..<content.index(startIndex, offsetBy: jsonEndIndex.utf16Offset(in: toolCallContent)))
                }
                
                return (toolCall: toolCallContent, range: range1.lowerBound..<endIndex)
            }
        }
        
        // Check for legacy format tool calls with <|python_tag|>...<|eom_id|>
        guard let range1 = content.ranges(of: "<|python_tag|>").first else {
            return (nil, nil)
        }
        
        let startIndex = range1.upperBound
        
        // Look for the closing tag after the opening tag
        let range2Attempt = content.ranges(of: "<|eom_id|>").first { range in
            range.lowerBound >= startIndex
        }
        
        guard let range2 = range2Attempt else {
            let endIndex = content.endIndex
            let toolCallContent = String(content[startIndex..<endIndex])
            // For wrapped tool calls with only opening tag, try to extract just the tool call
            if let toolCall = extractToolCallFromContent(toolCallContent, availableTools: availableTools) {
                return (toolCall: toolCall, range: range1.lowerBound..<endIndex)
            }
            return (toolCall: toolCallContent, range: range1.lowerBound..<endIndex)
        }
        let endIndex = range2.lowerBound
        let toolCallContent = String(content[startIndex..<endIndex])
        // For wrapped tool calls, try to extract just the tool call from the content
        if let extractedToolCall = extractToolCallFromContent(toolCallContent, availableTools: availableTools) {
            return (toolCall: extractedToolCall, range: range1.lowerBound..<range2.upperBound)
        }
        return (toolCall: toolCallContent, range: range1.lowerBound..<range2.upperBound)
    }
    
    private static func findDirectJsonToolCall(in content: String, availableTools: [String]) -> Range<String.Index>? {
        // Look for JSON objects that start with { and contain "type": "function"
        var braceCount = 0
        var startIndex: String.Index?
        
        for (index, char) in content.enumerated() {
            let stringIndex = content.index(content.startIndex, offsetBy: index)
            
            if char == "{" {
                if braceCount == 0 {
                    startIndex = stringIndex
                }
                braceCount += 1
            } else if char == "}" {
                braceCount -= 1
                if braceCount == 0 && startIndex != nil {
                    // We found a complete JSON object
                    let jsonRange = startIndex!..<content.index(after: stringIndex)
                    let jsonContent = String(content[jsonRange])
                    
                    // Check if it contains "type": "function" and is valid JSON
                    if jsonContent.contains("\"type\": \"function\"") {
                        if let toolCall = parseJsonFormat(jsonContent) {
                            if availableTools.isEmpty || availableTools.contains(toolCall.name) {
                                return jsonRange
                            }
                        }
                    }
                    
                    // Reset for next potential JSON object
                    startIndex = nil
                }
            }
        }
        
        return nil
    }
    
    private static func findJsonEndIndex(in content: String) -> String.Index? {
        var braceCount = 0
        var inString = false
        var escapeNext = false
        
        for (index, char) in content.enumerated() {
            let stringIndex = content.index(content.startIndex, offsetBy: index)
            
            if escapeNext {
                escapeNext = false
                continue
            }
            
            if char == "\\" {
                escapeNext = true
                continue
            }
            
            if char == "\"" {
                inString.toggle()
                continue
            }
            
            if !inString {
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        return content.index(after: stringIndex)
                    }
                }
            }
        }
        
        return nil
    }
    
    private static func extractToolCallFromContent(_ content: String, availableTools: [String]) -> String? {
        let trimmedContent = content.trimmingCharacters(in: .whitespaces)
        
        // If no available tools specified, return the trimmed content
        if availableTools.isEmpty && !trimmedContent.isEmpty {
            return trimmedContent
        }
        
        for toolName in availableTools {
            // Check if the entire trimmed content is a tool call
            if trimmedContent.hasPrefix("\(toolName)(") {
                // Find the matching closing parenthesis
                var parenCount = 0
                var endIndex = trimmedContent.startIndex
                
                for (index, char) in trimmedContent.enumerated() {
                    if char == "(" {
                        parenCount += 1
                    } else if char == ")" {
                        parenCount -= 1
                        if parenCount == 0 {
                            endIndex = trimmedContent.index(trimmedContent.startIndex, offsetBy: index + 1)
                            break
                        }
                    }
                }
                
                if parenCount == 0 {
                    return String(trimmedContent[..<endIndex])
                }
            }
            
            // Also search for tool calls within the content (not just at the beginning)
            let pattern = "\(toolName)\\("
            if let range = trimmedContent.range(of: pattern, options: .regularExpression) {
                let startIndex = range.lowerBound
                var parenCount = 0
                var endIndex = trimmedContent.startIndex
                
                for (index, char) in trimmedContent[range.lowerBound...].enumerated() {
                    if char == "(" {
                        parenCount += 1
                    } else if char == ")" {
                        parenCount -= 1
                        if parenCount == 0 {
                            endIndex = trimmedContent.index(startIndex, offsetBy: index + 1)
                            break
                        }
                    }
                }
                
                if parenCount == 0 {
                    return String(trimmedContent[startIndex..<endIndex])
                }
            }
        }
        
        return nil
    }
    
    public static func processModelResponse(content: String, availableTools: [String] = []) -> (message: String, toolCall: String?) {
        
        let (toolCall, range) = processToolCalls(content: content, availableTools: availableTools)
        if let toolCall {
            if let range {
                // Check if this is a JSON format tool call by looking for the opening tag
                if let pythonStartTagRange = content.range(of: "<|python_start|>"),
                   range.lowerBound >= pythonStartTagRange.lowerBound {
                    // This is a JSON format wrapped tool call
                    if let pythonEndTagRange = content.range(of: "<|python_end|>"),
                       range.upperBound <= pythonEndTagRange.upperBound {
                        // Both tags are present, remove the entire wrapped content
                        let beforePythonStartTag = String(content[..<pythonStartTagRange.lowerBound])
                        let afterPythonEndTag = String(content[pythonEndTagRange.upperBound...])
                        let message = beforePythonStartTag + afterPythonEndTag
                        return (message: message, toolCall: toolCall)
                    } else {
                        // Only opening tag is present, remove everything from the opening tag onwards
                        let beforePythonStartTag = String(content[..<pythonStartTagRange.lowerBound])
                        let message = beforePythonStartTag
                        return (message: message, toolCall: toolCall)
                    }
                } else if let pythonTagRange = content.range(of: "<|python_tag|>"),
                          range.lowerBound >= pythonTagRange.lowerBound {
                    // This is a legacy wrapped tool call
                    if let eomTagRange = content.range(of: "<|eom_id|>"),
                       range.upperBound <= eomTagRange.upperBound {
                        // Both tags are present, preserve the tags
                        let beforePythonTag = String(content[..<pythonTagRange.lowerBound])
                        let afterEomTag = String(content[eomTagRange.upperBound...])
                        let message = beforePythonTag + afterEomTag
                        return (message: message, toolCall: toolCall)
                    } else {
                        // Only opening tag is present, remove everything from the opening tag onwards
                        let beforePythonTag = String(content[..<pythonTagRange.lowerBound])
                        let message = beforePythonTag
                        return (message: message, toolCall: toolCall)
                    }
                } else {
                    // This is a direct tool call, remove the entire range
                    let beforeRange = String(content[..<range.lowerBound])
                    let afterRange = String(content[range.upperBound...])
                    let message = beforeRange + afterRange
                    return (message: message, toolCall: toolCall)
                }
            } else {
                // Tool call found but no range (e.g., direct tool call with spaces)
                // Remove only the first occurrence of the tool call, preserving all other whitespace
                if let toolCallRange = content.range(of: toolCall) {
                    var message = content
                    message.removeSubrange(toolCallRange)
                    return (message: message, toolCall: toolCall)
                } else {
                    return (message: content, toolCall: toolCall)
                }
            }
        } else {
            return (message: content, toolCall: nil)
        }
    }
    
    /// Parses a tool call string and returns a ToolCall object.
    ///
    /// This function takes a string in the format `function_name(arg1, arg2)` and parses it into
    /// a `ToolCall` object with the function name and arguments.
    ///
    /// ## Usage Examples
    ///
    /// ### Basic Tool Call
    /// ```swift
    /// let toolCall = ToolCall.parse("search_tool(query=\"test\")")
    /// // toolCall.name == "search_tool"
    /// // toolCall.arguments == ["query": "test"]
    /// ```
    ///
    /// ### Multiple Arguments
    /// ```swift
    /// let toolCall = ToolCall.parse("calculate_sum(a=5, b=10)")
    /// // toolCall.name == "calculate_sum"
    /// // toolCall.arguments == ["a": "5", "b": "10"]
    /// ```
    ///
    /// ### No Arguments
    /// ```swift
    /// let toolCall = ToolCall.parse("get_time()")
    /// // toolCall.name == "get_time"
    /// // toolCall.arguments == [:]
    /// ```
    ///
    /// ### Invalid Format
    /// ```swift
    /// let toolCall = ToolCall.parse("invalid_format")
    /// // toolCall == nil
    /// ```
    ///
    /// - Parameter toolCallString: The tool call string to parse, expected in the format
    ///   `function_name(arg1, arg2)` where arguments are optional.
    ///
    /// - Returns: A `ToolCall` object if the string can be parsed successfully, or `nil` if the
    ///   format is invalid or parsing fails.
    ///
    /// - Note: Arguments are parsed as strings. If you need typed arguments, you'll need to
    ///   convert them after parsing based on your specific requirements.
    public static func parse(_ toolCallString: String) -> ToolCall? {
        let trimmed = toolCallString.trimmingCharacters(in: .whitespaces)
        
        // Try to parse as JSON format first
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            return parseJsonFormat(trimmed)
        }
        
        // Find the opening parenthesis
        guard let openParenIndex = trimmed.firstIndex(of: "(") else {
            return nil
        }
        
        // Extract function name
        let functionName = String(trimmed[..<openParenIndex]).trimmingCharacters(in: .whitespaces)
        guard !functionName.isEmpty else {
            return nil
        }
        
        // Find the closing parenthesis
        guard let closeParenIndex = trimmed.lastIndex(of: ")") else {
            return nil
        }
        
        // Extract arguments string
        let argsStartIndex = trimmed.index(after: openParenIndex)
        let argsEndIndex = closeParenIndex
        let argsString = String(trimmed[argsStartIndex..<argsEndIndex]).trimmingCharacters(in: .whitespaces)
        
        // Parse arguments
        var arguments: [String: Sendable] = [:]
        
        if !argsString.isEmpty {
            let args = parseArguments(argsString)
            arguments = args
        }
        
        return ToolCall(name: functionName, arguments: arguments)
    }
    
    private static func parseJsonFormat(_ jsonString: String) -> ToolCall? {
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            
            guard let dict = json as? [String: Any] else {
                return nil
            }
            
            guard let type = dict["type"] as? String, type == "function" else {
                return nil
            }
            
            guard let name = dict["name"] as? String else {
                return nil
            }
            
            var arguments: [String: Sendable] = [:]
            
            if let parameters = dict["parameters"] as? [String: Any] {
                for (key, value) in parameters {
                    // Convert values to appropriate types
                    if let stringValue = value as? String {
                        arguments[key] = stringValue
                    } else if let boolValue = value as? Bool {
                        arguments[key] = boolValue
                    } else if let intValue = value as? Int {
                        arguments[key] = intValue
                    } else if let doubleValue = value as? Double {
                        arguments[key] = doubleValue
                    } else if let nsNumber = value as? NSNumber {
                        // Handle NSNumber types (including booleans from JSON)
                        if CFGetTypeID(nsNumber) == CFBooleanGetTypeID() {
                            arguments[key] = nsNumber.boolValue
                        } else if CFNumberIsFloatType(nsNumber) {
                            arguments[key] = nsNumber.doubleValue
                        } else {
                            arguments[key] = nsNumber.intValue
                        }
                    } else {
                        // Convert other types to strings
                        arguments[key] = String(describing: value)
                    }
                }
            }
            
            return ToolCall(name: name, arguments: arguments)
        } catch {
            return nil
        }
    }
    
    private static func parseArguments(_ argsString: String) -> [String: Sendable] {
        var arguments: [String: Sendable] = [:]
        var currentArg = ""
        var currentValue = ""
        var inQuotes = false
        var quoteChar: Character?
        var parenCount = 0
        var parsingKey = true
        var key = ""
        var positionalIndex = 1
        var hasSeenEquals = false
        
        for char in argsString {
            if inQuotes {
                if char == quoteChar {
                    inQuotes = false
                    quoteChar = nil
                    if parsingKey && hasSeenEquals {
                        // This is a quoted value for a named argument
                        key = currentValue
                        currentValue = ""
                        parsingKey = false
                    } else if parsingKey && !hasSeenEquals {
                        // This is a quoted unnamed argument
                        let value = currentValue.trimmingCharacters(in: .whitespaces)
                        if !value.isEmpty {
                            arguments[String(positionalIndex)] = value
                            positionalIndex += 1
                        }
                        currentValue = ""
                    }
                } else {
                    currentValue.append(char)
                }
            } else {
                switch char {
                case "'", "\"":
                    inQuotes = true
                    quoteChar = char
                case "(":
                    parenCount += 1
                    currentValue.append(char)
                case ")":
                    parenCount -= 1
                    currentValue.append(char)
                case "=":
                    if parenCount == 0 && parsingKey {
                        hasSeenEquals = true
                        key = currentArg.trimmingCharacters(in: .whitespaces)
                        currentArg = ""
                        parsingKey = false
                    } else {
                        currentValue.append(char)
                    }
                case ",":
                    if parenCount == 0 {
                        if !parsingKey {
                            // Named argument: key=value
                            let value = currentValue.trimmingCharacters(in: .whitespaces)
                            if !key.isEmpty {
                                arguments[key] = value
                            }
                        } else {
                            // Unnamed argument: just value
                            let value = currentArg.trimmingCharacters(in: .whitespaces)
                            if !value.isEmpty {
                                arguments[String(positionalIndex)] = value
                                positionalIndex += 1
                            }
                        }
                        currentArg = ""
                        currentValue = ""
                        key = ""
                        parsingKey = true
                        hasSeenEquals = false
                    } else {
                        currentValue.append(char)
                    }
                default:
                    if parsingKey {
                        currentArg.append(char)
                    } else {
                        currentValue.append(char)
                    }
                }
            }
        }
        
        // Handle the last argument
        if !parsingKey {
            // Named argument: key=value
            let value = currentValue.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                arguments[key] = value
            }
        } else {
            // Unnamed argument: just value
            let value = currentArg.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty {
                arguments[String(positionalIndex)] = value
            }
        }
        
        return arguments
    }
}


