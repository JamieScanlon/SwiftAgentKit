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
                throw APIError.requestFailed(error)
            }
        default:
            break
        }
        return request
    }
} 