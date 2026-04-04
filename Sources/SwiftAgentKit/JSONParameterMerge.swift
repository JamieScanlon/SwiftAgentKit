import Foundation
import EasyJSON

/// Shallow-merges JSON object parameters for orchestrator / LLM request layering.
///
/// - If both `base` and `override` are JSON objects, keys from `override` replace those in `base`.
/// - If only one is non-nil, that value is returned.
/// - If `override` is a non-object, it replaces `base` entirely.
public func mergeJSONObjectParameters(_ base: JSON?, _ override: JSON?) -> JSON? {
    switch (base, override) {
    case (nil, nil):
        return nil
    case (let b?, nil):
        return b
    case (nil, let o?):
        return o
    case (let .object(bd), let .object(od)):
        var merged = bd
        for (k, v) in od {
            merged[k] = v
        }
        return .object(merged)
    case (_, let o?):
        return o
    }
}
