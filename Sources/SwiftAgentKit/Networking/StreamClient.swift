import Foundation
import Logging

public struct StreamClient {
    private let requestBuilder: RequestBuilder
    private let logger: Logger
    
    public init(requestBuilder: RequestBuilder, logger: Logger?) {
        self.requestBuilder = requestBuilder
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .networking("StreamClient")
        )
    }
    
    public init(requestBuilder: RequestBuilder) {
        self.init(requestBuilder: requestBuilder, logger: nil)
    }
    
    public func streamRequest(_ endpoint: String,
                                method: HTTPMethod = .get,
                                parameters: [String: Any]? = nil,
                                headers: [String: String]? = nil) -> AsyncStream<StreamingDataBuffer> {
        let logging = logger
        let (stream, continuation) = AsyncStream<StreamingDataBuffer>.makeStream()
        logging.info(
            "Opening streaming request",
            metadata: [
                "endpoint": .string(endpoint),
                "method": .string(method.rawValue),
                "parameterCount": .stringConvertible(parameters?.count ?? 0),
                "headerCount": .stringConvertible(headers?.count ?? 0)
            ]
        )
        do {
            let delegate = StreamDelegate(continuation: continuation, logger: logging)
            let streamSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let request = try requestBuilder.createRequest(endpoint: endpoint, method: method, parameters: parameters, headers: headers)
            
            // Log full request payload at debug level
            var fullRequestMetadata: Logger.Metadata = [
                "endpoint": .string(endpoint),
                "method": .string(method.rawValue),
                "fullURL": .string(request.url?.absoluteString ?? "")
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
            
            logging.debug("Full streaming request payload", metadata: fullRequestMetadata)
            
            let dataTask = streamSession.dataTask(with: request)
            dataTask.resume()
            continuation.onTermination = { @Sendable _ in
                dataTask.cancel()
                logging.debug(
                    "Streaming request cancelled",
                    metadata: [
                        "endpoint": .string(endpoint),
                        "method": .string(method.rawValue)
                    ]
                )
                continuation.finish()
            }
        } catch {
            logging.error(
                "Failed to start streaming request",
                metadata: [
                    "endpoint": .string(endpoint),
                    "method": .string(method.rawValue),
                    "error": .string(String(describing: error))
                ]
            )
            continuation.finish()
        }
        return stream
    }
}

final class StreamDelegate: NSObject, URLSessionDataDelegate {
    private let continuation: AsyncStream<StreamingDataBuffer>.Continuation
    private let buffer = StreamingDataBuffer()
    private let decoder = JSONDecoder()
    private let logger: Logger
    let completionHandler: (@Sendable () -> Void)? = nil
    
    init(continuation: AsyncStream<StreamingDataBuffer>.Continuation, logger: Logger) {
        self.continuation = continuation
        self.logger = logger
        super.init()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task {
            await buffer.append(data)
            logger.debug(
                "Streaming chunk received",
                metadata: ["bytes": .stringConvertible(data.count)]
            )
            continuation.yield(buffer)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            logger.error(
                "Streaming request failed",
                metadata: ["error": .string(String(describing: error))]
            )
        } else {
            logger.info("Streaming request completed")
        }
        continuation.yield(buffer)
        continuation.finish()
        completionHandler?()
    }
}