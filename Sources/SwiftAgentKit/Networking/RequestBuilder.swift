import Foundation

public struct RequestBuilder {
    public let baseURL: URL
    
    public init(baseURL: URL) {
        self.baseURL = baseURL
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
        
        // Add parameters
        if let parameters = parameters {
            switch method {
            case .get, .delete:
                if var components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
                    components.queryItems = parameters.map { key, value in
                        URLQueryItem(name: key, value: "\(value)")
                    }
                    request.url = components.url
                }
            case .post, .put, .patch:
                do {
                    if let data = body {
                        request.httpBody = data
                    } else {
                        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
                    }
                } catch {
                    throw APIError.requestFailed(error)
                }
            }
        }
        return request
    }
} 