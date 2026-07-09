import Foundation
import SwiftAgentKit
import EasyJSON

public enum ToolInvocationSource: String, Sendable, Codable, Equatable {
    case model
    case command
    case direct
    case system
}

public enum ToolInvocationArgumentMode: String, Sendable, Codable, Equatable {
    case parsed
    case raw
}

public struct RawToolCommandEnvelope: Sendable, Codable {
    public let envelopeVersion: String
    public let rawText: String
    public let commandToken: String?
    public let commandName: String?
    public let argsText: String?
    public let parsedTokens: [String]?

    public init(
        envelopeVersion: String = "1",
        rawText: String,
        commandToken: String? = nil,
        commandName: String? = nil,
        argsText: String? = nil,
        parsedTokens: [String]? = nil
    ) {
        self.envelopeVersion = envelopeVersion
        self.rawText = rawText
        self.commandToken = commandToken
        self.commandName = commandName
        self.argsText = argsText
        self.parsedTokens = parsedTokens
    }
}

public enum ToolDispatchPlannerMode: String, Sendable, Codable, Equatable {
    case serial
    case allParallel
    case mixedDeterministic
}

public struct ToolInvocationRequest: Sendable, Codable {
    public let toolName: String
    public let argumentsPayload: JSON
    public let toolCallID: String
    public let argumentMode: ToolInvocationArgumentMode
    public let rawEnvelope: RawToolCommandEnvelope?
    public let conversationID: String?
    public let runID: String?
    public let source: ToolInvocationSource
    public let callerProvenance: String?
    public let policyContext: JSON?
    public let timeoutSeconds: TimeInterval?

