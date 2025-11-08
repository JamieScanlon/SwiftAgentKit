//
//  OAuthDiscoveryManager.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Foundation
import Logging

/// OAuth Discovery Manager that orchestrates the complete discovery process
/// Implements the flow described in the MCP Auth specification
public actor OAuthDiscoveryManager {
    
    private let logger: Logger
    private let urlSession: URLSession
    private let protectedResourceClient: ProtectedResourceMetadataClient
    private let oauthServerClient: OAuthServerMetadataClient
    
    public init(
        urlSession: URLSession,
        logger: Logger?
    ) {
        self.urlSession = urlSession
        let resolvedLogger = logger ?? SwiftAgentKitLogging.logger(
            for: .authentication("OAuthDiscoveryManager")
        )
        self.logger = resolvedLogger
        self.protectedResourceClient = ProtectedResourceMetadataClient(
            urlSession: urlSession,
            logger: SwiftAgentKitLogging.logger(
                for: .authentication("ProtectedResourceMetadataClient"),
                metadata: ["manager": .string("OAuthDiscovery")]
            )
        )
        self.oauthServerClient = OAuthServerMetadataClient(
            urlSession: urlSession,
            logger: SwiftAgentKitLogging.logger(
                for: .authentication("OAuthServerMetadataClient"),
                metadata: ["manager": .string("OAuthDiscovery")]
            )
        )
    }
    
    public init(urlSession: URLSession = .shared) {
        self.init(urlSession: urlSession, logger: nil)
    }
    
    /// Discover authorization server metadata following the complete MCP Auth flow
    /// This implements the full discovery process as described in the specification
    /// - Parameters:
    ///   - resourceServerURL: URL of the MCP server (Resource Server)
    ///   - resourceType: Type of resource (e.g., "mcp" for MCP servers)
    ///   - preConfiguredAuthServerURL: Pre-configured authorization server URL (optional)
    /// - Returns: Complete OAuth server metadata for authentication
    /// - Throws: OAuthDiscoveryError if discovery fails
    public func discoverAuthorizationServerMetadata(
        resourceServerURL: URL,
        resourceType: String? = "mcp",
        preConfiguredAuthServerURL: URL? = nil
    ) async throws -> OAuthServerMetadata {
        
        logger.info(
            "Starting OAuth discovery process",
            metadata: ["resourceServerURL": .string(resourceServerURL.absoluteString)]
        )
        
        // Step 1: Try pre-configured authorization server URL first
        if let preConfiguredURL = preConfiguredAuthServerURL {
            logger.info(
                "Using pre-configured authorization server URL",
                metadata: ["authorizationServerURL": .string(preConfiguredURL.absoluteString)]
            )
            do {
                let metadata = try await oauthServerClient.discoverAuthorizationServerMetadata(issuerURL: preConfiguredURL)
                logger.info("Successfully discovered authorization server metadata using pre-configured URL")
                return metadata
            } catch {
                logger.warning(
                    "Pre-configured authorization server URL failed",
                    metadata: ["error": .string(String(describing: error))]
                )
                // Continue with discovery process
            }
        }
        
        // Step 2: Make an unauthenticated request to trigger discovery
        let challenge = try await makeUnauthenticatedRequest(to: resourceServerURL)
        
        // Step 3: Discover protected resource metadata
        let protectedResourceMetadata = try await discoverProtectedResourceMetadata(
            challenge: challenge,
            resourceServerURL: resourceServerURL,
            resourceType: resourceType
        )
        
        // Step 4: Discover authorization server metadata from protected resource metadata
        let authServerMetadata = try await oauthServerClient.discoverFromProtectedResourceMetadata(protectedResourceMetadata)
        
        logger.info("OAuth discovery process completed successfully")
        return authServerMetadata
    }
    
    /// Make an unauthenticated request to trigger 401 response with WWW-Authenticate header
    /// - Parameter resourceServerURL: URL of the resource server
    /// - Returns: Authentication challenge with 401 response
    /// - Throws: OAuthDiscoveryError if request fails
    private func makeUnauthenticatedRequest(to resourceServerURL: URL) async throws -> AuthenticationChallenge {
        logger.info(
            "Making unauthenticated request to trigger discovery",
            metadata: ["resourceServerURL": .string(resourceServerURL.absoluteString)]
        )
        
        // Create a simple request that should trigger authentication
        var request = URLRequest(url: resourceServerURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OAuthDiscoveryError.invalidResponse("Non-HTTP response received")
            }
            
            // We expect a 401 Unauthorized response
            if httpResponse.statusCode == 401 {
                let allHeaders = httpResponse.allHeaderFields
                var headers: [String: String] = [:]
                for (key, value) in allHeaders {
                    if let stringKey = key as? String, let stringValue = value as? String {
                        headers[stringKey] = stringValue
                    }
                }
                
                let challenge = AuthenticationChallenge(
                    statusCode: httpResponse.statusCode,
                    headers: headers,
                    body: data,
                    serverInfo: resourceServerURL.absoluteString
                )
                
                logger.info("Received 401 response with authentication challenge")
                return challenge
            } else if (200...299).contains(httpResponse.statusCode) {
                // Server doesn't require authentication - this is unexpected for MCP Auth flow
                throw OAuthDiscoveryError.noAuthenticationRequired("Resource server does not require authentication")
            } else {
                throw OAuthDiscoveryError.httpError(httpResponse.statusCode, "Unexpected response code: \(httpResponse.statusCode)")
            }
            
        } catch let error as OAuthDiscoveryError {
            throw error
        } catch {
            logger.error(
                "Failed to make unauthenticated request",
                metadata: ["error": .string(String(describing: error))]
            )
            throw OAuthDiscoveryError.networkError(error.localizedDescription)
        }
    }
    
    /// Discover protected resource metadata using multiple strategies
    /// - Parameters:
    ///   - challenge: Authentication challenge from 401 response
    ///   - resourceServerURL: URL of the resource server
    ///   - resourceType: Type of resource (e.g., "mcp")
    /// - Returns: Protected resource metadata
    /// - Throws: OAuthDiscoveryError if discovery fails
    private func discoverProtectedResourceMetadata(
        challenge: AuthenticationChallenge,
        resourceServerURL: URL,
        resourceType: String?
    ) async throws -> ProtectedResourceMetadata {
        
        logger.info("Discovering protected resource metadata")
        
        // Strategy 1: Extract from WWW-Authenticate header
        if let metadata = try await protectedResourceClient.discoverFromWWWAuthenticateHeader(challenge) {
            logger.info("Successfully discovered protected resource metadata from WWW-Authenticate header")
            return metadata
        }
        
        // Strategy 2: Fallback to well-known URI probing
        if let metadata = try await protectedResourceClient.discoverFromWellKnownURI(
            baseURL: resourceServerURL,
            resourceType: resourceType
        ) {
            logger.info("Successfully discovered protected resource metadata from well-known URI")
            return metadata
        }
        
        // If both strategies fail
        throw OAuthDiscoveryError.protectedResourceMetadataNotFound(
            "Could not discover protected resource metadata using WWW-Authenticate header or well-known URIs"
        )
    }
    
    /// Discover authorization server metadata with fallback to pre-configured values
    /// - Parameters:
    ///   - protectedResourceMetadata: Protected resource metadata
    ///   - fallbackAuthServerURL: Fallback authorization server URL
    /// - Returns: Authorization server metadata
    /// - Throws: OAuthDiscoveryError if discovery fails
    public func discoverWithFallback(
        protectedResourceMetadata: ProtectedResourceMetadata,
        fallbackAuthServerURL: URL? = nil
    ) async throws -> OAuthServerMetadata {
        
        logger.info("Discovering authorization server metadata with fallback options")
        
        do {
            return try await oauthServerClient.discoverFromProtectedResourceMetadata(protectedResourceMetadata)
        } catch {
            logger.warning(
                "Failed to discover from protected resource metadata",
                metadata: ["error": .string(String(describing: error))]
            )
            
            if let fallbackURL = fallbackAuthServerURL {
                logger.info(
                    "Attempting fallback to pre-configured authorization server URL",
                    metadata: ["authorizationServerURL": .string(fallbackURL.absoluteString)]
                )
                return try await oauthServerClient.discoverAuthorizationServerMetadata(issuerURL: fallbackURL)
            } else {
                throw OAuthDiscoveryError.authorizationServerDiscoveryFailed(
                    "Authorization server discovery failed and no fallback URL provided"
                )
            }
        }
    }
}

/// OAuth Discovery errors
public enum OAuthDiscoveryError: LocalizedError, Sendable {
    case networkError(String)
    case invalidResponse(String)
    case httpError(Int, String)
    case noAuthenticationRequired(String)
    case protectedResourceMetadataNotFound(String)
    case authorizationServerDiscoveryFailed(String)
    case invalidConfiguration(String)
    
    public var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error during OAuth discovery: \(message)"
        case .invalidResponse(let message):
            return "Invalid response during OAuth discovery: \(message)"
        case .httpError(let code, let message):
            return "HTTP error \(code) during OAuth discovery: \(message)"
        case .noAuthenticationRequired(let message):
            return "No authentication required: \(message)"
        case .protectedResourceMetadataNotFound(let message):
            return "Protected resource metadata not found: \(message)"
        case .authorizationServerDiscoveryFailed(let message):
            return "Authorization server discovery failed: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        }
    }
}
