//
//  MCPClient.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 5/17/25.
//

import EasyJSON
import Foundation
import Logging
import MCP
import System
import SwiftAgentKit

/// MCP clients maintain 1:1 connections with servers, inside the MCP host application
public actor MCPClient {
    
    public enum State: Sendable {
        case notConnected
        case connected
        case error
    }
    
    public enum MCPClientError: LocalizedError {
        case notConnected
        
        public var errorDescription: String? {
            switch self {
            case .notConnected:
                return "MCP client is not connected"
            }
        }
    }
    
    public let name: String
    public let version: String
    public let isStrict: Bool
    public var state: State = .notConnected
    
    public private(set) var tools: [Tool] = []
    public private(set) var resources: [Resource] = []
    public private(set) var prompts: [Prompt] = []
    private let logger = Logger(label: "MCPClient")
    
    public init(name: String, version: String, isStrict: Bool = false) {
        self.name = name
        self.version = version
        self.isStrict = isStrict
        // Client will be created when connecting to transport
    }
    
    /// Connect to an MCP server using the provided transport
    /// - Parameter transport: The transport to use for communication
    public func connect(transport: Transport) async throws {
        let configuration = Client.Configuration(strict: isStrict)
        let newClient = Client(name: name, version: version, configuration: configuration)
        
        // Connect the client to the transport
        try await newClient.connect(transport: transport)
        
        // Store the connected client
        self.client = newClient
        
        // Get capabilities after connection
        self.capabilities = await newClient.capabilities
        state = .connected
        logger.info("MCP client '\(name)' connected successfully")
    }
    
    /// Connect to an MCP server using stdio pipes
    /// - Parameters:
    ///   - inPipe: Input pipe for receiving data from the server
    ///   - outPipe: Output pipe for sending data to the server
    public func connect(inPipe: Pipe, outPipe: Pipe) async throws {
        let transport = ClientTransport(inPipe: inPipe, outPipe: outPipe)
        try await connect(transport: transport)
    }
    

    
    func getTools() async throws {
        guard let client = client else {
            throw MCPClientError.notConnected
        }
        // List available tools
        let (tools, _) = try await client.listTools()
        self.tools = tools
    }
    
    public func callTool(_ toolName: String, arguments: [String: Value]? = nil) async throws -> [Tool.Content]? {
        
        guard let client = client else {
            throw MCPClientError.notConnected
        }
        
        guard tools.map(\.name).firstIndex(of: toolName) != nil else {
            return nil
        }
        
        let (content, _) = try await client.callTool(name: toolName, arguments: arguments)
        // Handle tool content
        for item in content {
            switch item {
            case .text(let text):
                logger.info("Generated text: \(text)")
            case .image(_, let mimeType, let metadata):
                if let width = metadata?["width"] as? Int,
                   let height = metadata?["height"] as? Int {
                    logger.info("Generated \(width)x\(height) image of type \(mimeType)")
                    // Save or display the image data
                }
            case .audio(_, let mimeType):
                logger.info("Received audio data of type \(mimeType)")
            case .resource(let uri, let mimeType, let text):
                logger.info("Received resource from \(uri) of type \(mimeType)")
                if let text = text {
                    logger.info("Resource text: \(text)")
                }
            }
        }
        return content
    }
    
    func getResources() async throws {
        guard let client = client else {
            throw MCPClientError.notConnected
        }
        // List available tools
        let (resources, _) = try await client.listResources()
        self.resources = resources
    }
    
    func readResource(_ uri: String) async throws -> [Resource.Content] {
        guard let client = client else {
            throw MCPClientError.notConnected
        }
        let contents = try await client.readResource(uri: uri)
        return contents
    }
    
    func subscribeToResource(_ uri: String) async throws {
        guard let client = client else {
            throw MCPClientError.notConnected
        }
        // Subscribe to resource updates if supported
        // Note: Resource subscription capabilities may vary by MCP implementation
        try await client.subscribeToResource(uri: uri)
        
        // Register notification handler
        await client.onNotification(ResourceUpdatedNotification.self) { message in
            let uri = message.params.uri
            self.logger.info("Resource \(uri) updated with new content")
            
            // Fetch the updated resource content
            _ = try await self.client?.readResource(uri: uri)
            self.logger.info("Updated resource content received")
        }
    }
    
    func getPrompts() async throws {
        guard let client = client else {
            throw MCPClientError.notConnected
        }
        // List available tools
        let (prompts, _) = try await client.listPrompts()
        self.prompts = prompts
    }
    
    func getPrompt(_ name: String, arguments: [String: Value]? = nil) async throws -> [Prompt.Message] {
        guard let client = client else {
            throw MCPClientError.notConnected
        }
        let (_, messages) = try await client.getPrompt(name: name, arguments: arguments)
        return messages
    }
    
    // MARK: - Private
    
    private var client: Client?
    private var capabilities: Client.Capabilities?
}



