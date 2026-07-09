import EasyJSON
import MCP

/// Converts MCP `Value` payloads to EasyJSON `JSON` for schema preservation and tool handlers.
public enum MCPValueJSONConversion {
    public static func convert(_ value: MCP.Value) -> JSON {
        switch value {
        case .null:
            return .string("") // EasyJSON doesn't have null, use empty string
        case .bool(let bool):
            return .boolean(bool)
        case .int(let int):
            return .integer(int)
        case .double(let double):
            return .double(double)
        case .string(let string):
            return .string(string)
        case .data(_, let data):
            return .string(String(data: data, encoding: .utf8) ?? "")
        case .array(let array):
            return .array(array.map { convert($0) })
        case .object(let object):
            return .object(object.mapValues { convert($0) })
        }
    }
}
