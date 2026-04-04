import Foundation

/// Controls how the model uses tools when the request includes tool definitions.
///
/// `LLMProtocol` implementations map this to provider-specific fields (e.g. OpenAI `tool_choice`).
/// Backends that do not support forcing tools should treat unsupported cases as ``automatic``.
public enum ToolInvocationPolicy: String, Sendable, Codable, CaseIterable {
    /// Provider default: model may answer with text or call tools.
    case automatic
    /// Require at least one tool call when tools are non-empty (e.g. OpenAI `tool_choice: required`).
    case required
    /// Prefer a plain assistant message; do not force tools (maps to OpenAI `tool_choice: none` when applicable).
    case none
}
