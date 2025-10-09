import Foundation
import Logging
import EasyJSON

public struct SSEClient: Sendable {
    private let baseURL: URL
    private let logger = Logger(label: "SSEClient")
    
    public init(baseURL: URL) {
        self.baseURL = baseURL
    }
    
    public func sseRequest(_ endpoint: String,
                            method: HTTPMethod = .post,
                            parameters: [String: Sendable]? = nil,
                            headers: [String: String]? = nil) -> AsyncStream<[String: Sendable]> {
        return AsyncStream { continuation in
            let url = baseURL.appendingPathComponent(endpoint)
            var request = URLRequest(url: url)
            request.httpMethod = method.rawValue
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            headers?.forEach { key, value in
                request.setValue(value, forHTTPHeaderField: key)
            }
            if let parameters = parameters, method == .post {
                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
                } catch {
                    self.logger.error("SSE Error: Failed to serialize parameters: \(error)")
                    continuation.finish()
                    return
                }
            }
            let session = URLSession.shared
            let logger = self.logger
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    logger.error("SSE Error: \(error)")
                    continuation.finish()
                    return
                }
                guard let data = data,
                      let responseString = String(data: data, encoding: .utf8) else {
                    continuation.finish()
                    return
                }
                let lines = responseString.components(separatedBy: "\n")
                for line in lines {
                    if line.hasPrefix("data: ") {
                        let jsonString = String(line.dropFirst(6))
                        if let data = jsonString.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Sendable] {
                            continuation.yield(json)
                        }
                    }
                }
                continuation.finish()
            }
            task.resume()
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    public func sseRequest(_ endpoint: String,
                                method: HTTPMethod = .post,
                                parameters: JSON? = nil,
                                headers: [String: String]? = nil) -> AsyncStream<JSON> {
        return AsyncStream { continuation in
            let url = baseURL.appendingPathComponent(endpoint)
            var request = URLRequest(url: url)
            request.httpMethod = method.rawValue
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            headers?.forEach { key, value in
                request.setValue(value, forHTTPHeaderField: key)
            }
            if let parameters = parameters, method == .post {
                do {
                    // Convert JSON to Data for the request body
                    let parametersDict = try self.jsonToAny(parameters)
                    request.httpBody = try JSONSerialization.data(withJSONObject: parametersDict)
                } catch {
                    self.logger.error("SSE Error: Failed to serialize parameters: \(error)")
                    continuation.finish()
                    return
                }
            }
            let session = URLSession.shared
            let logger = self.logger
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    logger.error("SSE Error: \(error)")
                    continuation.finish()
                    return
                }
                guard let data = data,
                      let responseString = String(data: data, encoding: .utf8) else {
                    continuation.finish()
                    return
                }
                let lines = responseString.components(separatedBy: "\n")
                for line in lines {
                    if line.hasPrefix("data: ") {
                        let jsonString = String(line.dropFirst(6))
                        if let data = jsonString.data(using: .utf8),
                           let jsonObject = try? JSONSerialization.jsonObject(with: data) {
                            let json = self.convertToJSON(jsonObject)
                            continuation.yield(json)
                        }
                    }
                }
                continuation.finish()
            }
            task.resume()
            continuation.onTermination = { _ in
                task.cancel()
            }
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
    
    private func jsonToAny(_ json: JSON) throws -> Any {
        switch json {
        case .object(let dict):
            var result: [String: Any] = [:]
            for (key, value) in dict {
                result[key] = try jsonToAny(value)
            }
            return result
        case .array(let array):
            return try array.map { try jsonToAny($0) }
        case .string(let string):
            return string
        case .integer(let int):
            return int
        case .double(let double):
            return double
        case .boolean(let bool):
            return bool
        }
    }
} 
