import Foundation

public struct StreamClient {
    private let requestBuilder: RequestBuilder
    public init(requestBuilder: RequestBuilder) {
        self.requestBuilder = requestBuilder
    }
    
    public func streamRequest(_ endpoint: String,
                                method: HTTPMethod = .get,
                                parameters: [String: Any]? = nil,
                                headers: [String: String]? = nil) -> AsyncStream<StreamingDataBuffer> {
        let (stream, continuation) = AsyncStream<StreamingDataBuffer>.makeStream()
        do {
            let delegate = StreamDelegate(continuation: continuation)
            let streamSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let request = try requestBuilder.createRequest(endpoint: endpoint, method: method, parameters: parameters, headers: headers)
            let dataTask = streamSession.dataTask(with: request)
            dataTask.resume()
            continuation.onTermination = { @Sendable _ in
                dataTask.cancel()
                continuation.finish()
            }
        } catch {
            continuation.finish()
        }
        return stream
    }
}

final class StreamDelegate: NSObject, URLSessionDataDelegate {
    private let continuation: AsyncStream<StreamingDataBuffer>.Continuation
    private let buffer = StreamingDataBuffer()
    private let decoder = JSONDecoder()
    let completionHandler: (@Sendable () -> Void)? = nil
    
    init(continuation: AsyncStream<StreamingDataBuffer>.Continuation) {
        self.continuation = continuation
        super.init()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task {
            await buffer.append(data)
            continuation.yield(buffer)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Stream error: \(error)")
        }
        continuation.yield(buffer)
        continuation.finish()
        completionHandler?()
    }
} 