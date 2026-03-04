// OAuth Authentication Handler for Manual Flow
// Completes manual OAuth flow using SwiftAgentKit PKCE and OAuthManualFlowRequired metadata only.

import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// OAuth authentication error types for manual flow
public enum OAuthError: Error, LocalizedError {
    case invalidURL
    case userCancelled
    case networkError(String)
    case authorizationCodeNotFound
    case tokenExchangeFailed(String)
    case invalidTokenResponse
    case oauthError(String, String?) // error, error_description
    case incorrectClientCredentials
    case invalidGrant
    case unsupportedGrantType
    case invalidScope
    case serverError(String)
    case invalidConfiguration(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid OAuth URL"
        case .userCancelled:
            return "User cancelled authentication"
        case .networkError(let message):
            return "Network error: \(message)"
        case .authorizationCodeNotFound:
            return "Authorization code not found in callback"
        case .tokenExchangeFailed(let message):
            return "Token exchange failed: \(message)"
        case .invalidTokenResponse:
            return "Invalid token response format"
        case .oauthError(let error, let description):
            return "OAuth error: \(error)\(description.map { " - \($0)" } ?? "")"
        case .incorrectClientCredentials:
            return "Incorrect client credentials - check your client_id and client_secret"
        case .invalidGrant:
            return "Invalid grant - the authorization code may be expired or already used"
        case .unsupportedGrantType:
            return "Unsupported grant type"
        case .invalidScope:
            return "Invalid scope requested"
        case .serverError(let message):
            return "OAuth server error: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid OAuth configuration: \(message)"
        }
    }
}

/// OAuth token response structure (manual flow)
public struct OAuthToken: Codable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int?
    public let refreshToken: String?
    public let scope: String?
    
    public init(accessToken: String, tokenType: String, expiresIn: Int? = nil, refreshToken: String? = nil, scope: String? = nil) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.scope = scope
    }
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

/// OAuth error response structure
public struct OAuthErrorResponse: Codable, Sendable {
    public let error: String
    public let errorDescription: String?
    public let errorUri: String?
    
    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case errorUri = "error_uri"
    }
}

/// OAuth authenticator for manual flow (OAuthManualFlowRequired).
/// Accepts optional callback receiver, token exchanger, and URL opener for composability.
@MainActor
public class OAuthAuthenticator: ObservableObject {
    private let callbackReceiver: (any OAuthCallbackReceiver)?
    private let tokenExchanger: (any OAuthTokenExchanger)?
    private let urlOpener: (@Sendable (URL) -> Void)?
    
    /// - Parameters:
    ///   - callbackReceiver: Receives the OAuth redirect and returns the authorization code. If `nil`, a default `OAuthCallbackServer` is created from the redirect URI when needed.
    ///   - tokenExchanger: Performs the token endpoint HTTP exchange. If `nil`, uses `DefaultOAuthTokenExchanger` (URLSession + standard parsing).
    ///   - urlOpener: Opens the authorization URL (e.g. in browser). If `nil`, uses `OAuthCallbackServer.openAuthorizationURL` on macOS.
    public init(
        callbackReceiver: (any OAuthCallbackReceiver)? = nil,
        tokenExchanger: (any OAuthTokenExchanger)? = nil,
        urlOpener: (@Sendable (URL) -> Void)? = nil
    ) {
        self.callbackReceiver = callbackReceiver
        self.tokenExchanger = tokenExchanger
        self.urlOpener = urlOpener
    }
}

// MARK: - Manual flow (PKCE, use error metadata)
extension OAuthAuthenticator {
    /// Completes the OAuth manual flow using OAuthManualFlowRequired.
    /// Generates PKCE in-process so we can send code_verifier at token exchange; builds auth URL
    /// from the error's metadata (no duplicate URL building).
    public func completeManualOAuthFlow(
        oauthFlowError: OAuthManualFlowRequired,
        clientId: String,
        clientSecret: String?
    ) async throws -> OAuthToken {
        guard let authEndpoint = oauthFlowError.additionalMetadata["authorization_endpoint"],
              let tokenEndpoint = oauthFlowError.additionalMetadata["token_endpoint"],
              URL(string: authEndpoint) != nil,
              URL(string: tokenEndpoint) != nil else {
            throw OAuthError.invalidURL
        }
        
        let pkcePair = try PKCEUtilities.generatePKCEPair()
        var components = URLComponents(string: authEndpoint)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: oauthFlowError.redirectURI.absoluteString),
            URLQueryItem(name: "code_challenge", value: pkcePair.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: pkcePair.codeChallengeMethod)
        ]
        if let scope = oauthFlowError.scope, !scope.isEmpty {
            queryItems.append(URLQueryItem(name: "scope", value: scope))
        }
        if let resourceURI = oauthFlowError.resourceURI {
            queryItems.append(URLQueryItem(name: "resource", value: resourceURI))
        }
        components?.queryItems = queryItems
        guard let authURL = components?.url else {
            throw OAuthError.invalidURL
        }
        
        let port = UInt16(oauthFlowError.redirectURI.port ?? 8080)
        let path = oauthFlowError.redirectURI.path.isEmpty ? "/oauth/callback" : oauthFlowError.redirectURI.path
        let receiver: any OAuthCallbackReceiver = callbackReceiver ?? OAuthCallbackServer(port: port, callbackPath: path)
        
        if let urlOpener = urlOpener {
            urlOpener(authURL)
        } else {
            OAuthCallbackServer.openAuthorizationURL(authURL)
        }
        let result = try await receiver.waitForCallback(timeout: 300)
        
        if let error = result.error {
            throw OAuthError.networkError("OAuth error: \(error)")
        }
        guard let authorizationCode = result.authorizationCode else {
            throw OAuthError.authorizationCodeNotFound
        }
        
        let exchanger = tokenExchanger ?? DefaultOAuthTokenExchanger()
        return try await exchanger.exchangeCodeForToken(
            authorizationCode: authorizationCode,
            tokenEndpoint: tokenEndpoint,
            clientId: clientId,
            clientSecret: clientSecret,
            redirectURI: oauthFlowError.redirectURI.absoluteString,
            codeVerifier: pkcePair.codeVerifier,
            resourceURI: oauthFlowError.resourceURI
        )
    }
    
    /// Token exchange for authorization_code grant with optional PKCE (code_verifier) and resource.
    /// Uses the configured token exchanger, or `DefaultOAuthTokenExchanger` if none was provided.
    public func exchangeCodeForToken(
        authorizationCode: String,
        tokenEndpoint: String,
        clientId: String,
        clientSecret: String?,
        redirectURI: String,
        codeVerifier: String?,
        resourceURI: String?
    ) async throws -> OAuthToken {
        let exchanger = tokenExchanger ?? DefaultOAuthTokenExchanger()
        return try await exchanger.exchangeCodeForToken(
            authorizationCode: authorizationCode,
            tokenEndpoint: tokenEndpoint,
            clientId: clientId,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            codeVerifier: codeVerifier,
            resourceURI: resourceURI
        )
    }
}
