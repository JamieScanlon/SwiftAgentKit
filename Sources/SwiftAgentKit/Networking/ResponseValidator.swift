import Foundation
import EasyJSON
import Logging

public struct ResponseValidator {
    private let decoder: JSONDecoder
    private let logger: Logger
    
    public init(decoder: JSONDecoder? = nil, logger: Logger? = nil) {
        if let decoder = decoder {
            self.decoder = decoder
        } else {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            self.decoder = d
        }
        if let logger {
            self.logger = logger
        } else {
            self.logger = SwiftAgentKitLogging.logger(
                for: .networking("ResponseValidator")
            )
        }
    }
    
    public func validateResponse(_ response: HTTPURLResponse, data: Data) throws {
        let statusCode = response.statusCode
        
        // Log full response payload at debug level
        var responseMetadata: Logger.Metadata = [
            "status": .stringConvertible(statusCode),
            "responseBytes": .stringConvertible(data.count)
        ]
        
        // Log response headers
        let responseHeaders: [String: String] = Dictionary(uniqueKeysWithValues: response.allHeaderFields.compactMap { key, value in
            guard let keyString = key as? String, let valueString = value as? String else { return nil }
            return (keyString, valueString)
        })
        if !responseHeaders.isEmpty {
            let sortedHeaders = responseHeaders.sorted { $0.key < $1.key }
            let headerStrings = sortedHeaders.map { "\($0.key): \($0.value)" }
            responseMetadata["headers"] = .string(headerStrings.joined(separator: "\n"))
        }
        
        // Log response body
        if !data.isEmpty {
            // Try to decode as UTF-8 string first
            if let string = String(data: data, encoding: .utf8) {
                // Try to parse as JSON and pretty-print it
                if let json = try? JSONSerialization.jsonObject(with: data),
                   let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
                   let prettyString = String(data: prettyData, encoding: .utf8) {
                    responseMetadata["body"] = .string(prettyString)
                } else {
                    responseMetadata["body"] = .string(string)
                }
            } else {
                // If not UTF-8, return base64 encoded
                responseMetadata["body"] = .string(data.base64EncodedString())
            }
        }
        
        logger.debug("Full response payload", metadata: responseMetadata)
        
        guard (200...299).contains(statusCode) else {
            // Try to parse error message from response
            var errorMessage: String?
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorData["message"] as? String {
                errorMessage = message
            } else if let stringValue = String(data: data, encoding: .utf8) {
                errorMessage = String(stringValue.prefix(512))
            }
            
            var metadata: Logger.Metadata = [
                "status": .stringConvertible(statusCode),
                "responseBytes": .stringConvertible(data.count)
            ]
            if let errorMessage {
                metadata["excerpt"] = .string(errorMessage)
            }
            logger.warning("Server returned non-success status", metadata: metadata)
            throw APIError.serverError(statusCode: statusCode, message: errorMessage)
        }
    }
    
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error(
                "Failed to decode response payload",
                metadata: [
                    "type": .string(String(describing: T.self)),
                    "responseBytes": .stringConvertible(data.count),
                    "error": .string(String(describing: error))
                ]
            )
            throw APIError.decodingFailed(error)
        }
    }
    
    public func decodeJSON(from data: Data) throws -> [String: Sendable] {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Sendable] else {
                throw APIError.invalidJSON
            }
            return json
        } catch {
            logger.error(
                "Failed to decode JSON dictionary response",
                metadata: [
                    "responseBytes": .stringConvertible(data.count),
                    "error": .string(String(describing: error))
                ]
            )
            throw APIError.decodingFailed(error)
        }
    }
    
    public func decodeEasyJSON(from data: Data) throws -> JSON {
        do {
            guard let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                throw APIError.invalidJSON
            }
            
            // Convert [String: Any] to [String: JSON] manually to handle all types properly
            // This is necessary because JSONSerialization returns NSNumber for booleans,
            // and EasyJSON needs explicit handling
            let converted = convertToJSON(jsonObject)
            return converted
        } catch let error as APIError {
            throw error
        } catch {
            logger.error(
                "Failed to decode EasyJSON response",
                metadata: [
                    "responseBytes": .stringConvertible(data.count),
                    "error": .string(String(describing: error))
                ]
            )
            throw APIError.decodingFailed(error)
        }
    }
    
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
}
