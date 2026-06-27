import Foundation

/// A discriminated partial delta from a streaming LLM response, used by orchestrators and harnesses
/// to surface assistant-visible text separately from reasoning and streaming tool-call payloads.
///
/// Five channels are available:
/// - ``text(_:)`` — assistant-visible output text (legacy string streams typically expose only this)
/// - ``reasoning(_:)`` — extended thinking / reasoning delta
/// - ``toolCall(id:name:argumentsFragment:)`` — eager partial tool-argument JSON fragments (merge per ``id``)
/// - ``toolCallStarted(id:name:contentIndex:)`` — tool invocation announced; arguments not yet available
/// - ``toolCallCompleted(id:name:arguments:)`` — tool invocation finalized with complete serialized arguments
///
/// **Buffered providers** should emit ``toolCallStarted`` → ``toolCallCompleted`` (no intermediate
/// ``toolCall`` arg fragments). **Eager providers** may emit ``toolCallStarted`` → N × ``toolCall`` →
/// optional ``toolCallCompleted``.
///
/// Downstream servers can map cases trivially to discriminated streaming models (for example
/// Silenia’s `ChatStreamingPartial` / `ModelContentDeltaWire` with `kind: text | reasoning | toolCall`).
public enum PartialFragment: Sendable, Equatable {
    /// Assistant-visible output text (legacy string streams typically expose only this).
    case text(String)
    /// Extended thinking / reasoning delta when the provider exposes it separately from user-visible text.
    case reasoning(String)
    /// Eager tool-argument streaming: merge ``argumentsFragment`` values per ``id`` on the consumer side.
    case toolCall(id: String?, name: String?, argumentsFragment: String)
    /// Tool invocation announced; arguments not yet available (buffered / non-eager providers).
    case toolCallStarted(id: String?, name: String?, contentIndex: Int?)
    /// Tool invocation finalized with complete serialized arguments (JSON object string).
    case toolCallCompleted(id: String?, name: String?, arguments: String)
}
