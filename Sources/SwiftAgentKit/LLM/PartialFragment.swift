import Foundation

/// A discriminated partial delta from a streaming LLM response, used by orchestrators and harnesses
/// to surface assistant-visible text separately from reasoning and streaming tool-call payloads.
///
/// Downstream servers can map cases trivially to discriminated streaming models (for example
/// Silenia’s `ChatStreamingPartial` / `ModelContentDeltaWire` with `kind: text | reasoning | toolCall`).
public enum PartialFragment: Sendable, Equatable {
    /// Assistant-visible output text (legacy string streams typically expose only this).
    case text(String)
    /// Extended thinking / reasoning delta when the provider exposes it separately from user-visible text.
    case reasoning(String)
    /// Streaming tool invocation: merge ``argumentsFragment`` values per ``id`` on the consumer side.
    case toolCall(id: String?, name: String?, argumentsFragment: String)
}
