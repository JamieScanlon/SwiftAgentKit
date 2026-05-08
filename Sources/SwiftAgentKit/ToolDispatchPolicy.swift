import Foundation

public typealias ToolCallID = String

public enum ToolDispatchMode: Sendable, Equatable, Codable {
    case serial
    case parallel
}

public enum ToolParallelSafety: Sendable, Equatable, Codable {
    case parallelSafe
    case mutating
    case unknown
}

public struct ToolDispatchPolicyDecision: Sendable, Equatable, Codable {
    public var mode: ToolDispatchMode
    public var reason: String?

    public init(mode: ToolDispatchMode, reason: String? = nil) {
        self.mode = mode
        self.reason = reason
    }
}

public protocol ToolDispatchPolicyEvaluating: Sendable {
    func decide(
        toolCalls: [ToolCall],
        metadata: [ToolCallID: ToolParallelSafety]
    ) -> ToolDispatchPolicyDecision
}

/// Default deterministic policy:
/// - unknown/missing metadata => serial
/// - any mutating => serial
/// - all parallelSafe => serial/parallel according to orchestrator mode hint
public struct DefaultToolDispatchPolicyEvaluator: ToolDispatchPolicyEvaluating {
    private let orchestratorParallelModeEnabled: Bool

    public init(orchestratorParallelModeEnabled: Bool) {
        self.orchestratorParallelModeEnabled = orchestratorParallelModeEnabled
    }

    public func decide(
        toolCalls: [ToolCall],
        metadata: [ToolCallID: ToolParallelSafety]
    ) -> ToolDispatchPolicyDecision {
        guard !toolCalls.isEmpty else {
            return ToolDispatchPolicyDecision(mode: .serial, reason: "No tool calls in batch")
        }

        var allParallelSafe = true
        for toolCall in toolCalls {
            guard let id = toolCall.id else {
                return ToolDispatchPolicyDecision(
                    mode: .serial,
                    reason: "Missing tool call ID; defaulting to serial dispatch"
                )
            }
            let safety = metadata[id] ?? .unknown
            switch safety {
            case .parallelSafe:
                continue
            case .mutating:
                return ToolDispatchPolicyDecision(
                    mode: .serial,
                    reason: "Found mutating call in batch"
                )
            case .unknown:
                return ToolDispatchPolicyDecision(
                    mode: .serial,
                    reason: "Missing/unknown parallel-safety metadata; defaulting to serial dispatch"
                )
            }
        }

        allParallelSafe = true
        if allParallelSafe, orchestratorParallelModeEnabled {
            return ToolDispatchPolicyDecision(
                mode: .parallel,
                reason: "All tool calls are parallel-safe and orchestrator parallel mode is enabled"
            )
        }
        return ToolDispatchPolicyDecision(
            mode: .serial,
            reason: "Orchestrator parallel mode disabled; using serial dispatch"
        )
    }
}