    public init(
        toolName: String,
        argumentsPayload: JSON = .object([:]),
        toolCallID: String? = nil,
        argumentMode: ToolInvocationArgumentMode = .parsed,
        rawEnvelope: RawToolCommandEnvelope? = nil,
        conversationID: String? = nil,
        runID: String? = nil,
        source: ToolInvocationSource = .direct,
        callerProvenance: String? = nil,
        policyContext: JSON? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) {
        self.toolName = toolName
        self.argumentsPayload = argumentsPayload
        self.toolCallID = toolCallID ?? "call_\(UUID().uuidString.prefix(8))"
        self.argumentMode = argumentMode
        self.rawEnvelope = rawEnvelope
        self.conversationID = conversationID
        self.runID = runID
        self.source = source
        self.callerProvenance = callerProvenance
        self.policyContext = policyContext
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct ToolBatchInvocationRequest: Sendable, Codable {
    public let requests: [ToolInvocationRequest]
    public let plannerMode: ToolDispatchPlannerMode?
    public let defaultTimeoutSeconds: TimeInterval?
    public let conversationID: String?
    public let runID: String?
    public let source: ToolInvocationSource
    /// When set, overrides ``OrchestratorConfig/parallelToolDispatchEnabled`` for this batch.
    public let parallelToolDispatchEnabled: Bool?
    /// When set, overrides ``OrchestratorConfig/maxParallelInFlightPerStage`` for this batch.
    public let maxParallelInFlightPerStage: Int?

    public init(
        requests: [ToolInvocationRequest],
        plannerMode: ToolDispatchPlannerMode? = nil,
        defaultTimeoutSeconds: TimeInterval? = nil,
        conversationID: String? = nil,
        runID: String? = nil,
        source: ToolInvocationSource = .direct,
        parallelToolDispatchEnabled: Bool? = nil,
        maxParallelInFlightPerStage: Int? = nil
    ) {
        self.requests = requests
        self.plannerMode = plannerMode
        self.defaultTimeoutSeconds = defaultTimeoutSeconds
        self.conversationID = conversationID
        self.runID = runID
        self.source = source
        self.parallelToolDispatchEnabled = parallelToolDispatchEnabled
        self.maxParallelInFlightPerStage = maxParallelInFlightPerStage
    }
}

public struct ToolDispatchPlanStage: Sendable, Codable {
    public let mode: ToolDispatchMode
    public let toolCallIDs: [String]

    public init(mode: ToolDispatchMode, toolCallIDs: [String]) {
        self.mode = mode
        self.toolCallIDs = toolCallIDs
    }
}

public struct ToolDispatchPlanDiagnostics: Sendable, Codable {
    public let plannerMode: ToolDispatchPlannerMode
    public let reason: String
    public let stages: [ToolDispatchPlanStage]

    public init(plannerMode: ToolDispatchPlannerMode, reason: String, stages: [ToolDispatchPlanStage]) {
        self.plannerMode = plannerMode
        self.reason = reason
        self.stages = stages
    }
}

public enum ToolPreDispatchDecision: String, Sendable, Codable, Equatable {
    case allow
    case deny
    case requireApproval
    case elevated
}

public struct ToolApprovalSpec: Sendable, Codable {
    public let title: String
    public let description: String
    public let severity: String
    public let timeoutMs: Int?
    public let timeoutBehavior: String?

    public init(
        title: String,
        description: String,
        severity: String,
        timeoutMs: Int? = nil,
        timeoutBehavior: String? = nil
    ) {
        self.title = title
        self.description = description
        self.severity = severity
        self.timeoutMs = timeoutMs
        self.timeoutBehavior = timeoutBehavior
    }
}

public struct ToolPreDispatchPolicyDecision: Sendable, Codable {
    public let decision: ToolPreDispatchDecision
    public let reasonCode: String?
    public let reasonText: String?
    public let approvalSpec: ToolApprovalSpec?

    public init(
        decision: ToolPreDispatchDecision,
        reasonCode: String? = nil,
        reasonText: String? = nil,
        approvalSpec: ToolApprovalSpec? = nil
    ) {
        self.decision = decision
        self.reasonCode = reasonCode
        self.reasonText = reasonText
        self.approvalSpec = approvalSpec
    }
}

public struct ToolPreDispatchPolicyContext: Sendable, Codable {
    public let request: ToolInvocationRequest
    public let descriptor: RegisteredToolDescriptor?

    public init(request: ToolInvocationRequest, descriptor: RegisteredToolDescriptor?) {
        self.request = request
        self.descriptor = descriptor
    }
}

public protocol ToolPreDispatchPolicyEvaluating: Sendable {
    func decide(_ context: ToolPreDispatchPolicyContext) async -> ToolPreDispatchPolicyDecision
}

public struct ToolInvocationMetadata: Sendable, Codable {
    public let conversationID: String?
    public let runID: String?
    public let source: ToolInvocationSource
    public let callerProvenance: String?
    public let policyDecision: ToolPreDispatchPolicyDecision?
    public let dispatchMode: ToolDispatchMode?
    public let dispatchPlan: ToolDispatchPlanDiagnostics?

    public init(
        conversationID: String?,
        runID: String?,
        source: ToolInvocationSource,
        callerProvenance: String?,
        policyDecision: ToolPreDispatchPolicyDecision?,
        dispatchMode: ToolDispatchMode?,
        dispatchPlan: ToolDispatchPlanDiagnostics?
    ) {
        self.conversationID = conversationID
        self.runID = runID
        self.source = source
        self.callerProvenance = callerProvenance
        self.policyDecision = policyDecision
        self.dispatchMode = dispatchMode
        self.dispatchPlan = dispatchPlan
    }
}

public enum ToolInvocationOutcome: Sendable, Codable {
    case completed(result: ToolResult, metadata: ToolInvocationMetadata)
    case pending(handle: PendingToolHandle, metadata: ToolInvocationMetadata)
    case denied(metadata: ToolInvocationMetadata)
    case approvalRequired(metadata: ToolInvocationMetadata)
}

public struct ToolBatchInvocationOutcome: Sendable, Codable {
    public let outcomes: [ToolInvocationOutcome]
    public let diagnostics: ToolDispatchPlanDiagnostics

    public init(outcomes: [ToolInvocationOutcome], diagnostics: ToolDispatchPlanDiagnostics) {
        self.outcomes = outcomes
        self.diagnostics = diagnostics
    }
}
