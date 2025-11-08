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