import Foundation
import Logging

public struct RequestBuilder {
    public let baseURL: URL
    private let logger: Logger
    
    public init(baseURL: URL, logger: Logger? = nil) {
        self.baseURL = baseURL
        if let logger {
            self.logger = logger
        } else {
            let metadata: Logger.Metadata = ["baseURL": .string(baseURL.absoluteString)]
            self.logger = SwiftAgentKitLogging.logger(
                for: .networking("RequestBuilder"),
                metadata: metadata
            )
        }
    }
    
    public func createRequest(endpoint: String,
                               method: HTTPMethod,
                               parameters: [String: Any]? = nil,
                               headers: [String: String]? = nil,
                               body: Data? = nil) throws -> URLRequest {
        // Create URL
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        
        // Add headers
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        headers?.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        // Add query parameters for GET/DELETE
        if let parameters = parameters, (method == .get || method == .delete) {
            if var components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
                components.queryItems = parameters.map { key, value in
                    URLQueryItem(name: key, value: "\(value)")
                }
                request.url = components.url
            }
        }

        // Add body for POST/PUT/PATCH
        switch method {
        case .post, .put, .patch:
            do {
                if let data = body {
                    request.httpBody = data
                } else if let parameters = parameters {
                    // Validate JSON before attempting serialization to avoid Objective-C exceptions
                    guard JSONSerialization.isValidJSONObject(parameters) else {
                        throw APIError.invalidJSON
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
                }
            } catch {
                logger.warning(
                    "Failed to encode request body",
                    metadata: [
                        "endpoint": .string(endpoint),
                        "method": .string(method.rawValue),
                        "error": .string(String(describing: error))
                    ]
                )
                throw APIError.requestFailed(error)
            }
        default:
            break
        }
        
        var debugMetadata: Logger.Metadata = [
            "endpoint": .string(endpoint),
            "method": .string(method.rawValue),
            "url": .string(request.url?.absoluteString ?? url.absoluteString),
            "headerCount": .stringConvertible(request.allHTTPHeaderFields?.count ?? 0)
        ]
        if let parameters {
            debugMetadata["parameterCount"] = .stringConvertible(parameters.count)
        }
        if let body = request.httpBody {
            debugMetadata["bodyBytes"] = .stringConvertible(body.count)
        }
        logger.debug("Constructed URL request", metadata: debugMetadata)
        
        // Log full request details at debug level
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
        
            // Log query parameters for GET/DELETE
            if let parameters = parameters, (method == .get || method == .delete) {
                do {
                    if JSONSerialization.isValidJSONObject(parameters) {
                        let data = try JSONSerialization.data(withJSONObject: parameters, options: [.prettyPrinted, .sortedKeys])
                        if let jsonString = String(data: data, encoding: .utf8) {
                            fullRequestMetadata["queryParameters"] = .string(jsonString)
                        }
                    } else {
                        fullRequestMetadata["queryParameters"] = .string(String(describing: parameters))
                    }
                } catch {
                    fullRequestMetadata["queryParameters"] = .string(String(describing: parameters))
                }
            }
        
        // Log request body
        if let body = request.httpBody, !body.isEmpty {
            // Try to decode as UTF-8 string first
            if let string = String(data: body, encoding: .utf8) {
                // Try to parse as JSON and pretty-print it
                if let json = try? JSONSerialization.jsonObject(with: body),
                   let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
                   let prettyString = String(data: prettyData, encoding: .utf8) {
                    fullRequestMetadata["body"] = .string(prettyString)
                } else {
                    fullRequestMetadata["body"] = .string(string)
                }
            } else {
                // If not UTF-8, return base64 encoded
                fullRequestMetadata["body"] = .string(body.base64EncodedString())
            }
        }
        
        logger.debug("Full request details", metadata: fullRequestMetadata)
        return request
    }
}