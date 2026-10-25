import Foundation
import MCP
import SwiftAgentKit

extension Array where Element == Tool.Content {

    /// Typed tool-result parts for these `tools/call` contents, in order.
    ///
    /// - `.text` becomes a text part.
    /// - `.image` becomes an image part with base64-decoded bytes, its MIME type, and `width` / `height` from `_meta` when present.
    /// - An embedded `.resource` with an `image/*` MIME type and a `blob` becomes an image part.
    ///
    /// Audio, non-image resources, and resource links are not represented and are skipped.
    /// Image payloads that are not valid base64 are dropped rather than surfaced as text.
    public var toolResultParts: [ToolResultContentPart] {
        compactMap { content in
            switch content {
            case .text(let text, _, _):
                return .text(text)
            case .image(let base64, let mimeType, _, let meta):
                guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
                return .image(ToolResultImage(
                    data: data,
                    mediaType: mimeType,
                    width: meta?["width"]?.mcpDimension,
                    height: meta?["height"]?.mcpDimension
                ))
            case .resource(let resource, _, let meta):
                guard let mimeType = resource.mimeType,
                      mimeType.lowercased().hasPrefix("image/"),
                      let blob = resource.blob,
                      let data = Data(base64Encoded: blob, options: .ignoreUnknownCharacters) else { return nil }
                return .image(ToolResultImage(
                    data: data,
                    mediaType: mimeType,
                    width: (meta?["width"] ?? resource._meta?["width"])?.mcpDimension,
                    height: (meta?["height"] ?? resource._meta?["height"])?.mcpDimension
                ))
            default:
                return nil
            }
        }
    }
}

private extension Value {
    var mcpDimension: Int? {
        intValue ?? stringValue.flatMap(Int.init)
    }
}
