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

/// Protocol for A2A clients that support streaming; allows injection of test doubles.
public protocol A2AAgentStreamClient: Sendable {
    var agentCard: AgentCard? { get async }
    func streamMessage(params: MessageSendParams) async throws -> AsyncStream<SendStreamingMessageSuccessResponse<MessageResult>>
    func shutdown() async
    /// Per-server tool-call limit from A2A config (seconds). Default implementation returns `nil`.
    var toolCallTimeout: TimeInterval? { get async }
}

public extension A2AAgentStreamClient {
    func shutdown() async {}
    var toolCallTimeout: TimeInterval? {
        get async { nil }
    }
}

/// Protocol for A2A clients that support task lifecycle operations such as cancellation and polling.
public protocol A2ATaskLifecycleClient: A2AAgentStreamClient {
    func cancelTask(params: TaskIdParams) async throws -> A2ATask
    func getTask(params: TaskQueryParams) async throws -> A2ATask
}

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
    public private(set) var ingestionDiagnostics: [ToolIngestionDiagnostic] = []
    /// When the manager was initialized from a config file that set ``A2AConfig/toolCallTimeout``, that value is stored here. Otherwise `nil` (call sites fall back to the orchestrator’s default tool-call timeout).
    public private(set) var toolCallTimeout: TimeInterval? = nil
    
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
    
    /// Initialize the A2AManager with an array of stream-capable A2A clients (e.g. `A2AClient` or test doubles).
    public func initialize(clients: [any A2AAgentStreamClient]) async throws {
        toolCallTimeout = nil
        self.clients = clients
        await buildToolsJson()
    }

    /// Returns the stream client whose agent card name matches `name` (case-sensitive).
    public func client(forAgentNamed name: String) async -> (any A2AAgentStreamClient)? {
        for client in clients {
            guard let agentCard = await client.agentCard else { continue }
            if agentCard.name == name {
                return client
            }
        }
        return nil
    }

    /// Returns the agent card for the client whose name matches `name`, or `nil` if not found.
    public func agentCard(forAgentNamed name: String) async -> AgentCard? {
        guard let client = await client(forAgentNamed: name) else { return nil }
        return await client.agentCard
    }
    
    /// Streams normalized incremental A2A delegate events for a tool call.
    ///
    /// - Parameter orchestratorDefaultTimeout: Used when neither per-server nor root A2A config sets a tool-call timeout.
    /// - Throws: ``A2AManagerError/agentNotFound(_:)`` or ``A2AManagerError/invalidArguments`` before the stream starts.
    public func streamAgentCall(
        _ toolCall: ToolCall,
        invocationID: String,
        orchestratorDefaultTimeout: TimeInterval = 300
    ) async throws -> (handle: A2ADelegateInvocationHandle, events: AsyncStream<A2ADelegateStreamEvent>) {
        guard let client = await resolveClient(for: toolCall) else {
            throw A2AManagerError.agentNotFound(toolCall.name)
        }
        guard let instructions = validateInstructions(in: toolCall) else {
            throw A2AManagerError.invalidArguments
        }

        let handle = A2ADelegateInvocationHandle(
            invocationID: invocationID,
            toolCallID: toolCall.id,
            agentName: toolCall.name
        )
        let timeout = Self.resolvedToolCallTimeout(
            client: await client.toolCallTimeout,
            configDefault: toolCallTimeout,
            orchestrator: orchestratorDefaultTimeout
        )

        registerInFlight(
            invocationID: invocationID,
            toolCallID: toolCall.id,
            agentName: toolCall.name,
            client: client
        )

        let events = AsyncStream(A2ADelegateStreamEvent.self) { continuation in
            let streamTask = Task {
                final class TerminalState: @unchecked Sendable {
                    var terminalEmitted = false
                }
                let terminalState = TerminalState()
                let yield: @Sendable (A2ADelegateStreamEvent) -> Void = { event in
                    switch event {
                    case .completed, .failed:
                        terminalState.terminalEmitted = true
                    default:
                        break
                    }
                    continuation.yield(event)
                }
                defer {
                    Task { await self.deregisterInFlight(invocationID: invocationID) }
                }
                do {
                    try await withToolCallTimeout(timeout, toolName: toolCall.name) {
                        _ = try await self.processAgentStream(
                            client: client,
                            toolCall: toolCall,
                            instructions: instructions,
                            agentName: toolCall.name,
                            invocationID: invocationID,
                            yield: yield
                        )
                    }
                } catch is CancellationError {
                    if !terminalState.terminalEmitted {
                        let snapshot = await self.inFlightByInvocationID[invocationID]?.snapshot
                        continuation.yield(.failed(A2ADelegateFailure(
                            error: "Cancelled",
                            taskID: snapshot?.taskID
                        )))
                    }
                } catch {
                    if !terminalState.terminalEmitted {
                        let snapshot = await self.inFlightByInvocationID[invocationID]?.snapshot
                        continuation.yield(.failed(A2ADelegateFailure(
                            error: String(describing: error),
                            taskID: snapshot?.taskID
                        )))
                    }
                }
                continuation.finish()
            }
            Task { await self.setStreamTask(invocationID: invocationID, task: streamTask) }
        }
        return (handle, events)
    }

    /// Cancels an in-flight A2A agent call by invocation ID, tool call ID, or A2A task ID.
    ///
    /// Cancels the local stream task and, when a task ID is known, calls `tasks/cancel` on the matching client.
    /// - Returns: `true` if a matching in-flight invocation was found and cancellation was attempted.
    public func cancelAgentCall(
        invocationID: String? = nil,
        toolCallID: String? = nil,
        taskID: String? = nil
    ) async -> Bool {
        guard let resolvedInvocationID = resolveInFlightInvocationID(
            invocationID: invocationID,
            toolCallID: toolCallID,
            taskID: taskID
        ), let record = inFlightByInvocationID[resolvedInvocationID] else {
            return false
        }

        record.streamTask?.cancel()

        if let taskID = record.snapshot.taskID {
            if let lifecycleClient = record.client as? any A2ATaskLifecycleClient {
                do {
                    _ = try await lifecycleClient.cancelTask(params: TaskIdParams(taskId: taskID))
                } catch {
                    logger.debug(
                        "Remote A2A task cancel failed",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("taskID", .string(taskID)),
                            ("error", .string(String(describing: error)))
                        )
                    )
                }
            } else {
                logger.debug(
                    "Skipping remote A2A task cancel; client does not conform to A2ATaskLifecycleClient",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("taskID", .string(taskID)),
                        ("agentName", .string(record.snapshot.agentName))
                    )
                )
            }
        }

        deregisterInFlight(invocationID: resolvedInvocationID)
        return true
    }

    @available(*, deprecated, message: "Use cancelAgentCall(toolCallID:)")
    public func cancelPendingHandle(_ handleID: String) async -> Bool {
        await cancelAgentCall(invocationID: handleID, toolCallID: handleID, taskID: handleID)
    }

    /// - Parameter orchestratorDefaultTimeout: Used when neither per-server nor root A2A config sets a tool-call timeout.
    public func agentCall(_ toolCall: ToolCall, orchestratorDefaultTimeout: TimeInterval = 300) async throws -> [LLMResponse]? {
        do {
            let (_, events) = try await streamAgentCall(
                toolCall,
                invocationID: toolCall.id ?? UUID().uuidString,
                orchestratorDefaultTimeout: orchestratorDefaultTimeout
            )
            return await collectResponses(from: events)
        } catch A2AManagerError.agentNotFound, A2AManagerError.invalidArguments {
            return nil
        }
    }

    private func resolveClient(for toolCall: ToolCall) async -> (any A2AAgentStreamClient)? {
        await client(forAgentNamed: toolCall.name)
    }

    private func validateInstructions(in toolCall: ToolCall) -> String? {
        guard case .object(let argsDict) = toolCall.arguments,
              case .string(let instructions) = argsDict["instructions"] else {
            return nil
        }
        return instructions
    }

    private func processAgentStream(
        client: any A2AAgentStreamClient,
        toolCall: ToolCall,
        instructions: String,
        agentName: String,
        invocationID: String,
        yield: (@Sendable (A2ADelegateStreamEvent) -> Void)?
    ) async throws -> [LLMResponse] {
        yield?(.connecting(agentName: agentName))

        let a2aMessage = A2AMessage(role: "user", parts: [.text(text: instructions)], messageId: UUID().uuidString)
        let params: MessageSendParams = .init(message: a2aMessage, metadata: try? .init(["toolCallId": toolCall.id]))
        let contents = try await client.streamMessage(params: params)

        var returnResponses: [LLMResponse] = []
        var responseText: String = ""
        var accumulatedImages: [Message.Image] = []
        var accumulatedFiles: [LLMResponseFile] = []
        var taskID: String?
        var contextID: String?
        var terminalEmitted = false

        func updateTaskIdentity(taskID: String, contextID: String) {
            self.updateInFlightTaskIdentity(
                invocationID: invocationID,
                taskID: taskID,
                contextID: contextID
            )
        }

        func emitFailed(_ error: String) {
            guard !terminalEmitted else { return }
            terminalEmitted = true
            yield?(.failed(A2ADelegateFailure(error: error, taskID: taskID)))
        }

        func emitCompleted() {
            guard !terminalEmitted else { return }
            terminalEmitted = true
            let metadata = createMetadata(images: accumulatedImages, files: accumulatedFiles)
            yield?(.completed(A2ADelegateCompletion(
                content: responseText,
                metadata: metadata,
                taskID: taskID,
                contextID: contextID
            )))
        }

        for await content in contents {
            try Task.checkCancellation()

            switch content.result {
            case .message(let aMessage):
                let (text, images, files) = extractTextImagesAndFiles(from: aMessage.parts)
                accumulatedImages.append(contentsOf: images)
                accumulatedFiles.append(contentsOf: files)
                yield?(.messageChunk(text: text, images: images, files: files))
                let metadata = createMetadata(images: images, files: files)
                returnResponses.append(LLMResponse.complete(content: text, metadata: metadata))

            case .task(let task):
                taskID = task.id
                contextID = task.contextId
                updateTaskIdentity(taskID: task.id, contextID: task.contextId)
                yield?(.taskStarted(taskID: task.id, contextID: task.contextId))

                var text: String = ""
                var taskImages: [Message.Image] = []
                var taskFiles: [LLMResponseFile] = []
                if let artifacts = task.artifacts {
                    for artifact in artifacts {
                        let (artifactText, artifactImages, artifactFiles) = extractTextImagesAndFiles(from: artifact.parts, artifactName: artifact.name)
                        text += artifactText
                        taskImages.append(contentsOf: artifactImages)
                        taskFiles.append(contentsOf: artifactFiles)
                    }
                }
                accumulatedImages.append(contentsOf: taskImages)
                accumulatedFiles.append(contentsOf: taskFiles)
                if !text.isEmpty || !taskImages.isEmpty || !taskFiles.isEmpty {
                    yield?(.messageChunk(text: text, images: taskImages, files: taskFiles))
                }
                let metadata = createMetadata(images: taskImages, files: taskFiles)
                returnResponses.append(LLMResponse.complete(content: text, metadata: metadata))

            case .taskArtifactUpdate(let event):
                taskID = event.taskId
                contextID = event.contextId
                updateTaskIdentity(taskID: event.taskId, contextID: event.contextId)
                let (artifactText, artifactImages, artifactFiles) = extractTextImagesAndFiles(from: event.artifact.parts, artifactName: event.artifact.name)
                accumulatedImages.append(contentsOf: artifactImages)
                accumulatedFiles.append(contentsOf: artifactFiles)

                yield?(.artifactChunk(
                    taskID: event.taskId,
                    text: artifactText,
                    append: event.append ?? false,
                    lastChunk: event.lastChunk ?? false
                ))

                if event.append == true {
                    responseText += artifactText
                } else {
                    responseText = artifactText
                }
                if event.lastChunk == true {
                    let metadata = createMetadata(images: accumulatedImages, files: accumulatedFiles)
                    returnResponses.append(LLMResponse.complete(content: responseText, metadata: metadata))
                    yield?(.messageChunk(text: responseText, images: accumulatedImages, files: accumulatedFiles))
                    responseText = ""
                    accumulatedImages = []
                    accumulatedFiles = []
                }

            case .taskStatusUpdate(let event):
                taskID = event.taskId
                contextID = event.contextId
                updateTaskIdentity(taskID: event.taskId, contextID: event.contextId)
                yield?(.statusUpdate(taskID: event.taskId, state: event.status.state, final: event.final))

                switch event.status.state {
                case .failed, .rejected, .canceled:
                    let errorMessage = event.status.message?.parts.compactMap { part -> String? in
                        if case .text(let text) = part, !text.isEmpty { return text }
                        return nil
                    }.joined(separator: " ") ?? ""
                    emitFailed(errorMessage.isEmpty ? "Task \(event.status.state.rawValue)" : errorMessage)
                case .completed:
                    if !responseText.isEmpty || !accumulatedImages.isEmpty || !accumulatedFiles.isEmpty {
                        let metadata = createMetadata(images: accumulatedImages, files: accumulatedFiles)
                        returnResponses.append(LLMResponse.complete(content: responseText, metadata: metadata))
                        yield?(.messageChunk(text: responseText, images: accumulatedImages, files: accumulatedFiles))
                        responseText = ""
                        accumulatedImages = []
                        accumulatedFiles = []
                    }
                    if event.final {
                        emitCompleted()
                    }
                default:
                    break
                }
            }
        }

        if !terminalEmitted {
            if Task.isCancelled {
                emitFailed("Cancelled")
            } else {
                emitCompleted()
            }
        }

        return returnResponses
    }

    private func collectResponses(from events: AsyncStream<A2ADelegateStreamEvent>) async -> [LLMResponse] {
        var returnResponses: [LLMResponse] = []
        for await event in events {
            if case .messageChunk(let text, let images, let files) = event {
                let metadata = createMetadata(images: images, files: files)
                returnResponses.append(LLMResponse.complete(content: text, metadata: metadata))
            }
        }
        return returnResponses
    }
    
    private nonisolated static func resolvedToolCallTimeout(
        client: TimeInterval?,
        configDefault: TimeInterval?,
        orchestrator: TimeInterval
    ) -> TimeInterval {
        if let v = client, v > 0 { return v }
        if let v = configDefault, v > 0 { return v }
        return orchestrator
    }
    
    // MARK: - Helper Methods for Content Extraction
    
    /// Extracts text, images, and file/data content from A2A message parts.
    /// Image parts go to `images`; other file/data parts go to `files`.
    private func extractTextImagesAndFiles(from parts: [A2AMessagePart], artifactName: String? = nil) -> (text: String, images: [Message.Image], files: [LLMResponseFile]) {
        var textParts: [String] = []
        var images: [Message.Image] = []
        var files: [LLMResponseFile] = []
        let baseName = artifactName ?? "part"
        
        for (index, part) in parts.enumerated() {
            switch part {
            case .text(let text):
                if !text.isEmpty {
                    textParts.append(text)
                }
            case .file(let data, let url):
                if let imageData = data {
                    let mimeType = detectMIMEType(from: imageData)
                    let name = artifactName ?? "\(baseName)-\(index + 1)"
                    if mimeType?.hasPrefix("image/") == true {
                        let image = Message.Image(
                            name: name,
                            path: url?.absoluteString,
                            imageData: imageData,
                            thumbData: nil
                        )
                        images.append(image)
                        logger.debug(
                            "Extracted image from file part",
                            metadata: SwiftAgentKitLogging.metadata(
                                ("imageName", .string(name)),
                                ("dataSize", .stringConvertible(imageData.count)),
                                ("mimeType", .string(mimeType ?? "unknown"))
                            )
                        )
                    } else {
                        files.append(LLMResponseFile(name: name, mimeType: mimeType, data: imageData, url: url))
                        logger.debug(
                            "Extracted file from file part",
                            metadata: SwiftAgentKitLogging.metadata(
                                ("name", .string(name)),
                                ("dataSize", .stringConvertible(imageData.count)),
                                ("mimeType", .string(mimeType ?? "unknown"))
                            )
                        )
                    }
                } else if let url = url {
                    let name = artifactName ?? "\(baseName)-\(index + 1)"
                    files.append(LLMResponseFile(name: name, mimeType: nil, data: nil, url: url))
                    logger.debug(
                        "Extracted file URL from file part",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("name", .string(name)),
                            ("url", .string(url.absoluteString))
                        )
                    )
                }
            case .data(let data):
                let mimeType = detectMIMEType(from: data)
                let name = artifactName ?? "\(baseName)-\(index + 1)"
                if mimeType?.hasPrefix("image/") == true {
                    let image = Message.Image(
                        name: name,
                        path: nil,
                        imageData: data,
                        thumbData: nil
                    )
                    images.append(image)
                    logger.debug(
                        "Extracted image from data part",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("imageName", .string(name)),
                            ("dataSize", .stringConvertible(data.count)),
                            ("mimeType", .string(mimeType ?? "unknown"))
                        )
                    )
                } else {
                    files.append(LLMResponseFile(name: name, mimeType: mimeType, data: data, url: nil))
                    logger.debug(
                        "Extracted file from data part",
                        metadata: SwiftAgentKitLogging.metadata(
                            ("name", .string(name)),
                            ("dataSize", .stringConvertible(data.count)),
                            ("mimeType", .string(mimeType ?? "unknown"))
                        )
                    )
                }
            }
        }
        
        let text = textParts.joined(separator: " ")
        return (text, images, files)
    }
    
    /// Creates LLMMetadata with images and/or files in modelMetadata
    private func createMetadata(images: [Message.Image], files: [LLMResponseFile]) -> LLMMetadata? {
        var entries: [String: JSON] = [:]
        if !images.isEmpty {
            entries["images"] = .array(images.map { $0.toEasyJSON(includeImageData: true, includeThumbData: false) })
        }
        if !files.isEmpty {
            entries["files"] = .array(files.map { $0.toJSON() })
        }
        guard !entries.isEmpty else { return nil }
        return LLMMetadata(modelMetadata: .object(entries))
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
    
    /// Disconnects A2A clients and terminates any subprocess started for `boot` configuration.
    public func shutdown() async {
        cancelAllInFlight()
        for client in clients {
            await client.shutdown()
        }
        clients.removeAll()
        toolCallsJson = []
        toolCallsJsonString = nil
        toolCallTimeout = nil
        state = .notReady
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

    /// Canonical typed registration rows for A2A-ingested tools.
    public func registeredToolDescriptors(
        targetProviderCapabilities: ToolSchemaTargetProviderCapabilities = .providerSafe
    ) async -> [RegisteredToolDescriptor] {
        let normalizer = ToolSchemaNormalizer()
        var descriptors: [RegisteredToolDescriptor] = []
        var diagnostics: [ToolIngestionDiagnostic] = []
        for client in clients {
            guard let agentCard = await client.agentCard else { continue }
            let definition = ToolDefinition(
                name: agentCard.name,
                description: agentCard.description,
                parameters: [
                    .init(
                        name: "instructions",
                        description: "Issue a task for this agent to complete on your behalf.",
                        type: "string",
                        required: true
                    )
                ],
                type: .a2aAgent
            )
            let normalized = normalizer.normalize(
                rawSchema: definition.inferredSchemaJSON,
                source: .a2a,
                targetProviderCapabilities: targetProviderCapabilities
            )
            descriptors.append(
                RegisteredToolDescriptor(
                    definition: definition,
                    source: .a2a,
                    effectClass: .mutating,
                    parallelHint: .serialOnly,
                    policyTags: [],
                    normalizedSchema: normalized
                )
            )
            if normalized.report.didFallback {
                diagnostics.append(
                    ToolIngestionDiagnostic(
                        toolName: definition.name,
                        source: .a2a,
                        message: "Schema normalization applied fallback policy."
                    )
                )
            }
        }
        ingestionDiagnostics = diagnostics
        return descriptors
    }

    // MARK: - Private

    private struct InFlightRecord {
        var snapshot: A2AInFlightInvocation
        let client: any A2AAgentStreamClient
        var streamTask: Task<Void, Never>?
    }

    private var clients: [any A2AAgentStreamClient] = []
    private var inFlightByInvocationID: [String: InFlightRecord] = [:]
    private var inFlightByToolCallID: [String: String] = [:]
    private var inFlightByTaskID: [String: String] = [:]

    private func registerInFlight(
        invocationID: String,
        toolCallID: String?,
        agentName: String,
        client: any A2AAgentStreamClient
    ) {
        let snapshot = A2AInFlightInvocation(
            invocationID: invocationID,
            toolCallID: toolCallID,
            agentName: agentName
        )
        inFlightByInvocationID[invocationID] = InFlightRecord(snapshot: snapshot, client: client)
        if let toolCallID {
            inFlightByToolCallID[toolCallID] = invocationID
        }
    }

    private func setStreamTask(invocationID: String, task: Task<Void, Never>) {
        guard var record = inFlightByInvocationID[invocationID] else { return }
        record.streamTask = task
        inFlightByInvocationID[invocationID] = record
    }

    private func updateInFlightTaskIdentity(invocationID: String, taskID: String, contextID: String) {
        guard var record = inFlightByInvocationID[invocationID] else { return }
        if let previousTaskID = record.snapshot.taskID, previousTaskID != taskID {
            inFlightByTaskID.removeValue(forKey: previousTaskID)
        }
        record.snapshot.taskID = taskID
        record.snapshot.contextID = contextID
        inFlightByInvocationID[invocationID] = record
        inFlightByTaskID[taskID] = invocationID
    }

    private func resolveInFlightInvocationID(
        invocationID: String?,
        toolCallID: String?,
        taskID: String?
    ) -> String? {
        if let invocationID, inFlightByInvocationID[invocationID] != nil {
            return invocationID
        }
        if let toolCallID, let resolved = inFlightByToolCallID[toolCallID] {
            return resolved
        }
        if let taskID, let resolved = inFlightByTaskID[taskID] {
            return resolved
        }
        return nil
    }

    private func deregisterInFlight(invocationID: String) {
        guard let record = inFlightByInvocationID.removeValue(forKey: invocationID) else { return }
        if let toolCallID = record.snapshot.toolCallID {
            if inFlightByToolCallID[toolCallID] == invocationID {
                inFlightByToolCallID.removeValue(forKey: toolCallID)
            }
        }
        if let taskID = record.snapshot.taskID {
            if inFlightByTaskID[taskID] == invocationID {
                inFlightByTaskID.removeValue(forKey: taskID)
            }
        }
    }

    private func cancelAllInFlight() {
        let invocationIDs = Array(inFlightByInvocationID.keys)
        for invocationID in invocationIDs {
            inFlightByInvocationID[invocationID]?.streamTask?.cancel()
        }
        inFlightByInvocationID.removeAll()
        inFlightByToolCallID.removeAll()
        inFlightByTaskID.removeAll()
    }
    
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
        toolCallTimeout = config.toolCallTimeout
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
