import Foundation
import EasyJSON

public struct ResponseValidator {
    private let decoder: JSONDecoder
    
    public init(decoder: JSONDecoder? = nil) {
        if let decoder = decoder {
            self.decoder = decoder
        } else {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            self.decoder = d
        }
    }
    
    public func validateResponse(_ response: HTTPURLResponse, data: Data) throws {
        let statusCode = response.statusCode
        guard (200...299).contains(statusCode) else {
            // Try to parse error message from response
            var errorMessage: String?
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorData["message"] as? String {
                errorMessage = message
            } else if let stringValue = String(data: data, encoding: .utf8) {
                errorMessage = stringValue
            }
            throw APIError.serverError(statusCode: statusCode, message: errorMessage)
        }
    }
    
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
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
