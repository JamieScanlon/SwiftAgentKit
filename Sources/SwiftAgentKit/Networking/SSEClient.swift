import Foundation
import Logging
import EasyJSON

public struct SSEClient: Sendable {
    private let baseURL: URL
    private let logger: Logger
    private let session: URLSession
    private let timeoutInterval: TimeInterval
    
    /// Initialize SSEClient with configurable timeout
    /// - Parameters:
    ///   - baseURL: The base URL for SSE requests
    ///   - session: Optional custom URLSession. If nil, a session with the specified timeout will be created
    ///   - timeoutInterval: Timeout interval in seconds for SSE connections (default: 600 seconds / 10 minutes)
    ///   - logger: Optional logger instance
    public init(baseURL: URL, session: URLSession? = nil, timeoutInterval: TimeInterval = 600.0, logger: Logger? = nil) {
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
        
        if let logger {
            self.logger = logger
        } else {
            let metadata: Logger.Metadata = ["baseURL": .string(baseURL.absoluteString)]
            self.logger = SwiftAgentKitLogging.logger(
                for: .networking("SSEClient"),
                metadata: metadata
            )
        }
        
        // Create a session with configured timeouts for SSE streams if not provided
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = timeoutInterval
            config.timeoutIntervalForResource = timeoutInterval
            self.session = URLSession(configuration: config)
        }
    }
    
    public init(baseURL: URL) {
        self.init(baseURL: baseURL, session: nil, timeoutInterval: 600.0, logger: nil)
    }
    
    public func sseRequest(_ endpoint: String,
                            method: HTTPMethod = .post,
                            parameters: [String: Sendable]? = nil,
                            headers: [String: String]? = nil) -> AsyncStream<[String: Sendable]> {
        return AsyncStream { continuation in
            logger.info(
                "Opening SSE connection",
                metadata: [
                    "endpoint": .string(endpoint),
                    "method": .string(method.rawValue),
                    "parameterCount": .stringConvertible(parameters?.count ?? 0),
                    "headerCount": .stringConvertible(headers?.count ?? 0)
                ]
            )
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
                    logger.debug(
                        "Serialized SSE parameters",
                        metadata: [
                            "endpoint": .string(endpoint),
                            "parameterKeys": .string(parameters.keys.sorted().joined(separator: ",")),
                            "bodyBytes": .stringConvertible(request.httpBody?.count ?? 0)
                        ]
                    )
                } catch {
                    self.logger.error(
                        "Failed to serialize SSE parameters",
                        metadata: [
                            "endpoint": .string(endpoint),
                            "error": .string(String(describing: error))
                        ]
                    )
                    continuation.finish()
                    return
                }
            }
            // Set timeout on the request itself as well (though session config takes precedence)
            request.timeoutInterval = self.timeoutInterval
            
            let logger = self.logger
            let task = self.session.dataTask(with: request) { data, response, error in
                if let error = error {
                    logger.error(
                        "SSE request failed",
                        metadata: [
                            "endpoint": .string(endpoint),
                            "error": .string(String(describing: error))
                        ]
                    )
                    continuation.finish()
                    return
                }
                guard let data = data,
                      let responseString = String(data: data, encoding: .utf8) else {
                    logger.warning(
                        "SSE request returned empty response",
                        metadata: ["endpoint": .string(endpoint)]
                    )
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
                logger.info(
                    "SSE request completed",
                    metadata: ["endpoint": .string(endpoint)]
                )
                continuation.finish()
            }
            task.resume()
            continuation.onTermination = { _ in
                task.cancel()
                logger.debug(
                    "SSE request cancelled",
                    metadata: ["endpoint": .string(endpoint)]
                )
            }
        }
    }
    
    public func sseRequest(_ endpoint: String,
                                method: HTTPMethod = .post,
                                parameters: JSON? = nil,
                                headers: [String: String]? = nil) -> AsyncStream<JSON> {
        return AsyncStream { continuation in
            logger.info(
                "Opening SSE connection",
                metadata: [
                    "endpoint": .string(endpoint),
                    "method": .string(method.rawValue),
                    "hasParameters": .string(parameters == nil ? "false" : "true"),
                    "headerCount": .stringConvertible(headers?.count ?? 0)
                ]
            )
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
                    logger.debug(
                        "Serialized SSE parameters",
                        metadata: [
                            "endpoint": .string(endpoint),
                            "bodyBytes": .stringConvertible(request.httpBody?.count ?? 0)
                        ]
                    )
                } catch {
                    self.logger.error(
                        "Failed to serialize SSE parameters",
                        metadata: [
                            "endpoint": .string(endpoint),
                            "error": .string(String(describing: error))
                        ]
                    )
                    continuation.finish()
                    return
                }
            }
            // Set timeout on the request itself as well (though session config takes precedence)
            request.timeoutInterval = self.timeoutInterval
            
            let logger = self.logger
            let task = self.session.dataTask(with: request) { data, response, error in
                if let error = error {
                    logger.error(
                        "SSE request failed",
                        metadata: [
                            "endpoint": .string(endpoint),
                            "error": .string(String(describing: error))
                        ]
                    )
                    continuation.finish()
                    return
                }
                guard let data = data,
                      let responseString = String(data: data, encoding: .utf8) else {
                    logger.warning(
                        "SSE request returned empty response",
                        metadata: ["endpoint": .string(endpoint)]
                    )
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
                logger.info(
                    "SSE request completed",
                    metadata: ["endpoint": .string(endpoint)]
                )
                continuation.finish()
            }
            task.resume()
            continuation.onTermination = { _ in
                task.cancel()
                logger.debug(
                    "SSE request cancelled",
                    metadata: ["endpoint": .string(endpoint)]
                )
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
