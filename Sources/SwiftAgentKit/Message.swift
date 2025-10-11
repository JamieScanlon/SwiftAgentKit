import Foundation
import EasyJSON

public enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

// TODO: Support images, audio, resources
public struct Message: Identifiable, Codable, Equatable, Sendable {
    
    public struct Image: Codable, Equatable, Sendable {
        /// `name` must be unique
        public var name: String
        public var path: String?
        public var imageData: Data?
        public var base64EncodedImage: String? {
            return imageData?.base64EncodedString()
        }
        public var thumbData: Data?
        public var base64EncodedThumb: String? {
            return thumbData?.base64EncodedString()
        }
        public init(name: String, path: String? = nil, imageData: Data? = nil, thumbData: Data? = nil) {
            self.name = name
            self.path = path
            self.imageData = imageData
            self.thumbData = thumbData
        }
        public init(from: [String: Sendable]) {
            if let aName = from["name"] as? String {
                self.name = aName
            } else {
                print("WARNING: Image name not provided, generating UUID")
                self.name = UUID().uuidString
            }
            self.path = from["path"] as? String
            if let base64String = from["imageData"] as? String {
                self.imageData = Data(base64Encoded: base64String)
            } else {
                self.imageData = nil
            }
            if let base64String = from["thumbData"] as? String {
                self.thumbData = Data(base64Encoded: base64String)
            } else {
                self.thumbData = nil
            }
        }
        
        public init(from json: JSON) {
            guard case .object(let dict) = json else {
                print("WARNING: Invalid JSON format, generating UUID")
                self.name = UUID().uuidString
                self.path = nil
                self.imageData = nil
                self.thumbData = nil
                return
            }
            
            if case .string(let aName) = dict["name"] {
                self.name = aName
            } else {
                print("WARNING: Image name not provided, generating UUID")
                self.name = UUID().uuidString
            }
            
            if case .string(let pathStr) = dict["path"] {
                self.path = pathStr
            } else {
                self.path = nil
            }
            
            if case .string(let base64String) = dict["imageData"] {
                self.imageData = Data(base64Encoded: base64String)
            } else {
                self.imageData = nil
            }
            
            if case .string(let base64String) = dict["thumbData"] {
                self.thumbData = Data(base64Encoded: base64String)
            } else {
                self.thumbData = nil
            }
        }
        public func toJSON(includeImageData: Bool = false, includeThumbData: Bool = true) -> [String: Sendable] {
            var returnValue = [String: Sendable]()
            returnValue["name"] = name
            if let path = path {
                returnValue["path"] = path
            }
            if let base64EncodedImage, includeImageData {
                returnValue["imageData"] = base64EncodedImage
            }
            if let base64EncodedThumb, includeThumbData {
                returnValue["thumbData"] = base64EncodedThumb
            }
            return returnValue
        }
        
        public func toEasyJSON(includeImageData: Bool = false, includeThumbData: Bool = true) -> JSON {
            var dict: [String: JSON] = [:]
            dict["name"] = .string(name)
            if let path = path {
                dict["path"] = .string(path)
            }
            if let base64EncodedImage, includeImageData {
                dict["imageData"] = .string(base64EncodedImage)
            }
            if let base64EncodedThumb, includeThumbData {
                dict["thumbData"] = .string(base64EncodedThumb)
            }
            return .object(dict)
        }
    }
    
    
    public var id: UUID
    public var role: MessageRole
    public var content: String
    public var isUser: Bool {
        role == .user
    }
    public var timestamp: Date = Date()
    public var images: [Image] = []
    /// a list of tools in JSON that the model wants to use
    public var toolCalls: [String] = []
    /// When this message is a response to a tool call, this id represents the id of the original tool call
    public var toolCallId: String?
    public var responseFormat: String?
    
    public init(id: UUID, role: MessageRole, content: String, timestamp: Date = Date(), images: [Image] = [], toolCalls: [String] = [], toolCallId: String? = nil, responseFormat: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.images = images
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.responseFormat = responseFormat
    }
    
