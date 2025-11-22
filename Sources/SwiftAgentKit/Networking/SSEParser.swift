import Foundation
import Logging
import EasyJSON
import EasyJSON

/// Parser for Server-Sent Events (SSE) that handles incremental parsing of streaming data
/// Handles proper SSE message boundaries, multi-line data fields, and UTF-8 character boundaries
actor SSEParser {
    private var buffer = Data()
    private let logger: Logger?
    
    init(logger: Logger? = nil) {
        self.logger = logger
    }
    
    /// Append a chunk of data and extract any complete SSE messages
    /// - Parameter data: New data chunk to append
    /// - Returns: Array of complete JSON objects parsed from SSE messages
    func appendChunk(_ data: Data) -> [[String: Sendable]] {
        buffer.append(data)
        var messages: [[String: Sendable]] = []
        
        // Process complete SSE messages (separated by \n\n)
        // Keep processing until no more complete messages are found
        var processedAny = true
        while processedAny {
            processedAny = false
            guard let messageEnd = findMessageBoundary() else {
                break
            }
            
            guard messageEnd < buffer.count else {
                break // Invalid boundary index
            }
            
            let endIndex = buffer.index(buffer.startIndex, offsetBy: messageEnd)
            let messageData = buffer[..<endIndex]
            
            // Remove message including \n\n (2 bytes)
            let removeEndIndex = buffer.index(endIndex, offsetBy: 2)
            guard removeEndIndex <= buffer.endIndex else {
                break // Not enough data yet
            }
            
            // Parse the message before removing it
            if let json = parseSSEMessage(messageData) {
                messages.append(json)
            }
            
            // Remove the processed message
            buffer.removeSubrange(..<removeEndIndex)
            processedAny = true
        }
        
        return messages
    }
    
    /// Extract any remaining complete messages and reset the buffer
    /// Useful when stream ends
    func finalize() -> [[String: Sendable]] {
        var messages: [[String: Sendable]] = []
        
        // Process any remaining complete messages
        var processedAny = true
        while processedAny {
            processedAny = false
            guard let messageEnd = findMessageBoundary() else {
                break
            }
            
            guard messageEnd < buffer.count else {
                break // Invalid boundary index
            }
            
            let endIndex = buffer.index(buffer.startIndex, offsetBy: messageEnd)
            let messageData = buffer[..<endIndex]
            
            // Remove message including \n\n (2 bytes)
            let removeEndIndex = buffer.index(endIndex, offsetBy: 2)
            guard removeEndIndex <= buffer.endIndex else {
                break // Not enough data yet
            }
            
            // Parse the message before removing it
            if let json = parseSSEMessage(messageData) {
                messages.append(json)
            }
            
            // Remove the processed message
            buffer.removeSubrange(..<removeEndIndex)
            processedAny = true
        }
        
        // If there's remaining data without a trailing \n\n, try to parse it as a final message
        // Some servers don't send final \n\n
        if !buffer.isEmpty {
            if let json = parseSSEMessage(buffer) {
                messages.append(json)
            }
            buffer.removeAll()
        }
        
        return messages
    }
    
    /// Find the index of the next message boundary (\n\n)
    /// Returns nil if no complete message is available
    private func findMessageBoundary() -> Int? {
        guard !buffer.isEmpty else { return nil }
        
        var searchIndex = buffer.startIndex
        
        while searchIndex < buffer.endIndex {
            // Look for \n
            guard let newlineIndex = buffer[searchIndex...].firstIndex(of: UInt8(ascii: "\n")) else {
                break
            }
            
            // Check if next byte is also \n (message boundary)
            let nextIndex = buffer.index(after: newlineIndex)
            guard nextIndex < buffer.endIndex else {
                break // Not enough data for double newline
            }
            
            if buffer[nextIndex] == UInt8(ascii: "\n") {
                return buffer.distance(from: buffer.startIndex, to: newlineIndex)
            }
            
            // Move past this newline and continue searching
            searchIndex = buffer.index(after: newlineIndex)
        }
        
        return nil
    }
    
    /// Parse a complete SSE message into a JSON object
    /// Handles multiple data: fields (joins them with \n)
    /// - Parameter messageData: Data containing a complete SSE message
    /// - Returns: Parsed JSON object, or nil if parsing fails
    private func parseSSEMessage(_ messageData: Data) -> [String: Sendable]? {
        guard let messageString = String(data: messageData, encoding: .utf8) else {
            logger?.debug(
                "Failed to decode SSE message as UTF-8",
                metadata: ["messageBytes": .stringConvertible(messageData.count)]
            )
            return nil
        }
        
        let lines = messageString.components(separatedBy: .newlines)
        var dataFields: [String] = []
        var eventType: String?
        var eventId: String?
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines
            if trimmedLine.isEmpty {
                continue
            }
            
            // Parse data: field (SSE spec allows multiple data: fields per message)
            if trimmedLine.hasPrefix("data:") {
                let dataContent = String(trimmedLine.dropFirst(5))
                    .trimmingCharacters(in: .whitespaces)
                if !dataContent.isEmpty {
                    dataFields.append(dataContent)
                }
            }
            // Parse event: field
            else if trimmedLine.hasPrefix("event:") {
                eventType = String(trimmedLine.dropFirst(6))
                    .trimmingCharacters(in: .whitespaces)
            }
            // Parse id: field
            else if trimmedLine.hasPrefix("id:") {
                eventId = String(trimmedLine.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
            }
            // Ignore comment lines (starting with :)
            else if trimmedLine.hasPrefix(":") {
                continue
            }
            // Ignore other field types (retry:, etc.)
        }
        
        // Join multiple data fields with newline (per SSE spec)
        guard !dataFields.isEmpty else {
            logger?.debug("SSE message has no data fields")
            return nil
        }
        
        let combinedData = dataFields.joined(separator: "\n")
        
        // Try to parse as JSON
        guard let jsonData = combinedData.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Sendable] else {
            logger?.debug(
                "Failed to parse SSE data as JSON",
                metadata: ["data": .string(combinedData)]
            )
            return nil
        }
        
        // Add event type and id if present
        var result = jsonObject
        if let eventType = eventType {
            result["_sse_event"] = eventType
        }
        if let eventId = eventId {
            result["_sse_id"] = eventId
        }
        
        return result
    }
    
    /// Reset the parser state
    func reset() {
        buffer.removeAll()
    }
}

