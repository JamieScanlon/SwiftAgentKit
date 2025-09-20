//
//  PKCEUtilitiesTests.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Testing
import Foundation
import CryptoKit
import SwiftAgentKit

@Suite("PKCEUtilities Tests")
struct PKCEUtilitiesTests {
    
    @Test("Generate PKCE pair")
    func testGeneratePKCEPair() throws {
        let pkcePair = try PKCEUtilities.generatePKCEPair()
        
        #expect(!pkcePair.codeVerifier.isEmpty)
        #expect(!pkcePair.codeChallenge.isEmpty)
        #expect(pkcePair.codeChallengeMethod == "S256")
        
        // Code verifier should be between 43 and 128 characters
        #expect(pkcePair.codeVerifier.count >= 43)
        #expect(pkcePair.codeVerifier.count <= 128)
        
        // Code challenge should be exactly 43 characters (base64url encoded SHA256)
        #expect(pkcePair.codeChallenge.count == 43)
    }
    
    @Test("Code verifier length validation")
    func testCodeVerifierLengthValidation() throws {
        let pkcePair = try PKCEUtilities.generatePKCEPair()
        
        // Test valid length
        #expect(pkcePair.codeVerifier.count >= 43)
        #expect(pkcePair.codeVerifier.count <= 128)
    }
    
    @Test("Code challenge format validation")
    func testCodeChallengeFormatValidation() throws {
        let pkcePair = try PKCEUtilities.generatePKCEPair()
        
        // Code challenge should be base64url encoded (no padding, no + or /)
        #expect(!pkcePair.codeChallenge.contains("+"))
        #expect(!pkcePair.codeChallenge.contains("/"))
        #expect(!pkcePair.codeChallenge.contains("="))
        
        // Should be exactly 43 characters for S256 method
        #expect(pkcePair.codeChallenge.count == 43)
    }
    
    @Test("Validate code verifier against challenge")
    func testValidateCodeVerifierAgainstChallenge() throws {
        let pkcePair = try PKCEUtilities.generatePKCEPair()
        
        // Valid code verifier should match its challenge
        let isValid = PKCEUtilities.validateCodeVerifier(pkcePair.codeVerifier, against: pkcePair.codeChallenge)
        #expect(isValid == true)
        
        // Invalid code verifier should not match
        let invalidVerifier = "invalid_verifier"
        let isInvalid = PKCEUtilities.validateCodeVerifier(invalidVerifier, against: pkcePair.codeChallenge)
        #expect(isInvalid == false)
    }
    
    @Test("Multiple PKCE pairs are unique")
    func testMultiplePKCEPairsAreUnique() throws {
        let pair1 = try PKCEUtilities.generatePKCEPair()
        let pair2 = try PKCEUtilities.generatePKCEPair()
        let pair3 = try PKCEUtilities.generatePKCEPair()
        
        // All pairs should be different
        #expect(pair1.codeVerifier != pair2.codeVerifier)
        #expect(pair1.codeVerifier != pair3.codeVerifier)
        #expect(pair2.codeVerifier != pair3.codeVerifier)
        
        #expect(pair1.codeChallenge != pair2.codeChallenge)
        #expect(pair1.codeChallenge != pair3.codeChallenge)
        #expect(pair2.codeChallenge != pair3.codeChallenge)
    }
    
    @Test("PKCE pair consistency")
    func testPKCEPairConsistency() throws {
        let pkcePair = try PKCEUtilities.generatePKCEPair()
        
        // The same code verifier should always generate the same challenge
        let isValid = PKCEUtilities.validateCodeVerifier(pkcePair.codeVerifier, against: pkcePair.codeChallenge)
        #expect(isValid == true)
    }
    
    @Test("Base64url encoding validation")
    func testBase64urlEncodingValidation() throws {
        let pkcePair = try PKCEUtilities.generatePKCEPair()
        
        // Code verifier and challenge should only contain base64url characters
        let base64urlChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        
        let verifierChars = CharacterSet(charactersIn: pkcePair.codeVerifier)
        let challengeChars = CharacterSet(charactersIn: pkcePair.codeChallenge)
        
        #expect(verifierChars.isSubset(of: base64urlChars))
        #expect(challengeChars.isSubset(of: base64urlChars))
    }
}

