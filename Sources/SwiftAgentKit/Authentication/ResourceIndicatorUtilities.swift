//
//  ResourceIndicatorUtilities.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Foundation
import Logging

/// Utilities for implementing RFC 8707 Resource Indicators for OAuth 2.0
/// Used by MCP clients to specify target resources in OAuth requests
public struct ResourceIndicatorUtilities {
    private static let logger = SwiftAgentKitLogging.logger(
        for: .authentication("ResourceIndicatorUtilities")
    )
    
    /// Validates and normalizes a canonical URI according to RFC 8707 Section 2
    /// - Parameter uri: The URI to validate and normalize
    /// - Returns: The canonical form of the URI
    /// - Throws: ResourceIndicatorError if the URI is invalid
    public static func canonicalizeResourceURI(_ uri: String) throws -> String {
        guard let url = URL(string: uri) else {
            logger.warning(
                "Invalid resource URI format",
                metadata: ["uri": .string(uri)]
            )
            throw ResourceIndicatorError.invalidURI("Invalid URI format: \(uri)")
        }
        
        // Validate scheme is present (required)
        guard let scheme = url.scheme, !scheme.isEmpty else {
            logger.warning(
                "Resource URI missing scheme",
                metadata: ["uri": .string(uri)]
            )
            throw ResourceIndicatorError.invalidURI("Missing scheme: \(uri)")
        }
        
        // Validate scheme is supported (http/https for MCP servers)
        let supportedSchemes = ["http", "https"]
        guard supportedSchemes.contains(scheme.lowercased()) else {
            logger.warning(
                "Unsupported resource URI scheme",
                metadata: [
                    "uri": .string(uri),
                    "scheme": .string(scheme)
                ]
            )
            throw ResourceIndicatorError.invalidURI("Unsupported scheme '\(scheme)': \(uri). Only http and https are supported for MCP servers.")
        }
        
        // Validate host is present (required for http/https)
        guard let host = url.host, !host.isEmpty else {
            logger.warning(
                "Resource URI missing host",
                metadata: ["uri": .string(uri)]
            )
            throw ResourceIndicatorError.invalidURI("Missing host: \(uri)")
        }
        
        // Check for invalid components
        if url.fragment != nil {
            logger.warning(
                "Resource URI contains fragment",
                metadata: ["uri": .string(uri)]
            )
            throw ResourceIndicatorError.invalidURI("URI must not contain fragment: \(uri)")
        }
        
        // Build canonical URI
        var canonicalComponents = URLComponents()
        canonicalComponents.scheme = scheme.lowercased()
        canonicalComponents.host = host.lowercased()
        
        // Include port if present and not default
        if let port = url.port {
            let isDefaultPort = (scheme.lowercased() == "https" && port == 443) ||
                               (scheme.lowercased() == "http" && port == 80)
            if !isDefaultPort {
                canonicalComponents.port = port
            }
        }
        
        // Include path if present, but normalize trailing slash
        let path = url.path
        if !path.isEmpty && path != "/" {
            // Remove trailing slash unless it's semantically significant
            canonicalComponents.path = path.hasSuffix("/") && path != "/" ? String(path.dropLast()) : path
        }
        
        // Include query if present
        if let query = url.query, !query.isEmpty {
            canonicalComponents.query = query
        }
        
        guard let canonicalURI = canonicalComponents.url?.absoluteString else {
            logger.error(
                "Failed to construct canonical resource URI",
                metadata: ["uri": .string(uri)]
            )
            throw ResourceIndicatorError.invalidURI("Failed to construct canonical URI from: \(uri)")
        }
        
        logger.debug(
            "Canonicalized resource URI",
            metadata: [
                "originalURI": .string(uri),
                "canonicalURI": .string(canonicalURI)
            ]
        )
        
        return canonicalURI
    }
    
    /// Validates that a URI is suitable for use as a resource indicator
    /// - Parameter uri: The URI to validate
    /// - Returns: True if valid, false otherwise
    public static func isValidResourceURI(_ uri: String) -> Bool {
        do {
            _ = try canonicalizeResourceURI(uri)
            return true
        } catch {
            logger.debug(
                "Resource URI validation failed",
                metadata: [
                    "uri": .string(uri),
                    "error": .string(String(describing: error))
                ]
            )
            return false
        }
    }
    
    /// Creates a resource parameter value for OAuth requests (URL encoded)
    /// - Parameter canonicalURI: The canonical URI of the resource
    /// - Returns: URL-encoded resource parameter value
    public static func createResourceParameter(canonicalURI: String) -> String {
        // For OAuth request parameters, we need to percent-encode the entire URI
        // Using urlHostAllowed excludes characters that need encoding in query parameters
        let encoded = canonicalURI.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? canonicalURI
        logger.debug(
            "Created resource parameter",
            metadata: [
                "canonicalURI": .string(canonicalURI),
                "encodedLength": .stringConvertible(encoded.count)
            ]
        )
        return encoded
    }
    
    /// Extracts canonical MCP server URI from various input formats
    /// - Parameter serverURL: The server URL (may include paths, ports, etc.)
    /// - Returns: Canonical MCP server URI suitable for resource parameter
    /// - Throws: ResourceIndicatorError if the URL cannot be processed
    public static func extractMCPServerCanonicalURI(from serverURL: URL) throws -> String {
        var uriString = serverURL.absoluteString
        
        // Remove trailing slash if present (unless it's the root path)
        if uriString.hasSuffix("/") && uriString != serverURL.scheme! + "://" + serverURL.host! + "/" {
            uriString = String(uriString.dropLast())
        }
        
        let canonical = try canonicalizeResourceURI(uriString)
        logger.debug(
            "Extracted MCP server canonical URI",
            metadata: [
                "serverURL": .string(serverURL.absoluteString),
                "canonicalURI": .string(canonical)
            ]
        )
        return canonical
    }
}

/// Errors related to resource indicator processing
public enum ResourceIndicatorError: Error, LocalizedError {
    case invalidURI(String)
    case canonicalizationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURI(let message):
            return "Invalid resource URI: \(message)"
        case .canonicalizationFailed(let message):
            return "Failed to canonicalize URI: \(message)"
        }
    }
}