/// Parser for Server-Sent Events (SSE) that returns EasyJSON.JSON objects
actor SSEJSONParser {
    private var buffer = Data()
    private let logger: Logger?
    
    init(logger: Logger? = nil) {
        self.logger = logger
    }
    
    /// Append a chunk of data and extract any complete SSE messages
    /// - Parameter data: New data chunk to append
    /// - Returns: Array of complete JSON objects parsed from SSE messages
    func appendChunk(_ data: Data) -> [JSON] {
        buffer.append(data)
        var messages: [JSON] = []
        
        // Process complete SSE messages (separated by \n\n)
        // Keep processing until no more complete messages are found
        var processedAny = true
        while processedAny {
            processedAny = false
            guard let messageEnd = findMessageBoundary() else {
                break
            }
            
            guard messageEnd < buffer.count else {
                break // Invalid boundary index
            }
            
            let endIndex = buffer.index(buffer.startIndex, offsetBy: messageEnd)
            let messageData = buffer[..<endIndex]
            
            // Remove message including \n\n (2 bytes)
            let removeEndIndex = buffer.index(endIndex, offsetBy: 2)
            guard removeEndIndex <= buffer.endIndex else {
                break // Not enough data yet
            }
            
            // Parse the message before removing it
            if let json = parseSSEMessage(messageData) {
                messages.append(json)
            }
            
            // Remove the processed message
            buffer.removeSubrange(..<removeEndIndex)
            processedAny = true
        }
        
        return messages
    }
    
    /// Extract any remaining complete messages and reset the buffer
    /// Useful when stream ends
    func finalize() -> [JSON] {
        var messages: [JSON] = []
        
        // Process any remaining complete messages
        var processedAny = true
        while processedAny {
            processedAny = false
            guard let messageEnd = findMessageBoundary() else {
                break
            }
            
            guard messageEnd < buffer.count else {
                break // Invalid boundary index
            }
            
            let endIndex = buffer.index(buffer.startIndex, offsetBy: messageEnd)
            let messageData = buffer[..<endIndex]
            
            // Remove message including \n\n (2 bytes)
            let removeEndIndex = buffer.index(endIndex, offsetBy: 2)
            guard removeEndIndex <= buffer.endIndex else {
                break // Not enough data yet
            }
            
            // Parse the message before removing it
            if let json = parseSSEMessage(messageData) {
                messages.append(json)
            }
            
            // Remove the processed message
            buffer.removeSubrange(..<removeEndIndex)
            processedAny = true
        }
        
        // If there's remaining data without a trailing \n\n, try to parse it as a final message
        // Some servers don't send final \n\n
        if !buffer.isEmpty {
            if let json = parseSSEMessage(buffer) {
                messages.append(json)
            }
            buffer.removeAll()
        }
        
        return messages
    }
    
    /// Find the index of the next message boundary (\n\n)
    /// Returns nil if no complete message is available
    private func findMessageBoundary() -> Int? {
        guard !buffer.isEmpty else { return nil }
        
        var searchIndex = buffer.startIndex
        
        while searchIndex < buffer.endIndex {
            // Look for \n
            guard let newlineIndex = buffer[searchIndex...].firstIndex(of: UInt8(ascii: "\n")) else {
                break
            }
            
            // Check if next byte is also \n (message boundary)
            let nextIndex = buffer.index(after: newlineIndex)
            guard nextIndex < buffer.endIndex else {
                break // Not enough data for double newline
            }
            
            if buffer[nextIndex] == UInt8(ascii: "\n") {
                return buffer.distance(from: buffer.startIndex, to: newlineIndex)
            }
            
            // Move past this newline and continue searching
            searchIndex = buffer.index(after: newlineIndex)
        }
        
        return nil
    }
    
    /// Parse a complete SSE message into a JSON object
    /// Handles multiple data: fields (joins them with \n)
    /// - Parameter messageData: Data containing a complete SSE message
    /// - Returns: Parsed JSON object, or nil if parsing fails
    private func parseSSEMessage(_ messageData: Data) -> JSON? {
        guard let messageString = String(data: messageData, encoding: .utf8) else {
            logger?.debug(
                "Failed to decode SSE message as UTF-8",
                metadata: ["messageBytes": .stringConvertible(messageData.count)]
            )
            return nil
        }
        
        let lines = messageString.components(separatedBy: .newlines)
        var dataFields: [String] = []
        var eventType: String?
        var eventId: String?
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines
            if trimmedLine.isEmpty {
                continue
            }
            
            // Parse data: field (SSE spec allows multiple data: fields per message)
            if trimmedLine.hasPrefix("data:") {
                let dataContent = String(trimmedLine.dropFirst(5))
                    .trimmingCharacters(in: .whitespaces)
                if !dataContent.isEmpty {
                    dataFields.append(dataContent)
                }
            }
            // Parse event: field
            else if trimmedLine.hasPrefix("event:") {
                eventType = String(trimmedLine.dropFirst(6))
                    .trimmingCharacters(in: .whitespaces)
            }
            // Parse id: field
            else if trimmedLine.hasPrefix("id:") {
                eventId = String(trimmedLine.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
            }
            // Ignore comment lines (starting with :)
            else if trimmedLine.hasPrefix(":") {
                continue
            }
            // Ignore other field types (retry:, etc.)
        }
        
        // Join multiple data fields with newline (per SSE spec)
        guard !dataFields.isEmpty else {
            logger?.debug("SSE message has no data fields")
            return nil
        }
        
        let combinedData = dataFields.joined(separator: "\n")
        
        // Try to parse as JSON
        guard let jsonData = combinedData.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) else {
            logger?.debug(
                "Failed to parse SSE data as JSON",
                metadata: ["data": .string(combinedData)]
            )
            return nil
        }
        
        // Convert to EasyJSON.JSON
        let json = convertToJSON(jsonObject)
        
        // Add event type and id if present
        if let eventType = eventType {
            if case .object(var dict) = json {
                dict["_sse_event"] = .string(eventType)
                return .object(dict)
            }
        }
        if let eventId = eventId {
            if case .object(var dict) = json {
                dict["_sse_id"] = .string(eventId)
                return .object(dict)
            }
        }
        
        return json
    }
    
    /// Convert Any to EasyJSON.JSON
    private func convertToJSON(_ value: Any) -> JSON {
        if let dict = value as? [String: Any] {
            var jsonDict: [String: JSON] = [:]
            for (key, val) in dict {
                jsonDict[key] = convertToJSON(val)
            }
            return .object(jsonDict)
        } else if let array = value as? [Any] {
            return .array(array.map { convertToJSON($0) })
        } else if let nsNumber = value as? NSNumber {
            // Check if it's a boolean
            if CFGetTypeID(nsNumber) == CFBooleanGetTypeID() {
                return .boolean(nsNumber.boolValue)
            } else if CFNumberIsFloatType(nsNumber) {
                return .double(nsNumber.doubleValue)
            } else {
                return .integer(nsNumber.intValue)
            }
        } else if let string = value as? String {
            return .string(string)
        } else {
            // For null or unknown types, return empty string
            return .string("")
        }
    }
    
    /// Reset the parser state
    func reset() {
        buffer.removeAll()
    }
}

