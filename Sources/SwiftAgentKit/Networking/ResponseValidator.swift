import Foundation

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
} 