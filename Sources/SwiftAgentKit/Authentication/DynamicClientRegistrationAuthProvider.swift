//
//  DynamicClientRegistrationAuthProvider.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Foundation
import Logging

/// Authentication provider that uses OAuth 2.0 Dynamic Client Registration
/// This provider automatically registers with authorization servers and manages client credentials
public actor DynamicClientRegistrationAuthProvider: AuthenticationProvider {
    
    private let logger = Logger(label: "DynamicClientRegistrationAuthProvider")
    
    /// The authentication scheme this provider handles
    public let scheme: AuthenticationScheme = .oauth
    
    /// Configuration for dynamic client registration
    private let registrationConfig: DynamicClientRegistrationConfig
    
    /// Client registration request metadata
    private let registrationRequest: DynamicClientRegistration.ClientRegistrationRequest
    
    /// Registered client credentials (populated after successful registration)
    private var registeredClient: DynamicClientRegistration.ClientRegistrationResponse?
    
    /// Underlying OAuth provider (created after registration)
    private var oauthProvider: (any AuthenticationProvider)?
    
    /// Software statement for registration (if applicable)
    private let softwareStatement: String?
    
    /// Storage for client credentials (persistent across app restarts)
    private let credentialStorage: DynamicClientCredentialStorage?
    
    /// Initializes the provider with registration configuration
    /// - Parameters:
    ///   - registrationConfig: Configuration for client registration
    ///   - registrationRequest: Client registration request metadata
    ///   - softwareStatement: Optional software statement for registration
    ///   - credentialStorage: Optional storage for persisting client credentials
    public init(
        registrationConfig: DynamicClientRegistrationConfig,
        registrationRequest: DynamicClientRegistration.ClientRegistrationRequest,
        softwareStatement: String? = nil,
        credentialStorage: DynamicClientCredentialStorage? = nil
    ) {
        self.registrationConfig = registrationConfig
        self.registrationRequest = registrationRequest
        self.softwareStatement = softwareStatement
        self.credentialStorage = credentialStorage
    }
    
    /// Provides authentication headers for HTTP requests
    /// - Returns: Dictionary of headers to include in requests
    public func authenticationHeaders() async throws -> [String: String] {
        // Ensure we have a registered client and OAuth provider
        try await ensureRegisteredClient()
        
        guard let oauthProvider = oauthProvider else {
            throw AuthenticationError.authenticationFailed("OAuth provider not available")
        }
        
        return try await oauthProvider.authenticationHeaders()
    }
    
    /// Handles authentication challenges/refreshes if needed
    /// - Parameter challenge: Authentication challenge information
    /// - Returns: Updated headers or throws if auth failed
    public func handleAuthenticationChallenge(_ challenge: AuthenticationChallenge) async throws -> [String: String] {
        // Ensure we have a registered client and OAuth provider
        try await ensureRegisteredClient()
        
        guard let oauthProvider = oauthProvider else {
            throw AuthenticationError.authenticationFailed("OAuth provider not available")
        }
        
        return try await oauthProvider.handleAuthenticationChallenge(challenge)
    }
    
    /// Validates if current authentication is still valid
    /// - Returns: True if authentication is valid, false if refresh needed
    public func isAuthenticationValid() async -> Bool {
        guard let oauthProvider = oauthProvider else {
            return false
        }
        
        return await oauthProvider.isAuthenticationValid()
    }
    
    /// Cleans up any authentication resources (tokens, sessions, etc.)
    public func cleanup() async {
        await oauthProvider?.cleanup()
    }
    
    // MARK: - Public Methods
    
    /// Gets the registered client ID
    /// - Returns: Client ID if registered, nil otherwise
    public func getClientId() async -> String? {
        return registeredClient?.clientId
    }
    
    /// Gets the registered client secret
    /// - Returns: Client secret if registered and available, nil otherwise
    public func getClientSecret() async -> String? {
        return registeredClient?.clientSecret
    }
    
    /// Forces re-registration of the client
    /// This can be useful if the client credentials have been revoked or expired
    public func reRegisterClient() async throws {
        logger.info("Forcing client re-registration")
        
        // Clear existing registration
        registeredClient = nil
        oauthProvider = nil
        
        // Clear stored credentials
        if let credentialStorage = credentialStorage,
           let clientId = registeredClient?.clientId {
            await credentialStorage.clearCredentials(clientId: clientId)
        }
        
        // Register again
        try await ensureRegisteredClient()
    }
    
    // MARK: - Private Methods
    
    /// Ensures that we have a registered client and corresponding OAuth provider
    private func ensureRegisteredClient() async throws {
        // If we already have a registered client, check if it's still valid
        if let registeredClient = registeredClient,
           let oauthProvider = oauthProvider {
            
            // Check if the OAuth provider is still valid
            if await oauthProvider.isAuthenticationValid() {
                return // Everything is good
            } else {
                logger.info("OAuth provider is no longer valid, attempting to refresh or re-register")
                // Try to refresh the OAuth provider
                do {
                    let challenge = AuthenticationChallenge(
                        statusCode: 401,
                        headers: [:],
                        body: nil,
                        serverInfo: nil
                    )
                    _ = try await oauthProvider.handleAuthenticationChallenge(challenge)
                    return // Refresh was successful
                } catch {
                    logger.info("OAuth refresh failed, will re-register client")
                    // If refresh fails, we'll re-register below
                }
            }
        }
        
        // Try to load existing credentials from storage
        if let credentialStorage = credentialStorage {
            if let storedCredentials = await credentialStorage.loadCredentials() {
                logger.info("Found stored client credentials, attempting to use them")
                
                // Create OAuth provider with stored credentials
                if let oauthProvider = try await createOAuthProvider(from: storedCredentials) {
                    self.registeredClient = storedCredentials
                    self.oauthProvider = oauthProvider
                    
                    // Verify the credentials are still valid
                    if await oauthProvider.isAuthenticationValid() {
                        logger.info("Stored credentials are valid, using existing registration")
                        return
                    } else {
                        logger.info("Stored credentials are invalid, will re-register")
                    }
                }
            }
        }
        
        // Need to register a new client
        logger.info("Registering new client with authorization server")
        
        let registrationClient = DynamicClientRegistrationClient(config: registrationConfig)
        
        do {
            let response = try await registrationClient.registerClient(
                request: registrationRequest,
                softwareStatement: softwareStatement
            )
            
            logger.info("Successfully registered client with ID: \(response.clientId)")
            
            // Store the registered client
            registeredClient = response
            
            // Create OAuth provider with the registered credentials
            oauthProvider = try await createOAuthProvider(from: response)
            
            // Store credentials for future use
            if let credentialStorage = credentialStorage {
                await credentialStorage.storeCredentials(response)
            }
            
        } catch {
            logger.error("Failed to register client: \(error)")
            throw AuthenticationError.authenticationFailed("Client registration failed: \(error.localizedDescription)")
        }
    }
    
    /// Creates an OAuth provider from registered client credentials
    private func createOAuthProvider(from response: DynamicClientRegistration.ClientRegistrationResponse) async throws -> (any AuthenticationProvider)? {
        
        // We need to determine the OAuth configuration based on the registration response
        // This is a simplified implementation - in practice, you might need more sophisticated logic
        
        // For now, we'll create a basic OAuth provider
        // In a real implementation, you would:
        // 1. Discover the authorization server endpoints
        // 2. Create the appropriate OAuth provider (PKCE, OAuth Discovery, etc.)
        // 3. Handle different grant types and response types
        
        logger.info("Creating OAuth provider for registered client: \(response.clientId)")
        
        // This is a placeholder - you would implement the actual OAuth provider creation logic here
        // based on your specific OAuth flow requirements
        
        throw AuthenticationError.authenticationFailed("OAuth provider creation not yet implemented")
    }
}

