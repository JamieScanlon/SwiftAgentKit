//
//  ACPManager.swift
//  SwiftAgentKitACP
//

import Foundation
import Logging
import SwiftAgentKit
import EasyJSON

/// Protocol for ACP clients that support prompt streaming; allows injection of test doubles.
public protocol ACPAgentStreamClient: Sendable {
    var agentInfo: ACPImplementation? { get async }
    func promptStream(_ instructions: String) async throws -> (ACPPromptResponse, AsyncStream<ACPSessionUpdate>)
    func shutdown() async
    var toolCallTimeout: TimeInterval? { get async }
}

public extension ACPAgentStreamClient {
    var toolCallTimeout: TimeInterval? {
        get async { nil }
    }
}

extension ACPClient: ACPAgentStreamClient {
    public func promptStream(_ instructions: String) async throws -> (ACPPromptResponse, AsyncStream<ACPSessionUpdate>) {
        try await prompt(instructions)
    }
}

/// Manages tool calling via ACP agents.
public actor ACPManager {
    private let logger: Logger

    public enum State: Sendable {
        case notReady
        case initialized
    }

    public var state: State = .notReady
    public var toolCallsJson: [[String: Any]] = []
    public var toolCallsJsonString: String? {
        guard let data = try? JSONSerialization.data(withJSONObject: toolCallsJson) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    public private(set) var ingestionDiagnostics: [ToolIngestionDiagnostic] = []
    public private(set) var toolCallTimeout: TimeInterval? = nil
    public private(set) var clients: [ACPClient] = []

    private var streamClients: [any ACPAgentStreamClient] = []
    private var localProcesses: [String: Process] = [:]

    public init(logger: Logger? = nil) {
        self.logger = logger ?? SwiftAgentKitLogging.logger(for: .acp("ACPManager"))
    }

    public func initialize(configFileURL: URL) async throws {
        try await loadACPConfiguration(configFileURL: configFileURL)
    }

    public func initialize(clients: [any ACPAgentStreamClient]) async throws {
        toolCallTimeout = nil
        streamClients = clients
        localProcesses = [:]
        await buildToolsJson()
        state = .initialized
    }

    public func agentCall(_ toolCall: ToolCall, orchestratorDefaultTimeout: TimeInterval = 300) async throws -> [LLMResponse]? {
        var matchingClient: (any ACPAgentStreamClient)?
        for client in streamClients {
            guard let info = await client.agentInfo else { continue }
            if info.name == toolCall.name {
                matchingClient = client
                break
            }
        }
        guard let client = matchingClient else { return nil }
        guard case .object(let argsDict) = toolCall.arguments,
              case .string(let instructions) = argsDict["instructions"] else { return nil }

        let seconds = Self.resolvedToolCallTimeout(
            client: await client.toolCallTimeout,
            configDefault: toolCallTimeout,
            orchestrator: orchestratorDefaultTimeout
        )
        return try await withToolCallTimeout(seconds, toolName: toolCall.name) {
            try await self.executeAgentCall(client: client, toolCall: toolCall, instructions: instructions)
        }
    }

    public func availableTools() async -> [ToolDefinition] {
        var tools: [ToolDefinition] = []
        for client in streamClients {
            guard let info = await client.agentInfo else { continue }
            tools.append(ToolDefinition(
                name: info.name,
                description: info.title ?? "ACP agent \(info.name)",
                parameters: [
                    .init(name: "instructions", description: "Instructions for the ACP agent.", type: "string", required: true)
                ],
                type: .acpAgent
            ))
        }
        return tools
    }

    public func registeredToolDescriptors(
        targetProviderCapabilities: ToolSchemaTargetProviderCapabilities = .providerSafe
    ) async -> [RegisteredToolDescriptor] {
        let normalizer = ToolSchemaNormalizer()
        var descriptors: [RegisteredToolDescriptor] = []
        for client in streamClients {
            guard let info = await client.agentInfo else { continue }
            let definition = ToolDefinition(
                name: info.name,
                description: info.title ?? "ACP agent \(info.name)",
                parameters: [
                    .init(name: "instructions", description: "Instructions for the ACP agent.", type: "string", required: true)
                ],
                type: .acpAgent
            )
            let normalized = normalizer.normalize(
                rawSchema: definition.inferredSchemaJSON,
                source: .acp,
                targetProviderCapabilities: targetProviderCapabilities
            )
            descriptors.append(
                RegisteredToolDescriptor(
                    definition: definition,
                    source: .acp,
                    effectClass: .mutating,
                    parallelHint: .serialOnly,
                    policyTags: [],
                    normalizedSchema: normalized
                )
            )
        }
        return descriptors
    }

    public func shutdown() async {
        for client in streamClients {
            await client.shutdown()
        }
        for (_, process) in localProcesses {
            Shell.terminateProcess(process)
        }
        localProcesses.removeAll()
        streamClients.removeAll()
        clients.removeAll()
        state = .notReady
    }

    private func executeAgentCall(
        client: any ACPAgentStreamClient,
        toolCall: ToolCall,
        instructions: String
    ) async throws -> [LLMResponse] {
        let (response, updates) = try await client.promptStream(instructions)
        var text = ""
        for await update in updates {
            if case .agentMessageChunk(_, let content) = update,
               case .text(let chunk) = content {
                text += chunk
            }
        }
        if text.isEmpty {
            text = "ACP agent completed with stop reason: \(response.stopReason.rawValue)"
        }
        return [LLMResponse.complete(
            content: text,
            metadata: LLMMetadata(
                modelMetadata: .object([
                    "source": .string("acp_agent"),
                    "stopReason": .string(response.stopReason.rawValue)
                ])
            )
        )]
    }

    private func loadACPConfiguration(configFileURL: URL) async throws {
        let config = try ACPConfigHelper.parseACPConfig(fileURL: configFileURL)
        toolCallTimeout = config.toolCallTimeout
        var bootedClients: [ACPClient] = []

        for bootCall in config.agentBootCalls {
            var environment = config.globalEnvironment.acpEnvironment
            environment.merge(bootCall.environment.acpEnvironment, uniquingKeysWith: { _, new in new })
            do {
                let client = try await ACPClient.boot(
                    name: bootCall.name,
                    command: bootCall.command,
                    arguments: bootCall.arguments,
                    environment: environment,
                    useShell: bootCall.useShell,
                    toolCallTimeout: bootCall.toolCallTimeout ?? config.toolCallTimeout
                )
                bootedClients.append(client)
            } catch {
                ingestionDiagnostics.append(ToolIngestionDiagnostic(
                    toolName: bootCall.name,
                    source: .acp,
                    message: "Failed to boot ACP agent: \(error)"
                ))
                logger.error(
                    "Failed to boot ACP agent",
                    metadata: SwiftAgentKitLogging.metadata(
                        ("name", .string(bootCall.name)),
                        ("error", .string(String(describing: error)))
                    )
                )
            }
        }

        clients = bootedClients
        streamClients = bootedClients
        await buildToolsJson()
        state = .initialized
    }

    private func buildToolsJson() async {
        toolCallsJson = await availableTools().map { $0.toolCallJson() }
    }

    private static func resolvedToolCallTimeout(
        client: TimeInterval?,
        configDefault: TimeInterval?,
        orchestrator: TimeInterval
    ) -> TimeInterval {
        client ?? configDefault ?? orchestrator
    }
}
