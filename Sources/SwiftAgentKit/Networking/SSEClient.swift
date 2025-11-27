import Foundation
import Logging
import EasyJSON

/// URLSession delegate for handling SSE streaming
final class SSEDelegate: NSObject, URLSessionDataDelegate {
    private let continuation: AsyncStream<[String: Sendable]>.Continuation
    private let parser = SSEParser()
    private let logger: Logger
    private let endpoint: String
    private var session: URLSession? // Retain session to keep delegate alive
    
    init(continuation: AsyncStream<[String: Sendable]>.Continuation, logger: Logger, endpoint: String) {
        self.continuation = continuation
        self.logger = logger
        self.endpoint = endpoint
        super.init()
    }
    
    func setSession(_ session: URLSession) {
        self.session = session
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task {
            // Log raw data chunk at debug level
            logger.debug(
                "SSE data chunk received",
                metadata: [
                    "endpoint": .string(endpoint),
                    "chunkBytes": .stringConvertible(data.count)
                ]
            )
            
            // Log raw data content (first 1KB to avoid huge logs)
            if !data.isEmpty {
                let previewLength = min(data.count, 1024)
                let previewData = data.prefix(previewLength)
                if let previewString = String(data: previewData, encoding: .utf8) {
                    var chunkMetadata: Logger.Metadata = [
                        "endpoint": .string(endpoint),
                        "chunkPreview": .string(previewString)
                    ]
                    if data.count > previewLength {
                        chunkMetadata["chunkTruncated"] = .string("true")
                        chunkMetadata["totalChunkBytes"] = .stringConvertible(data.count)
                    }
                    logger.debug("SSE raw data chunk", metadata: chunkMetadata)
                } else {
                    logger.debug(
                        "SSE raw data chunk (binary)",
                        metadata: [
                            "endpoint": .string(endpoint),
                            "chunkBase64": .string(previewData.base64EncodedString())
                        ]
                    )
                }
            }
            
            let messages = await parser.appendChunk(data)
            
            // Log parsed messages at debug level
            for (index, message) in messages.enumerated() {
                // Serialize message for logging
                do {
                    let messageData = try JSONSerialization.data(withJSONObject: message, options: [.prettyPrinted, .sortedKeys])
                    if let messageString = String(data: messageData, encoding: .utf8) {
                        logger.debug(
                            "SSE message parsed and yielded",
                            metadata: [
                                "endpoint": .string(endpoint),
                                "messageIndex": .stringConvertible(index),
                                "messageCount": .stringConvertible(messages.count),
                                "message": .string(messageString)
                            ]
                        )
                    }
                } catch {
                    logger.debug(
                        "SSE message parsed and yielded (serialization failed)",
                        metadata: [
                            "endpoint": .string(endpoint),
                            "messageIndex": .stringConvertible(index),
                            "messageCount": .stringConvertible(messages.count),
                            "messageKeys": .string(message.keys.sorted().joined(separator: ","))
                        ]
                    )
                }
                continuation.yield(message)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task {
            if let error = error {
                logger.error(
                    "SSE request failed",
                    metadata: [
                        "endpoint": .string(endpoint),
                        "error": .string(String(describing: error))
                    ]
                )
            } else {
                // Process any remaining messages
                let finalMessages = await parser.finalize()
                
                // Log final messages at debug level
                if !finalMessages.isEmpty {
                    logger.debug(
                        "SSE finalizing with remaining messages",
                        metadata: [
                            "endpoint": .string(endpoint),
                            "finalMessageCount": .stringConvertible(finalMessages.count)
                        ]
                    )
                    
                    for (index, message) in finalMessages.enumerated() {
                        // Serialize message for logging
                        do {
                            let messageData = try JSONSerialization.data(withJSONObject: message, options: [.prettyPrinted, .sortedKeys])
                            if let messageString = String(data: messageData, encoding: .utf8) {
                                logger.debug(
                                    "SSE final message parsed and yielded",
                                    metadata: [
                                        "endpoint": .string(endpoint),
                                        "messageIndex": .stringConvertible(index),
                                        "message": .string(messageString)
                                    ]
                                )
                            }
                        } catch {
                            logger.debug(
                                "SSE final message parsed and yielded (serialization failed)",
                                metadata: [
                                    "endpoint": .string(endpoint),
                                    "messageIndex": .stringConvertible(index),
                                    "messageKeys": .string(message.keys.sorted().joined(separator: ","))
                                ]
                            )
                        }
                        continuation.yield(message)
                    }
                }
                
                logger.info(
                    "SSE request completed",
                    metadata: [
                        "endpoint": .string(endpoint),
                        "totalFinalMessages": .stringConvertible(finalMessages.count)
                    ]
                )
            }
            continuation.finish()
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Log response headers
        if let httpResponse = response as? HTTPURLResponse {
            let responseHeaders: [String: String] = Dictionary(uniqueKeysWithValues: httpResponse.allHeaderFields.compactMap { key, value in
                guard let keyString = key as? String, let valueString = value as? String else { return nil }
                return (keyString, valueString)
            })
            
            if !responseHeaders.isEmpty {
                let sortedHeaders = responseHeaders.sorted { $0.key < $1.key }
                let headerStrings = sortedHeaders.map { "\($0.key): \($0.value)" }
                logger.debug(
                    "SSE response headers",
                    metadata: [
                        "endpoint": .string(endpoint),
                        "status": .stringConvertible(httpResponse.statusCode),
                        "headers": .string(headerStrings.joined(separator: "\n"))
                    ]
                )
            }
        }
        
        // Continue receiving data
        completionHandler(.allow)
    }
}

/// URLSession delegate for handling SSE streaming with EasyJSON
final class SSEJSONDelegate: NSObject, URLSessionDataDelegate {
    private let continuation: AsyncStream<JSON>.Continuation
    private let parser = SSEJSONParser()
    private let logger: Logger
    private let endpoint: String
    private var session: URLSession? // Retain session to keep delegate alive
    
    init(continuation: AsyncStream<JSON>.Continuation, logger: Logger, endpoint: String) {
        self.continuation = continuation
        self.logger = logger
        self.endpoint = endpoint
        super.init()
    }
    
    func setSession(_ session: URLSession) {
        self.session = session
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task {
            // Log raw data chunk at debug level
            logger.debug(
                "SSE data chunk received",
                metadata: [
                    "endpoint": .string(endpoint),
                    "chunkBytes": .stringConvertible(data.count)
                ]
            )
            
            // Log raw data content (first 1KB to avoid huge logs)
            if !data.isEmpty {
                let previewLength = min(data.count, 1024)
                let previewData = data.prefix(previewLength)
                if let previewString = String(data: previewData, encoding: .utf8) {
                    var chunkMetadata: Logger.Metadata = [
                        "endpoint": .string(endpoint),
                        "chunkPreview": .string(previewString)
                    ]
                    if data.count > previewLength {
                        chunkMetadata["chunkTruncated"] = .string("true")
                        chunkMetadata["totalChunkBytes"] = .stringConvertible(data.count)
                    }
                    logger.debug("SSE raw data chunk", metadata: chunkMetadata)
                } else {
                    logger.debug(
                        "SSE raw data chunk (binary)",
                        metadata: [
                            "endpoint": .string(endpoint),
                            "chunkBase64": .string(previewData.base64EncodedString())
                        ]
                    )
                }
            }
            
            let messages = await parser.appendChunk(data)
            
            // Log parsed messages at debug level
            for (index, message) in messages.enumerated() {
                // Serialize JSON message for logging
                let messageString = serializeJSONMessage(message)
                logger.debug(
                    "SSE message parsed and yielded",
                    metadata: [
                        "endpoint": .string(endpoint),
                        "messageIndex": .stringConvertible(index),
                        "messageCount": .stringConvertible(messages.count),
                        "message": .string(messageString)
                    ]
                )
                continuation.yield(message)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task {
            if let error = error {
                logger.error(
                    "SSE request failed",
                    metadata: [
                        "endpoint": .string(endpoint),
                        "error": .string(String(describing: error))
                    ]
                )
            } else {
                // Process any remaining messages
                let finalMessages = await parser.finalize()
                
                // Log final messages at debug level
                if !finalMessages.isEmpty {
                    logger.debug(
                        "SSE finalizing with remaining messages",
                        metadata: [
                            "endpoint": .string(endpoint),
                            "finalMessageCount": .stringConvertible(finalMessages.count)
                        ]
                    )
                    
                    for (index, message) in finalMessages.enumerated() {
                        // Serialize JSON message for logging
                        let messageString = serializeJSONMessage(message)
                        logger.debug(
                            "SSE final message parsed and yielded",
                            metadata: [
                                "endpoint": .string(endpoint),
                                "messageIndex": .stringConvertible(index),
                                "message": .string(messageString)
                            ]
                        )
                        continuation.yield(message)
                    }
                }
                
                logger.info(
                    "SSE request completed",
                    metadata: [
                        "endpoint": .string(endpoint),
                        "totalFinalMessages": .stringConvertible(finalMessages.count)
                    ]
                )
            }
            continuation.finish()
        }
    }
    
    /// Serialize JSON message for logging
    private func serializeJSONMessage(_ json: JSON) -> String {
        switch json {
        case .object(let dict):
            // Convert to dictionary for JSONSerialization
            var jsonDict: [String: Any] = [:]
            for (key, value) in dict {
                jsonDict[key] = jsonValueToAny(value)
            }
            if let data = try? JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys]),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return String(describing: json)
        case .array(let array):
            let arrayAny = array.map { jsonValueToAny($0) }
            if let data = try? JSONSerialization.data(withJSONObject: arrayAny, options: [.prettyPrinted, .sortedKeys]),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return String(describing: json)
        default:
            return String(describing: json)
        }
    }
    
    /// Convert JSON value to Any for JSONSerialization
    private func jsonValueToAny(_ json: JSON) -> Any {
        switch json {
        case .object(let dict):
            var result: [String: Any] = [:]
            for (key, value) in dict {
                result[key] = jsonValueToAny(value)
            }
            return result
        case .array(let array):
            return array.map { jsonValueToAny($0) }
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
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Log response headers
        if let httpResponse = response as? HTTPURLResponse {
            let responseHeaders: [String: String] = Dictionary(uniqueKeysWithValues: httpResponse.allHeaderFields.compactMap { key, value in
                guard let keyString = key as? String, let valueString = value as? String else { return nil }
                return (keyString, valueString)
            })
            
            if !responseHeaders.isEmpty {
                let sortedHeaders = responseHeaders.sorted { $0.key < $1.key }
                let headerStrings = sortedHeaders.map { "\($0.key): \($0.value)" }
                logger.debug(
                    "SSE response headers",
                    metadata: [
                        "endpoint": .string(endpoint),
                        "status": .stringConvertible(httpResponse.statusCode),
                        "headers": .string(headerStrings.joined(separator: "\n"))
                    ]
                )
            }
        }
        
        // Continue receiving data
        completionHandler(.allow)
    }
}

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
            
            // Log full request payload at debug level
            var fullRequestMetadata: Logger.Metadata = [
                "endpoint": .string(endpoint),
                "method": .string(method.rawValue),
                "fullURL": .string(request.url?.absoluteString ?? url.absoluteString)
            ]
            
            // Log all headers
            if let allHeaders = request.allHTTPHeaderFields, !allHeaders.isEmpty {
                let sortedHeaders = allHeaders.sorted { $0.key < $1.key }
                let headerStrings = sortedHeaders.map { "\($0.key): \($0.value)" }
                fullRequestMetadata["headers"] = .string(headerStrings.joined(separator: "\n"))
            }
            
            // Log request body
            if let body = request.httpBody, !body.isEmpty {
                if let string = String(data: body, encoding: .utf8) {
                    if let json = try? JSONSerialization.jsonObject(with: body),
                       let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
                       let prettyString = String(data: prettyData, encoding: .utf8) {
                        fullRequestMetadata["body"] = .string(prettyString)
                    } else {
                        fullRequestMetadata["body"] = .string(string)
                    }
                } else {
                    fullRequestMetadata["body"] = .string(body.base64EncodedString())
                }
            }
            
            logger.debug("Full SSE request payload", metadata: fullRequestMetadata)
            // Set timeout on the request itself as well (though session config takes precedence)
            request.timeoutInterval = self.timeoutInterval
            
            // Use streaming delegate for incremental SSE parsing
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = self.timeoutInterval
            config.timeoutIntervalForResource = self.timeoutInterval
            let delegate = SSEDelegate(continuation: continuation, logger: self.logger, endpoint: endpoint)
            // Create session with delegate (delegate retains session to keep it alive)
            let delegateSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            delegate.setSession(delegateSession)
            let task = delegateSession.dataTask(with: request)
            task.resume()
            
            continuation.onTermination = { _ in
                task.cancel()
                self.logger.debug(
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
            
            // Log full request payload at debug level
            var fullRequestMetadata: Logger.Metadata = [
                "endpoint": .string(endpoint),
                "method": .string(method.rawValue),
                "fullURL": .string(request.url?.absoluteString ?? url.absoluteString)
            ]
            
            // Log all headers
            if let allHeaders = request.allHTTPHeaderFields, !allHeaders.isEmpty {
                let sortedHeaders = allHeaders.sorted { $0.key < $1.key }
                let headerStrings = sortedHeaders.map { "\($0.key): \($0.value)" }
                fullRequestMetadata["headers"] = .string(headerStrings.joined(separator: "\n"))
            }
            
            // Log request body
            if let body = request.httpBody, !body.isEmpty {
                if let string = String(data: body, encoding: .utf8) {
                    if let json = try? JSONSerialization.jsonObject(with: body),
                       let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
                       let prettyString = String(data: prettyData, encoding: .utf8) {
                        fullRequestMetadata["body"] = .string(prettyString)
                    } else {
                        fullRequestMetadata["body"] = .string(string)
                    }
                } else {
                    fullRequestMetadata["body"] = .string(body.base64EncodedString())
                }
            }
            
            logger.debug("Full SSE request payload", metadata: fullRequestMetadata)
            // Set timeout on the request itself as well (though session config takes precedence)
            request.timeoutInterval = self.timeoutInterval
            
            // Use streaming delegate for incremental SSE parsing
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = self.timeoutInterval
            config.timeoutIntervalForResource = self.timeoutInterval
            let delegate = SSEJSONDelegate(continuation: continuation, logger: self.logger, endpoint: endpoint)
            // Create session with delegate (delegate retains session to keep it alive)
            let delegateSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            delegate.setSession(delegateSession)
            let task = delegateSession.dataTask(with: request)
            task.resume()
            
            continuation.onTermination = { _ in
                task.cancel()
                self.logger.debug(
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
