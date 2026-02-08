//
//  A2AManager.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 6/19/25.
//

import Foundation
import Logging
import SwiftAgentKit
import EasyJSON

public actor A2AManager {
    private let logger: Logger
    
    public init(logger: Logger? = nil) {
        self.logger = logger ?? SwiftAgentKitLogging.logger(
            for: .a2a("A2AManager")
        )
    }
    
    public enum State {
        case notReady
        case initialized
    }
    
    public var state: State = .notReady
    public var toolCallsJsonString: String?
    public var toolCallsJson: [[String: Any]] = []
    
    /// Initialize the A2AManager with a config file URL
    public func initialize(configFileURL: URL) async throws {
        do {
            try await loadA2AConfiguration(configFileURL: configFileURL)
        } catch {
            logger.error(
                "Failed to initialize A2A manager",
                metadata: SwiftAgentKitLogging.metadata(
                    ("configURL", .string(configFileURL.absoluteString)),
                    ("error", .string(String(describing: error)))
                )
            )
            throw error
        }
    }
    
    /// Initialize the A2AManager with an arrat of `A2AClient` objects
    public func initialize(clients: [A2AClient]) async throws {
        self.clients = clients
        await buildToolsJson()
    }
    
    public func agentCall(_ toolCall: ToolCall) async throws -> [LLMResponse]? {
        // Find the client whose agent card name matches the tool call name
        var matchingClient: A2AClient?
        for client in clients {
            guard let agentCard = await client.agentCard else { continue }
            if agentCard.name == toolCall.name {
                matchingClient = client
                break
            }
        }
        
        guard let client = matchingClient else {
            return nil
        }
        
        // Extract instructions from JSON arguments
        guard case .object(let argsDict) = toolCall.arguments,
              case .string(let instructions) = argsDict["instructions"] else { return nil }
        
        // A2A messages take the role of 'user' for the purpose of communicating with other agents.
        let a2aMessage = A2AMessage(role: "user", parts: [.text(text: instructions)], messageId: UUID().uuidString)
        let params: MessageSendParams = .init(message: a2aMessage, metadata: try? .init(["toolCallId": toolCall.id]))
        let contents = try await client.streamMessage(params: params)
        var returnResponses: [LLMResponse] = []
        var responseText: String = ""
        var accumulatedImages: [Message.Image] = []
        
        for await content in contents {
            switch content.result {
            case .message(let aMessage):
                let (text, images) = extractTextAndImages(from: aMessage.parts)
                accumulatedImages.append(contentsOf: images)
                let metadata = createMetadataWithImages(images)
                returnResponses.append(LLMResponse.complete(content: text, metadata: metadata))
            case .task(let task):
                var text: String = ""
                var taskImages: [Message.Image] = []
                if let artifacts = task.artifacts {
                    for artifact in artifacts {
                        let (artifactText, artifactImages) = extractTextAndImages(from: artifact.parts, artifactName: artifact.name)
                        text += artifactText
                        taskImages.append(contentsOf: artifactImages)
                    }
                }
                accumulatedImages.append(contentsOf: taskImages)
                let metadata = createMetadataWithImages(taskImages)
                returnResponses.append(LLMResponse.complete(content: text, metadata: metadata))
            case .taskArtifactUpdate(let event):
                let (artifactText, artifactImages) = extractTextAndImages(from: event.artifact.parts, artifactName: event.artifact.name)
                accumulatedImages.append(contentsOf: artifactImages)
                
                if event.append == true {
                    responseText += artifactText
                } else {
                    responseText = artifactText
                }
                if event.lastChunk == true {
                    let metadata = createMetadataWithImages(accumulatedImages)
                    returnResponses.append(LLMResponse.complete(content: responseText, metadata: metadata))
                    responseText = ""
                    accumulatedImages = []
                }
            case .taskStatusUpdate(let event):
                if event.status.state == .completed, (!responseText.isEmpty || !accumulatedImages.isEmpty) {
                    let metadata = createMetadataWithImages(accumulatedImages)
                    returnResponses.append(LLMResponse.complete(content: responseText, metadata: metadata))
                    responseText = ""
                    accumulatedImages = []
                }
            }
        }
        return returnResponses
    }
    
    // MARK: - Helper Methods for Image Extraction
    
    /// Extracts text and images from A2A message parts
    private func extractTextAndImages(from parts: [A2AMessagePart], artifactName: String? = nil) -> (text: String, images: [Message.Image]) {
        var textParts: [String] = []
        var images: [Message.Image] = []
        
        for (index, part) in parts.enumerated() {
            switch part {
            case .text(let text):
                if !text.isEmpty {
                    textParts.append(text)
                }
            case .file(let data, let url):
                if let imageData = data {
                    // Determine MIME type from artifact metadata or file extension
                    let mimeType = detectMIMEType(from: imageData)
                    let imageName = artifactName ?? "image-\(index + 1)"
                    
                    // Create Message.Image from file data
                    let image = Message.Image(
                        name: imageName,
                        path: url?.absoluteString,
                        imageData: imageData,
                        thumbData: nil
                    )
                    images.append(image)
                    
                    logger.debug(
                        "Extracted image from file part",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("imageName", .string(imageName)),
                            ("dataSize", .stringConvertible(imageData.count)),
                            ("mimeType", .string(mimeType ?? "unknown"))
                        )
                    )
                } else if let url = url {
                    // If URL but no data, create image with path only
                    let imageName = artifactName ?? "image-\(index + 1)"
                    let image = Message.Image(
                        name: imageName,
                        path: url.absoluteString,
                        imageData: nil,
                        thumbData: nil
                    )
                    images.append(image)
                    
                    logger.debug(
                        "Extracted image URL from file part",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("imageName", .string(imageName)),
                            ("url", .string(url.absoluteString))
                        )
                    )
                }
            case .data(let data):
                // Try to detect if it's image data
                let mimeType = detectMIMEType(from: data)
                if mimeType?.hasPrefix("image/") == true {
                    let imageName = artifactName ?? "image-\(index + 1)"
                    let image = Message.Image(
                        name: imageName,
                        path: nil,
                        imageData: data,
                        thumbData: nil
                    )
                    images.append(image)
                    
                    logger.debug(
                        "Extracted image from data part",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("imageName", .string(imageName)),
                            ("dataSize", .stringConvertible(data.count)),
                            ("mimeType", .string(mimeType ?? "unknown"))
                        )
                    )
                }
            }
        }
        
        let text = textParts.joined(separator: " ")
        return (text, images)
    }
    
    /// Creates LLMMetadata with images stored in modelMetadata
    private func createMetadataWithImages(_ images: [Message.Image]) -> LLMMetadata? {
        guard !images.isEmpty else { return nil }
        
        // Convert images to JSON array
        let imagesJSON = images.map { $0.toEasyJSON(includeImageData: true, includeThumbData: false) }
        
        // Store in modelMetadata
        let modelMetadata = try? JSON([
            "images": JSON.array(imagesJSON)
        ])
        
        return LLMMetadata(modelMetadata: modelMetadata)
    }
    
    /// Detects MIME type from image data by checking magic bytes
    private func detectMIMEType(from data: Data) -> String? {
        guard data.count >= 8 else { return nil }
        
        // Check for common image magic bytes
        let firstBytes = Array(data.prefix(8))
        
        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if firstBytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return "image/png"
        }
        
        // JPEG: FF D8 FF
        if firstBytes.prefix(3).starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        
        // GIF: 47 49 46 38 (GIF8)
        if firstBytes.prefix(4).starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return "image/gif"
        }
        
        // WebP: 52 49 46 46 (RIFF) followed by WEBP
        if firstBytes.prefix(4).starts(with: [0x52, 0x49, 0x46, 0x46]) && data.count >= 12 {
            let webpBytes = Array(data.prefix(12).suffix(4))
            if String(bytes: webpBytes, encoding: .ascii) == "WEBP" {
                return "image/webp"
            }
        }
        
        // BMP: 42 4D (BM)
        if firstBytes.prefix(2).starts(with: [0x42, 0x4D]) {
            return "image/bmp"
        }
        
        return nil
    }
    
    /// Get all available tools from A2A clients
    public func availableTools() async -> [ToolDefinition] {
        var allTools: [ToolDefinition] = []
        for client in clients {
            if let agentCard = await client.agentCard {
                allTools.append(ToolDefinition(
                    name: agentCard.name,
                    description: agentCard.description,
                    parameters: [
                        .init(name: "instructions", description: "Issue a task for this agent to complete on your behalf.", type: "string", required: true)
                    ],
                    type: .a2aAgent
                ))
            }
        }
        return allTools
    }
    
    // MARK: - Private
    
    private var clients: [A2AClient] = []
    
    private func loadA2AConfiguration(configFileURL: URL) async throws {
        do {
            let config = try A2AConfigHelper.parseA2AConfig(fileURL: configFileURL)
            try await createClients(config)
            state = .initialized
        } catch {
            logger.error(
                "Error loading A2A configuration",
                metadata: SwiftAgentKitLogging.metadata(
                    ("configURL", .string(configFileURL.absoluteString)),
                    ("error", .string(String(describing: error)))
                )
            )
            state = .notReady
            throw error
        }
    }
    
    private func createClients(_ config: A2AConfig) async throws {
        logger.info(
            "Creating A2A clients",
            metadata: SwiftAgentKitLogging.metadata(
                ("serverCount", .stringConvertible(config.servers.count))
            )
        )
        for server in config.servers {
            let bootCall = config.serverBootCalls.first(where: { $0.name == server.name })
            let clientLogger = SwiftAgentKitLogging.logger(
                for: .a2a("A2AClient"),
                metadata: SwiftAgentKitLogging.metadata(
                    ("serverName", .string(server.name)),
                    ("serverURL", .string(server.url.absoluteString))
                )
            )
            let client = A2AClient(server: server, bootCall: bootCall, logger: clientLogger)
            do {
                try await client.initializeA2AClient(globalEnvironment: config.globalEnvironment)
                clients.append(client)
                logger.info(
                    "Initialized A2A client",
                    metadata: SwiftAgentKitLogging.metadata(("serverName", .string(server.name)))
                )
            } catch {
                logger.error(
                    "Failed to initialize A2A client",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("serverName", .string(server.name)),
                        ("error", .string(String(describing: error)))
                    )
                )
                throw error
            }
        }
        await buildToolsJson()
    }
    
    private func buildToolsJson() async {
        var json: [[String: Any]] = []
        for client in clients {
            guard let agentCard = await client.agentCard else { continue }
            json.append(agentCard.toolCallJson())
        }
        toolCallsJson = json
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            toolCallsJsonString = String(data: data, encoding: .utf8)
        }
        logger.debug(
            "Built tools JSON",
            metadata: SwiftAgentKitLogging.metadata(("toolCount", .stringConvertible(json.count)))
        )
    }
}

extension AgentCard.AgentSkill {
    func toJson() -> [String: Any] {
        var returnValue: [String: Any] = [
            "name": name,
            "description": description,
            "tags": tags,
        ]
        if let inputModes = inputModes {
            returnValue["input-modes"] = inputModes
        }
        if let outputModes = outputModes {
            returnValue["output-modes"] = outputModes
        }
        return returnValue
    }
}

extension AgentCard {
     func toolCallJson() -> [String: Any] {
         var returnValue: [String: Any] = [:]
         returnValue[name] = [
            "description": description,
            "skills": skills.map({$0.toJson()}),
         ]
         return returnValue
    }
}
