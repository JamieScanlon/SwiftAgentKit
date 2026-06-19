import Foundation

/// The tool-choice capabilities a model can advertise via ``ModelRequestFeatures/toolChoiceModes``.
///
/// This is a capability marker (no associated value); the concrete tool name for a forced
/// single-tool call is carried by ``ToolInvocationPolicy/specific(toolName:)``.
public enum ToolChoiceMode: String, Sendable, Hashable, Codable, CaseIterable {
    /// Model may answer with text or call tools (provider default).
    case auto
    /// Model is asked to avoid tools and produce a plain message.
    case none
    /// Model must call at least one tool when tools are non-empty.
    case required
    /// Model can be forced to call a single named tool.
    case specific
}

/// Controls how the model uses tools when the request includes tool definitions.
///
/// `LLMProtocol` implementations map this to provider-specific fields (e.g. OpenAI `tool_choice`).
/// Backends that do not support a requested mode should clamp it to the nearest supported mode,
/// defaulting to ``automatic`` (see ``ModelRequestFeatures/resolve(_:)``).
public enum ToolInvocationPolicy: Sendable, Hashable, Codable {
    /// Provider default: model may answer with text or call tools.
    case automatic
    /// Require at least one tool call when tools are non-empty (e.g. OpenAI `tool_choice: required`).
    case required
    /// Prefer a plain assistant message; do not force tools (maps to OpenAI `tool_choice: none` when applicable).
    case none
    /// Force the model to call a single named tool (maps to OpenAI `tool_choice: {type: function, ...}`).
    case specific(toolName: String)

    /// The capability this policy requires from the model.
    public var mode: ToolChoiceMode {
        switch self {
        case .automatic: return .auto
        case .required: return .required
        case .none: return .none
        case .specific: return .specific
        }
    }

    // MARK: - Codable

    /// Backward-compatible coding: `.automatic` / `.required` / `.none` encode as the
    /// original plain strings; `.specific` encodes as `{"specific": "<toolName>"}`.
    /// Decoding accepts either a bare string or that object form.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let raw = try? container.decode(String.self) {
            switch raw {
            case "automatic": self = .automatic
            case "required": self = .required
            case "none": self = .none
            default:
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath,
                          debugDescription: "Unknown ToolInvocationPolicy value: \(raw)")
                )
            }
            return
        }

        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        let toolName = try keyed.decode(String.self, forKey: .specific)
        self = .specific(toolName: toolName)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .automatic, .required, .none:
            var container = encoder.singleValueContainer()
            switch self {
            case .automatic: try container.encode("automatic")
            case .required: try container.encode("required")
            case .none: try container.encode("none")
            case .specific: break // unreachable
            }
        case .specific(let toolName):
            var keyed = encoder.container(keyedBy: CodingKeys.self)
            try keyed.encode(toolName, forKey: .specific)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case specific
    }
}
