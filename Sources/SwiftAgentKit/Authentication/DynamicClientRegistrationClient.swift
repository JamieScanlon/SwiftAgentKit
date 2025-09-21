//
//  DynamicClientRegistrationClient.swift
//  SwiftAgentKit
//
//  Created by SwiftAgentKit on 1/17/25.
//

import Foundation
import Logging

/// Client for performing OAuth 2.0 Dynamic Client Registration as per RFC 7591
public actor DynamicClientRegistrationClient {
    
    private let logger = Logger(label: "DynamicClientRegistrationClient")
    private let session: URLSession
    private let config: DynamicClientRegistrationConfig
    
    public init(config: DynamicClientRegistrationConfig) {
        self.config = config
        
        // Create URL session with custom configuration
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.requestTimeout ?? 30.0
        sessionConfig.timeoutIntervalForResource = (config.requestTimeout ?? 30.0) * 2
        
        self.session = URLSession(configuration: sessionConfig)
    }
    
    /// Registers a client with the authorization server
    /// - Parameters:
    ///   - request: Client registration request
    ///   - softwareStatement: Optional software statement for the client
    /// - Returns: Client registration response with client ID and secret
    /// - Throws: DynamicClientRegistrationError if registration fails
    public func registerClient(
        request: DynamicClientRegistration.ClientRegistrationRequest,
        softwareStatement: String? = nil
    ) async throws -> DynamicClientRegistration.ClientRegistrationResponse {
        
        logger.info("Starting client registration with endpoint: \(config.registrationEndpoint)")
        
        // Create registration request
        var registrationRequest = request
        
        // Add software statement if provided
        if let softwareStatement = softwareStatement {
            // In a real implementation, you would parse and validate the software statement
            // For now, we'll add it to additional metadata
            var additionalMetadata = registrationRequest.additionalMetadata ?? [:]
            additionalMetadata["software_statement"] = softwareStatement
            registrationRequest = DynamicClientRegistration.ClientRegistrationRequest(
                redirectUris: registrationRequest.redirectUris,
                applicationType: registrationRequest.applicationType,
                clientUri: registrationRequest.clientUri,
                contacts: registrationRequest.contacts,
                clientName: registrationRequest.clientName,
                logoUri: registrationRequest.logoUri,
                tosUri: registrationRequest.tosUri,
                policyUri: registrationRequest.policyUri,
                jwksUri: registrationRequest.jwksUri,
                jwks: registrationRequest.jwks,
                tokenEndpointAuthMethod: registrationRequest.tokenEndpointAuthMethod,
                grantTypes: registrationRequest.grantTypes,
                responseTypes: registrationRequest.responseTypes,
                scope: registrationRequest.scope,
                additionalMetadata: additionalMetadata
            )
        }
        
        // Create HTTP request
        var urlRequest = URLRequest(url: config.registrationEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add initial access token if provided
        if let initialAccessToken = config.initialAccessToken {
            urlRequest.setValue("Bearer \(initialAccessToken)", forHTTPHeaderField: "Authorization")
        }
        
        // Add additional headers
        if let additionalHeaders = config.additionalHeaders {
            for (key, value) in additionalHeaders {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Encode request body
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            urlRequest.httpBody = try encoder.encode(registrationRequest)
        } catch {
            logger.error("Failed to encode registration request: \(error)")
            throw DynamicClientRegistrationError.encodingError(error)
        }
        
        // Send request
        do {
            let (data, response) = try await session.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DynamicClientRegistrationError.invalidResponse("Invalid HTTP response")
            }
            
            logger.info("Received registration response with status: \(httpResponse.statusCode)")
            
            // Handle response based on status code
            switch httpResponse.statusCode {
            case 201: // Created - successful registration
                return try handleSuccessfulRegistration(data: data, httpResponse: httpResponse)
                
            case 400: // Bad Request - registration error
                return try handleRegistrationError(data: data, httpResponse: httpResponse)
                
            case 401: // Unauthorized - authentication required
                throw DynamicClientRegistrationError.authenticationRequired
                
            case 403: // Forbidden - access denied
                throw DynamicClientRegistrationError.accessDenied
                
            case 405: // Method Not Allowed - registration not supported
                throw DynamicClientRegistrationError.registrationNotSupported
                
            default:
                throw DynamicClientRegistrationError.serverError(httpResponse.statusCode, "Unexpected status code")
            }
            
        } catch let error as DynamicClientRegistrationError {
            throw error
        } catch {
            logger.error("Network error during client registration: \(error)")
            throw DynamicClientRegistrationError.networkError(error)
        }
    }
    
    /// Updates an existing client registration
    /// - Parameters:
    ///   - clientId: ID of the client to update
    ///   - request: Updated client registration request
    ///   - accessToken: Access token for client management
    /// - Returns: Updated client registration response
    /// - Throws: DynamicClientRegistrationError if update fails
    public func updateClientRegistration(
        clientId: String,
        request: DynamicClientRegistration.ClientRegistrationRequest,
        accessToken: String
    ) async throws -> DynamicClientRegistration.ClientRegistrationResponse {
        
        logger.info("Updating client registration for client ID: \(clientId)")
        
        // Create update URL (typically the same as registration endpoint with client ID)
        let updateURL = config.registrationEndpoint.appendingPathComponent(clientId)
        
        // Create HTTP request
        var urlRequest = URLRequest(url: updateURL)
        urlRequest.httpMethod = "PUT"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        // Add additional headers
        if let additionalHeaders = config.additionalHeaders {
            for (key, value) in additionalHeaders {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Encode request body
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            logger.error("Failed to encode update request: \(error)")
            throw DynamicClientRegistrationError.encodingError(error)
        }
        
        // Send request
        do {
            let (data, response) = try await session.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DynamicClientRegistrationError.invalidResponse("Invalid HTTP response")
            }
            
            logger.info("Received update response with status: \(httpResponse.statusCode)")
            
            // Handle response based on status code
            switch httpResponse.statusCode {
            case 200: // OK - successful update
                return try handleSuccessfulRegistration(data: data, httpResponse: httpResponse)
                
            case 400: // Bad Request - update error
                return try handleRegistrationError(data: data, httpResponse: httpResponse)
                
            case 401: // Unauthorized - authentication required
                throw DynamicClientRegistrationError.authenticationRequired
                
            case 403: // Forbidden - access denied
                throw DynamicClientRegistrationError.accessDenied
                
            case 404: // Not Found - client not found
                throw DynamicClientRegistrationError.clientNotFound
                
            default:
                throw DynamicClientRegistrationError.serverError(httpResponse.statusCode, "Unexpected status code")
            }
            
        } catch let error as DynamicClientRegistrationError {
            throw error
        } catch {
            logger.error("Network error during client update: \(error)")
            throw DynamicClientRegistrationError.networkError(error)
        }
    }
    
    /// Retrieves an existing client registration
    /// - Parameters:
    ///   - clientId: ID of the client to retrieve
    ///   - accessToken: Access token for client management
    /// - Returns: Client registration response
    /// - Throws: DynamicClientRegistrationError if retrieval fails
    public func getClientRegistration(
        clientId: String,
        accessToken: String
    ) async throws -> DynamicClientRegistration.ClientRegistrationResponse {
        
        logger.info("Retrieving client registration for client ID: \(clientId)")
        
        // Create retrieval URL (typically the same as registration endpoint with client ID)
        let retrievalURL = config.registrationEndpoint.appendingPathComponent(clientId)
        
        // Create HTTP request
        var urlRequest = URLRequest(url: retrievalURL)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        // Add additional headers
        if let additionalHeaders = config.additionalHeaders {
            for (key, value) in additionalHeaders {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Send request
        do {
            let (data, response) = try await session.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DynamicClientRegistrationError.invalidResponse("Invalid HTTP response")
            }
            
            logger.info("Received retrieval response with status: \(httpResponse.statusCode)")
            
            // Handle response based on status code
            switch httpResponse.statusCode {
            case 200: // OK - successful retrieval
                return try handleSuccessfulRegistration(data: data, httpResponse: httpResponse)
                
            case 401: // Unauthorized - authentication required
                throw DynamicClientRegistrationError.authenticationRequired
                
            case 403: // Forbidden - access denied
                throw DynamicClientRegistrationError.accessDenied
                
            case 404: // Not Found - client not found
                throw DynamicClientRegistrationError.clientNotFound
                
            default:
                throw DynamicClientRegistrationError.serverError(httpResponse.statusCode, "Unexpected status code")
            }
            
        } catch let error as DynamicClientRegistrationError {
            throw error
        } catch {
            logger.error("Network error during client retrieval: \(error)")
            throw DynamicClientRegistrationError.networkError(error)
        }
    }
    
    /// Deletes an existing client registration
    /// - Parameters:
    ///   - clientId: ID of the client to delete
    ///   - accessToken: Access token for client management
    /// - Throws: DynamicClientRegistrationError if deletion fails
    public func deleteClientRegistration(
        clientId: String,
        accessToken: String
    ) async throws {
        
        logger.info("Deleting client registration for client ID: \(clientId)")
        
        // Create deletion URL (typically the same as registration endpoint with client ID)
        let deletionURL = config.registrationEndpoint.appendingPathComponent(clientId)
        
        // Create HTTP request
        var urlRequest = URLRequest(url: deletionURL)
        urlRequest.httpMethod = "DELETE"
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        // Add additional headers
        if let additionalHeaders = config.additionalHeaders {
            for (key, value) in additionalHeaders {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Send request
        do {
            let (_, response) = try await session.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DynamicClientRegistrationError.invalidResponse("Invalid HTTP response")
            }
            
            logger.info("Received deletion response with status: \(httpResponse.statusCode)")
            
            // Handle response based on status code
            switch httpResponse.statusCode {
            case 204: // No Content - successful deletion
                return
                
            case 401: // Unauthorized - authentication required
                throw DynamicClientRegistrationError.authenticationRequired
                
            case 403: // Forbidden - access denied
                throw DynamicClientRegistrationError.accessDenied
                
            case 404: // Not Found - client not found
                throw DynamicClientRegistrationError.clientNotFound
                
            default:
                throw DynamicClientRegistrationError.serverError(httpResponse.statusCode, "Unexpected status code")
            }
            
        } catch let error as DynamicClientRegistrationError {
            throw error
        } catch {
            logger.error("Network error during client deletion: \(error)")
            throw DynamicClientRegistrationError.networkError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func handleSuccessfulRegistration(
        data: Data,
        httpResponse: HTTPURLResponse
    ) throws -> DynamicClientRegistration.ClientRegistrationResponse {
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(DynamicClientRegistration.ClientRegistrationResponse.self, from: data)
            
            logger.info("Successfully registered client with ID: \(response.clientId)")
            return response
            
        } catch {
            logger.error("Failed to decode registration response: \(error)")
            throw DynamicClientRegistrationError.decodingError(error)
        }
    }
    
    private func handleRegistrationError(
        data: Data,
        httpResponse: HTTPURLResponse
    ) throws -> DynamicClientRegistration.ClientRegistrationResponse {
        
        do {
            let decoder = JSONDecoder()
            let error = try decoder.decode(DynamicClientRegistration.ClientRegistrationError.self, from: data)
            
            logger.error("Registration failed with error: \(error.error) - \(error.errorDescription ?? "No description")")
            throw DynamicClientRegistrationError.registrationError(error)
            
        } catch let dynamicError as DynamicClientRegistrationError {
            throw dynamicError
        } catch {
            logger.error("Failed to decode registration error response: \(error)")
            throw DynamicClientRegistrationError.decodingError(error)
        }
    }
}

/// Errors that can occur during dynamic client registration
public enum DynamicClientRegistrationError: LocalizedError, Sendable {
    case networkError(Error)
    case encodingError(Error)
    case decodingError(Error)
    case invalidResponse(String)
    case registrationError(DynamicClientRegistration.ClientRegistrationError)
    case authenticationRequired
    case accessDenied
    case clientNotFound
    case registrationNotSupported
    case serverError(Int, String)
    
    public var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error during client registration: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode registration request: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode registration response: \(error.localizedDescription)"
        case .invalidResponse(let message):
            return "Invalid response from registration server: \(message)"
        case .registrationError(let error):
            return "Registration error: \(error.error) - \(error.errorDescription ?? "No description")"
        case .authenticationRequired:
            return "Authentication required for client registration"
        case .accessDenied:
            return "Access denied for client registration"
        case .clientNotFound:
            return "Client not found"
        case .registrationNotSupported:
            return "Dynamic client registration is not supported by this authorization server"
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        }
    }
}