/// Storage interface for persisting dynamic client registration credentials
public protocol DynamicClientCredentialStorage: Sendable {
    /// Stores client credentials
    /// - Parameter credentials: Client registration response to store
    func storeCredentials(_ credentials: DynamicClientRegistration.ClientRegistrationResponse) async
    
    /// Loads stored client credentials (most recent)
    /// - Returns: Stored credentials if available, nil otherwise
    func loadCredentials() async -> DynamicClientRegistration.ClientRegistrationResponse?
    
    /// Loads stored client credentials for a specific client
    /// - Parameter clientId: Client ID to load credentials for
    /// - Returns: Stored credentials for the client if available, nil otherwise
    func loadCredentials(for clientId: String) async -> DynamicClientRegistration.ClientRegistrationResponse?
    
    /// Clears stored credentials for a specific client
    /// - Parameter clientId: Client ID to clear credentials for
    func clearCredentials(clientId: String) async
    
    /// Clears all stored credentials
    func clearAllCredentials() async
}

/// Default implementation of credential storage using UserDefaults
public actor DefaultDynamicClientCredentialStorage: DynamicClientCredentialStorage {
    
    private let logger = Logger(label: "DefaultDynamicClientCredentialStorage")
    private let userDefaults: UserDefaults
    private let keyPrefix = "DynamicClientRegistration_"
    
    public init(userDefaults: UserDefaults = UserDefaults.standard) {
        self.userDefaults = userDefaults
    }
    
    public func storeCredentials(_ credentials: DynamicClientRegistration.ClientRegistrationResponse) async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(credentials)
            
            // Include timestamp in key to support finding most recent
            let timestamp = Int(Date().timeIntervalSince1970)
            let key = "\(keyPrefix)\(timestamp)_\(credentials.clientId)"
            userDefaults.set(data, forKey: key)
            
            logger.info("Stored credentials for client: \(credentials.clientId)")
            
        } catch {
            logger.error("Failed to store credentials: \(error)")
        }
    }
    
    public func loadCredentials() async -> DynamicClientRegistration.ClientRegistrationResponse? {
        // For simplicity, we'll try to load from the most recently stored client
        // In a real implementation, you might want to support multiple clients
        
        let keys = userDefaults.dictionaryRepresentation().keys
        let credentialKeys = keys.filter { $0.hasPrefix(keyPrefix) }
        
        // Find the most recent key by timestamp
        var mostRecentKey: String?
        var mostRecentTime: Date = Date.distantPast
        
        for key in credentialKeys {
            // Extract timestamp from key (format: DynamicClientRegistration_<timestamp>_<clientId>)
            let components = key.dropFirst(keyPrefix.count).components(separatedBy: "_")
            if components.count >= 2,
               let timestamp = TimeInterval(components[0]) {
                let keyTime = Date(timeIntervalSince1970: timestamp)
                if keyTime > mostRecentTime {
                    mostRecentTime = keyTime
                    mostRecentKey = key
                }
            }
        }
        
        guard let latestKey = mostRecentKey,
              let data = userDefaults.data(forKey: latestKey) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let credentials = try decoder.decode(DynamicClientRegistration.ClientRegistrationResponse.self, from: data)
            
            logger.info("Loaded credentials for client: \(credentials.clientId)")
            return credentials
            
        } catch {
            logger.error("Failed to load credentials: \(error)")
            return nil
        }
    }
    
    public func loadCredentials(for clientId: String) async -> DynamicClientRegistration.ClientRegistrationResponse? {
        let keys = userDefaults.dictionaryRepresentation().keys
        let credentialKeys = keys.filter { $0.hasPrefix(keyPrefix) && $0.contains("_\(clientId)") }
        
        // Find the most recent key by timestamp for this specific client
        var mostRecentKey: String?
        var mostRecentTime: Date = Date.distantPast
        
        for key in credentialKeys {
            // Extract timestamp from key (format: DynamicClientRegistration_<timestamp>_<clientId>)
            let components = key.dropFirst(keyPrefix.count).components(separatedBy: "_")
            if components.count >= 2,
               let timestamp = TimeInterval(components[0]) {
                let keyTime = Date(timeIntervalSince1970: timestamp)
                if keyTime > mostRecentTime {
                    mostRecentTime = keyTime
                    mostRecentKey = key
                }
            }
        }
        
        guard let latestKey = mostRecentKey,
              let data = userDefaults.data(forKey: latestKey) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let credentials = try decoder.decode(DynamicClientRegistration.ClientRegistrationResponse.self, from: data)
            
            logger.info("Loaded credentials for client: \(credentials.clientId)")
            return credentials
            
        } catch {
            logger.error("Failed to load credentials: \(error)")
            return nil
        }
    }
    
    public func clearCredentials(clientId: String) async {
        // Find all keys for this client ID and remove them
        let keys = userDefaults.dictionaryRepresentation().keys
        let credentialKeys = keys.filter { $0.hasPrefix(keyPrefix) }
        
        for key in credentialKeys {
            if key.contains("_\(clientId)") {
                userDefaults.removeObject(forKey: key)
            }
        }
        
        logger.info("Cleared credentials for client: \(clientId)")
    }
    
    public func clearAllCredentials() async {
        let keys = userDefaults.dictionaryRepresentation().keys
        let credentialKeys = keys.filter { $0.hasPrefix(keyPrefix) }
        
        for key in credentialKeys {
            userDefaults.removeObject(forKey: key)
        }
        
        logger.info("Cleared all stored credentials (\(credentialKeys.count) clients)")
    }
}
