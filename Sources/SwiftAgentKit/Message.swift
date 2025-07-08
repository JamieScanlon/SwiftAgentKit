import Foundation

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
    public var responseFormat: String?
    
    public init(id: UUID, role: MessageRole, content: String, timestamp: Date = Date(), images: [Image] = [], toolCalls: [String] = [], responseFormat: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.images = images
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
            "images": images.map{ $0.toJSON(includeImageData: includeImageData, includeThumbData: includeThumbData) },
            "responseFormat": responseFormat ?? "",
        ]
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
        
        let responseFormat = json["responseFormat"] as? String
        
        return Message(id: id, role: role, content: content, timestamp: timestamp, images: images, toolCalls: toolCalls, responseFormat: responseFormat)
    }
}
