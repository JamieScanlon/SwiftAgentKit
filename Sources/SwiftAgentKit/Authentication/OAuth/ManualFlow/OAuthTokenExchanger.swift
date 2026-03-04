// OAuth Token Exchanger Protocol and Default Implementation
// Allows swapping the HTTP layer used to exchange an authorization code for tokens.

import Foundation

/// A type that can exchange an OAuth authorization code for tokens at the token endpoint.
/// Implement this to use a custom HTTP client, proxy, or test double.
public protocol OAuthTokenExchanger: Sendable {
    /// Exchanges an authorization code for access (and optionally refresh) tokens.
    func exchangeCodeForToken(
        authorizationCode: String,
        tokenEndpoint: String,
        clientId: String,
        clientSecret: String?,
        redirectURI: String,
        codeVerifier: String?,
        resourceURI: String?
    ) async throws -> OAuthToken
}

/// Default token exchanger using URLSession and standard JSON/form response parsing.
public struct DefaultOAuthTokenExchanger: OAuthTokenExchanger, Sendable {
    public init() {}
    
    public func exchangeCodeForToken(
        authorizationCode: String,
        tokenEndpoint: String,
        clientId: String,
        clientSecret: String?,
        redirectURI: String,
        codeVerifier: String?,
        resourceURI: String?
    ) async throws -> OAuthToken {
        guard let tokenURL = URL(string: tokenEndpoint) else {
            throw OAuthError.invalidURL
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var bodyItems: [URLQueryItem] = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code", value: authorizationCode),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]
        if let codeVerifier = codeVerifier {
            bodyItems.append(URLQueryItem(name: "code_verifier", value: codeVerifier))
        }
        if let resourceURI = resourceURI {
            bodyItems.append(URLQueryItem(name: "resource", value: resourceURI))
        }
        if let clientSecret = clientSecret {
            bodyItems.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = bodyItems
        request.httpBody = bodyComponents.query?.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.networkError("Invalid response")
        }
        guard 200...299 ~= httpResponse.statusCode else {
            if let oauthError = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
                throw Self.parseOAuthError(oauthError)
            }
            if let errorString = String(data: data, encoding: .utf8), let formError = Self.parseFormEncodedError(errorString) {
                throw formError
            }
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(message)")
        }
        if let token = try? JSONDecoder().decode(OAuthToken.self, from: data) {
            return token
        }
        if let errorString = String(data: data, encoding: .utf8), let token = Self.parseFormEncodedToken(errorString) {
            return token
        }
        throw OAuthError.invalidTokenResponse
    }
    
    private static func parseOAuthError(_ errorResponse: OAuthErrorResponse) -> OAuthError {
        switch errorResponse.error {
        case "invalid_client":
            return .incorrectClientCredentials
        case "invalid_grant":
            return .invalidGrant
        case "unsupported_grant_type":
            return .unsupportedGrantType
        case "invalid_scope":
            return .invalidScope
        case "server_error":
            return .serverError(errorResponse.errorDescription ?? "Unknown server error")
        default:
            return .oauthError(errorResponse.error, errorResponse.errorDescription)
        }
    }
    
    private static func parseFormEncodedError(_ errorString: String) -> OAuthError? {
        guard let components = URLComponents(string: "?" + errorString),
              let queryItems = components.queryItems else {
            return nil
        }
        var error: String?
        var errorDescription: String?
        for item in queryItems {
            switch item.name {
            case "error": error = item.value
            case "error_description": errorDescription = item.value?.removingPercentEncoding
            default: break
            }
        }
        guard let errorValue = error else { return nil }
        switch errorValue {
        case "incorrect_client_credentials": return .incorrectClientCredentials
        case "invalid_grant": return .invalidGrant
        case "unsupported_grant_type": return .unsupportedGrantType
        case "invalid_scope": return .invalidScope
        case "server_error": return .serverError(errorDescription ?? "Unknown server error")
        default: return .oauthError(errorValue, errorDescription)
        }
    }
    
    private static func parseFormEncodedToken(_ tokenString: String) -> OAuthToken? {
        guard let components = URLComponents(string: "?" + tokenString),
              let queryItems = components.queryItems else {
            return nil
        }
        var accessToken: String?
        var tokenType: String?
        var expiresIn: Int?
        var refreshToken: String?
        var scope: String?
        for item in queryItems {
            switch item.name {
            case "access_token": accessToken = item.value
            case "token_type": tokenType = item.value
            case "expires_in": if let v = item.value { expiresIn = Int(v) }
            case "refresh_token": refreshToken = item.value
            case "scope": scope = item.value
            default: break
            }
        }
        guard let at = accessToken, let tt = tokenType else { return nil }
        return OAuthToken(accessToken: at, tokenType: tt, expiresIn: expiresIn, refreshToken: refreshToken, scope: scope)
    }
}
