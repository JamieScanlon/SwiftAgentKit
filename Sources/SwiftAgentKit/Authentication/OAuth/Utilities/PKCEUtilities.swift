//
//  PKCEUtilities.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Foundation
import CryptoKit
import Logging

/// Utilities for implementing PKCE (Proof Key for Code Exchange) as per RFC 7636 and OAuth 2.1 Section 7.5.2
public struct PKCEUtilities {
    private static let logger = SwiftAgentKitLogging.logger(
        for: .authentication("PKCEUtilities")
    )
    
    /// PKCE code verifier and challenge pair
    public struct PKCEPair: Sendable {
        public let codeVerifier: String
        public let codeChallenge: String
        public let codeChallengeMethod: String = "S256" // Always use S256 as per OAuth 2.1 Section 4.1.1
        
        public init(codeVerifier: String, codeChallenge: String) {
            self.codeVerifier = codeVerifier
            self.codeChallenge = codeChallenge
        }
    }
    
    /// Generate a PKCE code verifier and challenge pair
    /// - Returns: PKCE pair with code verifier and S256 challenge
    /// - Throws: PKCEError if generation fails
    public static func generatePKCEPair() throws -> PKCEPair {
        logger.debug("Generating PKCE pair")
        do {
            // Generate a cryptographically random code verifier
            // Length should be between 43 and 128 characters (RFC 7636 Section 4.1)
            let codeVerifier = try generateCodeVerifier()
            
            // Generate code challenge using S256 method
            let codeChallenge = try generateCodeChallenge(from: codeVerifier)
            
            logger.debug(
                "Generated PKCE pair",
                metadata: [
                    "codeVerifierLength": .stringConvertible(codeVerifier.count),
                    "challengeLength": .stringConvertible(codeChallenge.count)
                ]
            )
            return PKCEPair(codeVerifier: codeVerifier, codeChallenge: codeChallenge)
        } catch {
            logger.error(
                "Failed to generate PKCE pair",
                metadata: ["error": .string(String(describing: error))]
            )
            throw error
        }
    }
    
    /// Generate a code verifier string
    /// - Returns: URL-safe base64-encoded random string
    /// - Throws: PKCEError if generation fails
    private static func generateCodeVerifier() throws -> String {
        // Generate 32 random bytes (256 bits) which gives us ~43 characters when base64url encoded
        let randomBytes = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        
        // Encode using base64url encoding (RFC 4648 Section 5)
        let base64String = randomBytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        guard base64String.count >= 43 && base64String.count <= 128 else {
            logger.warning(
                "Generated code verifier has invalid length",
                metadata: ["length": .stringConvertible(base64String.count)]
            )
            throw PKCEError.invalidCodeVerifierLength(base64String.count)
        }
        
        return base64String
    }
    
    /// Generate a code challenge from a code verifier using S256 method
    /// - Parameter codeVerifier: The code verifier string
    /// - Returns: Base64url-encoded SHA256 hash of the code verifier
    /// - Throws: PKCEError if generation fails
    private static func generateCodeChallenge(from codeVerifier: String) throws -> String {
        guard let data = codeVerifier.data(using: .utf8) else {
            logger.warning(
                "Unable to convert code verifier to UTF-8 data",
                metadata: ["verifierLength": .stringConvertible(codeVerifier.count)]
            )
            throw PKCEError.invalidCodeVerifier("Unable to convert code verifier to UTF-8 data")
        }
        
        // Compute SHA256 hash
        let hashed = SHA256.hash(data: data)
        
        // Encode using base64url encoding
        let base64String = Data(hashed).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        return base64String
    }
    
    /// Validate that a code verifier matches a code challenge
    /// - Parameters:
    ///   - codeVerifier: The code verifier to validate
    ///   - codeChallenge: The expected code challenge
    /// - Returns: True if the code verifier matches the challenge
    public static func validateCodeVerifier(_ codeVerifier: String, against codeChallenge: String) -> Bool {
        do {
            let expectedChallenge = try generateCodeChallenge(from: codeVerifier)
            let matches = expectedChallenge == codeChallenge
            if !matches {
                logger.debug(
                    "Provided code verifier does not match expected challenge",
                    metadata: [
                        "verifierLength": .stringConvertible(codeVerifier.count),
                        "expectedLength": .stringConvertible(expectedChallenge.count),
                        "providedLength": .stringConvertible(codeChallenge.count)
                    ]
                )
            }
            return matches
        } catch {
            logger.debug(
                "Failed to validate code verifier",
                metadata: ["error": .string(String(describing: error))]
            )
            return false
        }
    }
}

/// PKCE-specific errors
public enum PKCEError: LocalizedError, Sendable {
    case invalidCodeVerifierLength(Int)
    case invalidCodeVerifier(String)
    case generationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidCodeVerifierLength(let length):
            return "Invalid code verifier length: \(length). Must be between 43 and 128 characters."
        case .invalidCodeVerifier(let message):
            return "Invalid code verifier: \(message)"
        case .generationFailed(let message):
            return "PKCE generation failed: \(message)"
        }
    }
}
