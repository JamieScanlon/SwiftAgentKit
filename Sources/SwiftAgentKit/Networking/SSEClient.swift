import Foundation
import Logging

public struct SSEClient {
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
} 