    public func toJSON(includeImageData: Bool = false, includeThumbData: Bool = true) -> [String: Sendable] {
        let formatter = ISO8601DateFormatter()
        return [
            "id": id.uuidString,
            "role": role.rawValue,
            "content": content,
            "timestamp": formatter.string(from: timestamp),
            "toolCalls": toolCalls,
            "toolCallId": toolCallId,
            "images": images.map{ $0.toJSON(includeImageData: includeImageData, includeThumbData: includeThumbData) },
            "responseFormat": responseFormat ?? "",
        ]
    }
    
    public func toEasyJSON(includeImageData: Bool = false, includeThumbData: Bool = true) -> JSON {
        let formatter = ISO8601DateFormatter()
        var dict: [String: JSON] = [:]
        dict["id"] = .string(id.uuidString)
        dict["role"] = .string(role.rawValue)
        dict["content"] = .string(content)
        dict["timestamp"] = .string(formatter.string(from: timestamp))
        dict["toolCalls"] = .array(toolCalls.map { .string($0) })
        if let toolCallId { dict["toolCallId"] = .string(toolCallId) }
        dict["images"] = .array(images.map { $0.toEasyJSON(includeImageData: includeImageData, includeThumbData: includeThumbData) })
        dict["responseFormat"] = .string(responseFormat ?? "")
        return .object(dict)
    }
    
    public static func fromJSON(_ json: [String: Any]) -> Message? {
        let formatter = ISO8601DateFormatter()
        guard let idString = json["id"] as? String,
              let id = UUID(uuidString: idString),
              let roleString = json["role"] as? String,
              let role = MessageRole(rawValue: roleString),
              let content = json["content"] as? String,
              let timeStampSting = json["timestamp"] as? String,
              let timestamp = formatter.date(from: timeStampSting) else {
            return nil
        }
        
        let images: [Image] = {
            var returnValue = [Image]()
            if let imagesJSON = json["images"] as? [[String: Sendable]] {
                for imgJSON in imagesJSON {
                    returnValue.append(Image(from: imgJSON))
                }
            }
            return returnValue
        }()
        
        let toolCalls: [String] = {
            if let toolCallsArray = json["toolCalls"] as? [String] {
                return toolCallsArray
            } else {
                return []
            }
        }()
        
        let toolCallId = json["toolCallId"] as? String
        let responseFormat = json["responseFormat"] as? String
        
        return Message(id: id, role: role, content: content, timestamp: timestamp, images: images, toolCalls: toolCalls, toolCallId: toolCallId, responseFormat: responseFormat)
    }
    
    public static func fromEasyJSON(_ json: JSON) -> Message? {
        let formatter = ISO8601DateFormatter()
        
        guard case .object(let dict) = json else {
            return nil
        }
        
        guard case .string(let idString) = dict["id"],
              let id = UUID(uuidString: idString),
              case .string(let roleString) = dict["role"],
              let role = MessageRole(rawValue: roleString),
              case .string(let content) = dict["content"],
              case .string(let timestampString) = dict["timestamp"],
              let timestamp = formatter.date(from: timestampString) else {
            return nil
        }
        
        let images: [Image] = {
            var returnValue = [Image]()
            if case .array(let imagesArray) = dict["images"] {
                for imageJSON in imagesArray {
                    returnValue.append(Image(from: imageJSON))
                }
            }
            return returnValue
        }()
        
        let toolCalls: [String] = {
            if case .array(let toolCallsArray) = dict["toolCalls"] {
                return toolCallsArray.compactMap { jsonValue in
                    if case .string(let str) = jsonValue {
                        return str
                    }
                    return nil
                }
            } else {
                return []
            }
        }()
        
        let toolCallId: String? = {
            if case .string(let format) = dict["toolCallId"], !format.isEmpty {
                return format
            }
            return nil
        }()
        
        let responseFormat: String? = {
            if case .string(let format) = dict["responseFormat"], !format.isEmpty {
                return format
            }
            return nil
        }()
        
        return Message(id: id, role: role, content: content, timestamp: timestamp, images: images, toolCalls: toolCalls, toolCallId: toolCallId, responseFormat: responseFormat)
    }
}
