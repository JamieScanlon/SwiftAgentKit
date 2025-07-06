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
actor MCPClient {
    
    enum Transport {
        case stdio
        case rest
    }
    
    enum State {
        case notConnected
        case connected
        case error
    }
    
    var name: String {
        bootCall.name
    }
    var version: String
    var state: State = .notConnected
    
    private(set) var tools: [Tool] = []
    private(set) var resources: [Resource] = []
    private(set) var prompts: [Prompt] = []
    private let logger = Logger(label: "MCPClient")
    
    init(bootCall: MCPConfig.ServerBootCall, version: String, isStrict: Bool = false) {
        self.bootCall = bootCall
        self.version = version
        let configuration = Client.Configuration(strict: isStrict)
        self.client = Client(name: bootCall.name, version: version, configuration: configuration)
    }
    
    func initializeMCPClient(config: MCPConfig) async throws {
        
        var environment = config.globalEnvironment.mcpEnvironment
        let bootCallEnvironment = bootCall.environment.mcpEnvironment
        environment.merge(bootCallEnvironment, uniquingKeysWith: { (_, new) in new })
        let (inPipe, outPipe) = Shell.shell(bootCall.command, arguments: bootCall.arguments, environment: environment)
        
        // Create a transport and connect
        let transport = ClientTransport(inPipe: inPipe, outPipe: outPipe)
        try await client.connect(transport: transport)
        
        // Get capabilities after connection
        self.capabilities = await client.capabilities
        state = .connected
    }
    
    func getTools() async throws {
        // List available tools
        let (tools, _) = try await client.listTools()
        self.tools = tools
    }
    
    func callTool(_ toolName: String, arguments: [String: Value]? = nil) async throws -> [Tool.Content]? {
        
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
        // List available tools
        let (resources, _) = try await client.listResources()
        self.resources = resources
    }
    
    func readResource(_ uri: String) async throws -> [Resource.Content] {
        let contents = try await client.readResource(uri: uri)
        return contents
    }
    
    func subscribeToResource(_ uri: String) async throws {
        // Subscribe to resource updates if supported
        // Note: Resource subscription capabilities may vary by MCP implementation
        try await client.subscribeToResource(uri: uri)
        
        // Register notification handler
        await client.onNotification(ResourceUpdatedNotification.self) { message in
            let uri = message.params.uri
            self.logger.info("Resource \(uri) updated with new content")
            
            // Fetch the updated resource content
            _ = try await self.client.readResource(uri: uri)
            self.logger.info("Updated resource content received")
        }
    }
    
    func getPrompts() async throws {
        // List available tools
        let (prompts, _) = try await client.listPrompts()
        self.prompts = prompts
    }
    
    func getPrompt(_ name: String, arguments: [String: Value]? = nil) async throws -> [Prompt.Message] {
        let (_, messages) = try await client.getPrompt(name: name, arguments: arguments)
        return messages
    }
    
    // MARK: - Private
    
    private let client: Client
    private var bootCall: MCPConfig.ServerBootCall
    private var capabilities: Client.Capabilities?
}

import Logging

actor ClientTransport: Transport {
    
    nonisolated let logger: Logging.Logger
    
    
    init(inPipe: Pipe, outPipe: Pipe, logger: Logging.Logger? = nil) {
        
        self.inPipe = inPipe
        self.outPipe = outPipe
        self.logger = logger ?? Logging.Logger(label: "mcp.transport.stdio")
        
        // Create message stream
        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        self.messageStream = AsyncThrowingStream { continuation = $0 }
        self.messageContinuation = continuation
        
    }
    
    /// Establishes connection with the transport
    func connect() async throws {
        guard !isConnected else { return }
        
        isConnected = true
        
        // Start reading loop in background
        Task.detached {
            await self.readLoop()
        }
    }
    
    /// Disconnects from the transport
    func disconnect() async {
        guard isConnected else { return }
        isConnected = false
        messageContinuation.finish()
        outPipe.fileHandleForReading.readabilityHandler = nil
        logger.info("Transport disconnected")
    }
    
    /// Sends data
    func send(_ data: Data) async throws {
        
        guard isConnected else {
            throw MCPError.transportError(Errno(rawValue: ENOTCONN))
        }
        
        // Add newline as delimiter
        var messageWithNewline = data
        messageWithNewline.append(UInt8(ascii: "\n"))
        try inPipe.fileHandleForWriting.write(contentsOf: messageWithNewline)
    }
    
    /// Receives data in an async sequence
    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        return messageStream
    }
    
    // MARK: - Private
    
    private var inPipe: Pipe
    private var outPipe: Pipe
    private var isConnected = false
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation
    
    /// Continuous loop that reads and processes incoming messages
    ///
    /// This method runs in the background while the transport is connected,
    /// parsing complete messages delimited by newlines and yielding them
    /// to the message stream.
    private func readLoop() async {
        
        outPipe.fileHandleForReading.readabilityHandler = { pipeHandle in
            let data = pipeHandle.availableData
            self.logger.debug("Received data: \(String(data: data, encoding: .utf8) ?? "")")
            self.messageContinuation.yield(data)
        }
    }
}

// MARK: - Extensions

extension JSON {
    
    var mcpEnvironment: [String: String] {
        var result = [String: String]()
        
        guard case .object(let object) = self else {
            return [:]
        }
        
        for (key, value) in object {
            let stringValue: String? = {
                if case .string(let string) = value {
                    return string
                } else if case .integer(let interger) = value {
                    return String(interger)
                } else if case .double(let double) = value {
                    return String(double)
                } else if case .boolean(let boolean) = value {
                    return boolean ? "true" : "false"
                } else {
                    return nil
                }
            }()
            if let stringValue {
                result[key] = stringValue
            }
        }
        return result
    }
}

