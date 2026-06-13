//
//  ACPModels.swift
//  SwiftAgentKitACP
//

import Foundation
import EasyJSON

// MARK: - Shared types

public typealias ACPProtocolVersion = Int

public struct ACPImplementation: Codable, Sendable, Equatable {
    public var name: String
    public var title: String?
    public var version: String

    public init(name: String, title: String? = nil, version: String) {
        self.name = name
        self.title = title
        self.version = version
    }
}

public struct ACPMeta: Codable, Sendable {
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"
    }

    public init(meta: JSON? = nil) {
        self.meta = meta
    }
}

// MARK: - Capabilities

public struct ACPFilesystemCapabilities: Codable, Sendable, Equatable {
    public var readTextFile: Bool
    public var writeTextFile: Bool

    public init(readTextFile: Bool = false, writeTextFile: Bool = false) {
        self.readTextFile = readTextFile
        self.writeTextFile = writeTextFile
    }
}

public struct ACPPromptCapabilities: Codable, Sendable, Equatable {
    public var image: Bool
    public var audio: Bool
    public var embeddedContext: Bool

    public init(image: Bool = false, audio: Bool = false, embeddedContext: Bool = false) {
        self.image = image
        self.audio = audio
        self.embeddedContext = embeddedContext
    }
}

public struct ACPMcpCapabilities: Codable, Sendable, Equatable {
    public var http: Bool
    public var sse: Bool

    public init(http: Bool = false, sse: Bool = false) {
        self.http = http
        self.sse = sse
    }
}

/// Empty-object capability marker per ACP spec (`{}` means supported).
public struct ACPCapabilityMarker: Codable, Sendable {
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"
    }

    public init(meta: JSON? = nil) {
        self.meta = meta
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            meta = try container.decodeIfPresent(JSON.self, forKey: .meta)
        } else {
            meta = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(meta, forKey: .meta)
    }
}

public struct ACPSessionCapabilities: Codable, Sendable {
    public var load: ACPCapabilityMarker?
    public var list: ACPCapabilityMarker?
    public var resume: ACPCapabilityMarker?
    public var delete: ACPCapabilityMarker?
    public var close: ACPCapabilityMarker?
    public var setMode: ACPCapabilityMarker?
    public var setConfigOption: ACPCapabilityMarker?

    enum CodingKeys: String, CodingKey {
        case load, list, resume, delete, close
        case setMode = "setMode"
        case setConfigOption = "setConfigOption"
    }

    public init(
        load: ACPCapabilityMarker? = nil,
        list: ACPCapabilityMarker? = nil,
        resume: ACPCapabilityMarker? = nil,
        delete: ACPCapabilityMarker? = nil,
        close: ACPCapabilityMarker? = nil,
        setMode: ACPCapabilityMarker? = nil,
        setConfigOption: ACPCapabilityMarker? = nil
    ) {
        self.load = load
        self.list = list
        self.resume = resume
        self.delete = delete
        self.close = close
        self.setMode = setMode
        self.setConfigOption = setConfigOption
    }

    public var supportsList: Bool { list != nil }
    public var supportsResume: Bool { resume != nil }
    public var supportsDelete: Bool { delete != nil }
    public var supportsClose: Bool { close != nil }
    public var supportsSetMode: Bool { setMode != nil }
    public var supportsSetConfigOption: Bool { setConfigOption != nil }

    public static func withList() -> ACPSessionCapabilities {
        ACPSessionCapabilities(list: ACPCapabilityMarker())
    }

    public static func withResume() -> ACPSessionCapabilities {
        ACPSessionCapabilities(resume: ACPCapabilityMarker())
    }

    public static func withClose() -> ACPSessionCapabilities {
        ACPSessionCapabilities(close: ACPCapabilityMarker())
    }

    public static func withDelete() -> ACPSessionCapabilities {
        ACPSessionCapabilities(delete: ACPCapabilityMarker())
    }

    public static func fullLifecycle() -> ACPSessionCapabilities {
        ACPSessionCapabilities(
            list: ACPCapabilityMarker(),
            resume: ACPCapabilityMarker(),
            delete: ACPCapabilityMarker(),
            close: ACPCapabilityMarker()
        )
    }

    public static func == (lhs: ACPSessionCapabilities, rhs: ACPSessionCapabilities) -> Bool {
        lhs.supportsList == rhs.supportsList
            && lhs.supportsResume == rhs.supportsResume
            && lhs.supportsDelete == rhs.supportsDelete
            && lhs.supportsClose == rhs.supportsClose
            && lhs.supportsSetMode == rhs.supportsSetMode
            && lhs.supportsSetConfigOption == rhs.supportsSetConfigOption
            && (lhs.load != nil) == (rhs.load != nil)
    }
}

extension ACPSessionCapabilities: Equatable {}

public struct ACPAuthCapabilities: Codable, Sendable {
    public var logout: ACPCapabilityMarker?

    public init(logout: ACPCapabilityMarker? = nil) {
        self.logout = logout
    }

    public var supportsLogout: Bool { logout != nil }
}

extension ACPAuthCapabilities: Equatable {
    public static func == (lhs: ACPAuthCapabilities, rhs: ACPAuthCapabilities) -> Bool {
        lhs.supportsLogout == rhs.supportsLogout
    }
}

public struct ACPClientCapabilities: Codable, Sendable, Equatable {
    public var fs: ACPFilesystemCapabilities
    public var terminal: Bool

    public init(fs: ACPFilesystemCapabilities = ACPFilesystemCapabilities(), terminal: Bool = false) {
        self.fs = fs
        self.terminal = terminal
    }
}

public struct ACPAgentCapabilities: Codable, Sendable, Equatable {
    public var loadSession: Bool
    public var promptCapabilities: ACPPromptCapabilities
    public var mcpCapabilities: ACPMcpCapabilities
    public var sessionCapabilities: ACPSessionCapabilities
    public var auth: ACPAuthCapabilities

    public init(
        loadSession: Bool = false,
        promptCapabilities: ACPPromptCapabilities = ACPPromptCapabilities(),
        mcpCapabilities: ACPMcpCapabilities = ACPMcpCapabilities(),
        sessionCapabilities: ACPSessionCapabilities = ACPSessionCapabilities(),
        auth: ACPAuthCapabilities = ACPAuthCapabilities()
    ) {
        self.loadSession = loadSession
        self.promptCapabilities = promptCapabilities
        self.mcpCapabilities = mcpCapabilities
        self.sessionCapabilities = sessionCapabilities
        self.auth = auth
    }
}

public struct ACPAuthMethod: Codable, Sendable, Equatable {
    public var id: String
    public var name: String?
    public var description: String?

    public init(id: String, name: String? = nil, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }
}

// MARK: - Initialize

public struct ACPInitializeRequest: Codable, Sendable {
    public var protocolVersion: ACPProtocolVersion
    public var clientCapabilities: ACPClientCapabilities
    public var clientInfo: ACPImplementation?
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case protocolVersion, clientCapabilities, clientInfo
        case meta = "_meta"
    }

    public init(
        protocolVersion: ACPProtocolVersion = 1,
        clientCapabilities: ACPClientCapabilities = ACPClientCapabilities(),
        clientInfo: ACPImplementation? = nil,
        meta: JSON? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.clientCapabilities = clientCapabilities
        self.clientInfo = clientInfo
        self.meta = meta
    }
}

public struct ACPInitializeResponse: Codable, Sendable {
    public var protocolVersion: ACPProtocolVersion
    public var agentCapabilities: ACPAgentCapabilities
    public var agentInfo: ACPImplementation?
    public var authMethods: [ACPAuthMethod]
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case protocolVersion, agentCapabilities, agentInfo, authMethods
        case meta = "_meta"
    }

    public init(
        protocolVersion: ACPProtocolVersion = 1,
        agentCapabilities: ACPAgentCapabilities = ACPAgentCapabilities(),
        agentInfo: ACPImplementation? = nil,
        authMethods: [ACPAuthMethod] = [],
        meta: JSON? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.agentCapabilities = agentCapabilities
        self.agentInfo = agentInfo
        self.authMethods = authMethods
        self.meta = meta
    }
}

// MARK: - Authenticate

public struct ACPAuthenticateRequest: Codable, Sendable {
    public var methodId: String
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case methodId
        case meta = "_meta"
    }

    public init(methodId: String, meta: JSON? = nil) {
        self.methodId = methodId
        self.meta = meta
    }
}

public struct ACPAuthenticateResponse: Codable, Sendable {
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"
    }

    public init(meta: JSON? = nil) {
        self.meta = meta
    }
}

// MARK: - Logout

public struct ACPLogoutRequest: Codable, Sendable {
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"
    }

    public init(meta: JSON? = nil) {
        self.meta = meta
    }
}

public struct ACPLogoutResponse: Codable, Sendable {
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"
    }

    public init(meta: JSON? = nil) {
        self.meta = meta
    }
}

// MARK: - MCP server reference (session/new)

public struct ACPMcpServer: Codable, Sendable, Equatable {
    public var name: String
    public var command: String?
    public var args: [String]?
    public var env: [String: String]?

    public init(name: String, command: String? = nil, args: [String]? = nil, env: [String: String]? = nil) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
    }

    public init(name: String, command: String, arguments: [String], environment: [String: String] = [:]) {
        self.name = name
        self.command = command
        self.args = arguments
        self.env = environment.isEmpty ? nil : environment
    }
}

// MARK: - Session

public struct ACPNewSessionRequest: Codable, Sendable {
    public var cwd: String
    public var mcpServers: [ACPMcpServer]
    public var additionalRoots: [String]?
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case cwd, mcpServers, additionalRoots
        case meta = "_meta"
    }

    public init(cwd: String, mcpServers: [ACPMcpServer] = [], additionalRoots: [String]? = nil, meta: JSON? = nil) {
        self.cwd = cwd
        self.mcpServers = mcpServers
        self.additionalRoots = additionalRoots
        self.meta = meta
    }
}

public struct ACPNewSessionResponse: Codable, Sendable {
    public var sessionId: String
    public var configOptions: [ACPSessionConfigOption]?
    public var mode: ACPSessionModeState?
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case sessionId, configOptions, mode
        case meta = "_meta"
    }

    public init(sessionId: String, configOptions: [ACPSessionConfigOption]? = nil, mode: ACPSessionModeState? = nil, meta: JSON? = nil) {
        self.sessionId = sessionId
        self.configOptions = configOptions
        self.mode = mode
        self.meta = meta
    }
}

public struct ACPSessionConfigSelectOption: Codable, Sendable, Equatable {
    public var value: String
    public var name: String?
    public var description: String?

    enum CodingKeys: String, CodingKey {
        case value, name, description
    }

    public init(value: String, name: String? = nil, description: String? = nil) {
        self.value = value
        self.name = name
        self.description = description
    }
}

public struct ACPSessionConfigOption: Codable, Sendable, Equatable {
    public var id: String
    public var name: String?
    public var description: String?
    public var category: String?
    public var type: String
    public var currentValue: String
    public var options: [ACPSessionConfigSelectOption]

    public init(
        id: String,
        name: String? = nil,
        description: String? = nil,
        category: String? = nil,
        type: String = "select",
        currentValue: String,
        options: [ACPSessionConfigSelectOption]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.type = type
        self.currentValue = currentValue
        self.options = options
    }
}

public struct ACPSessionModeState: Codable, Sendable, Equatable {
    public var currentModeId: String
    public var availableModes: [ACPSessionMode]?

    public init(currentModeId: String, availableModes: [ACPSessionMode]? = nil) {
        self.currentModeId = currentModeId
        self.availableModes = availableModes
    }
}

public struct ACPSessionMode: Codable, Sendable, Equatable {
    public var id: String
    public var name: String?
    public var description: String?

    public init(id: String, name: String? = nil, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }
}

public struct ACPPromptRequest: Codable, Sendable {
    public var sessionId: String
    public var prompt: [ACPContentBlock]
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case sessionId, prompt
        case meta = "_meta"
    }

    public init(sessionId: String, prompt: [ACPContentBlock], meta: JSON? = nil) {
        self.sessionId = sessionId
        self.prompt = prompt
        self.meta = meta
    }
}

public struct ACPPromptResponse: Codable, Sendable {
    public var stopReason: ACPStopReason
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case stopReason
        case meta = "_meta"
    }

    public init(stopReason: ACPStopReason, meta: JSON? = nil) {
        self.stopReason = stopReason
        self.meta = meta
    }
}

public enum ACPStopReason: String, Codable, Sendable {
    case endTurn = "end_turn"
    case maxTokens = "max_tokens"
    case maxTurnRequests = "max_turn_requests"
    case refusal = "refusal"
    case cancelled = "cancelled"
}

public struct ACPSessionCancelParams: Codable, Sendable {
    public var sessionId: String
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case meta = "_meta"
    }

    public init(sessionId: String, meta: JSON? = nil) {
        self.sessionId = sessionId
        self.meta = meta
    }
}

public struct ACPSessionInfo: Codable, Sendable {
    public var sessionId: String
    public var cwd: String
    public var title: String?
    public var updatedAt: String?
    public var additionalDirectories: [String]?
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case sessionId, cwd, title, updatedAt, additionalDirectories
        case meta = "_meta"
    }

    public init(
        sessionId: String,
        cwd: String,
        title: String? = nil,
        updatedAt: String? = nil,
        additionalDirectories: [String]? = nil,
        meta: JSON? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.title = title
        self.updatedAt = updatedAt
        self.additionalDirectories = additionalDirectories
        self.meta = meta
    }
}

public struct ACPSessionInfoUpdate: Codable, Sendable {
    public var title: String?
    public var updatedAt: String?
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case title, updatedAt
        case meta = "_meta"
    }

    public init(title: String? = nil, updatedAt: String? = nil, meta: JSON? = nil) {
        self.title = title
        self.updatedAt = updatedAt
        self.meta = meta
    }
}

extension ACPSessionInfoUpdate: Equatable {
    public static func == (lhs: ACPSessionInfoUpdate, rhs: ACPSessionInfoUpdate) -> Bool {
        lhs.title == rhs.title && lhs.updatedAt == rhs.updatedAt
    }
}

public struct ACPListSessionsRequest: Codable, Sendable {
    public var cursor: String?
    public var cwd: String?
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case cursor, cwd
        case meta = "_meta"
    }

    public init(cursor: String? = nil, cwd: String? = nil, meta: JSON? = nil) {
        self.cursor = cursor
        self.cwd = cwd
        self.meta = meta
    }
}

public struct ACPListSessionsResponse: Codable, Sendable {
    public var sessions: [ACPSessionInfo]
    public var nextCursor: String?
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case sessions, nextCursor
        case meta = "_meta"
    }

    public init(sessions: [ACPSessionInfo], nextCursor: String? = nil, meta: JSON? = nil) {
        self.sessions = sessions
        self.nextCursor = nextCursor
        self.meta = meta
    }
}

public struct ACPLoadSessionRequest: Codable, Sendable {
    public var sessionId: String
    public var cwd: String
    public var mcpServers: [ACPMcpServer]
    public var additionalDirectories: [String]?
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case sessionId, cwd, mcpServers, additionalDirectories
        case meta = "_meta"
    }

    public init(
        sessionId: String,
        cwd: String,
        mcpServers: [ACPMcpServer] = [],
        additionalDirectories: [String]? = nil,
        meta: JSON? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.mcpServers = mcpServers
        self.additionalDirectories = additionalDirectories
        self.meta = meta
    }
}

public struct ACPLoadSessionResponse: Codable, Sendable {
    public var configOptions: [ACPSessionConfigOption]?
    public var mode: ACPSessionModeState?
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case configOptions, mode
        case meta = "_meta"
    }

    public init(configOptions: [ACPSessionConfigOption]? = nil, mode: ACPSessionModeState? = nil, meta: JSON? = nil) {
        self.configOptions = configOptions
        self.mode = mode
        self.meta = meta
    }
}

public struct ACPResumeSessionRequest: Codable, Sendable {
    public var sessionId: String
    public var cwd: String
    public var mcpServers: [ACPMcpServer]?
    public var additionalDirectories: [String]?
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case sessionId, cwd, mcpServers, additionalDirectories
        case meta = "_meta"
    }

    public init(
        sessionId: String,
        cwd: String,
        mcpServers: [ACPMcpServer]? = nil,
        additionalDirectories: [String]? = nil,
        meta: JSON? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.mcpServers = mcpServers
        self.additionalDirectories = additionalDirectories
        self.meta = meta
    }
}

public struct ACPResumeSessionResponse: Codable, Sendable {
    public var configOptions: [ACPSessionConfigOption]?
    public var mode: ACPSessionModeState?
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case configOptions, mode
        case meta = "_meta"
    }

    public init(configOptions: [ACPSessionConfigOption]? = nil, mode: ACPSessionModeState? = nil, meta: JSON? = nil) {
        self.configOptions = configOptions
        self.mode = mode
        self.meta = meta
    }
}

public struct ACPCloseSessionRequest: Codable, Sendable {
    public var sessionId: String
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case meta = "_meta"
    }

    public init(sessionId: String, meta: JSON? = nil) {
        self.sessionId = sessionId
        self.meta = meta
    }
}

public struct ACPCloseSessionResponse: Codable, Sendable {
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"
    }

    public init(meta: JSON? = nil) {
        self.meta = meta
    }
}

public struct ACPDeleteSessionRequest: Codable, Sendable {
    public var sessionId: String
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case meta = "_meta"
    }

    public init(sessionId: String, meta: JSON? = nil) {
        self.sessionId = sessionId
        self.meta = meta
    }
}

public struct ACPDeleteSessionResponse: Codable, Sendable {
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"
    }

    public init(meta: JSON? = nil) {
        self.meta = meta
    }
}

// MARK: - Session mode / config option RPC

public struct ACPSetSessionModeRequest: Codable, Sendable {
    public var sessionId: String
    public var modeId: String
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case sessionId, modeId
        case meta = "_meta"
    }

    public init(sessionId: String, modeId: String, meta: JSON? = nil) {
        self.sessionId = sessionId
        self.modeId = modeId
        self.meta = meta
    }
}

public struct ACPSetSessionModeResponse: Codable, Sendable {
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"
    }

    public init(meta: JSON? = nil) {
        self.meta = meta
    }
}

public struct ACPSetSessionConfigOptionRequest: Codable, Sendable {
    public var sessionId: String
    public var configId: String
    public var value: String
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case sessionId, configId, value
        case meta = "_meta"
    }

    public init(sessionId: String, configId: String, value: String, meta: JSON? = nil) {
        self.sessionId = sessionId
        self.configId = configId
        self.value = value
        self.meta = meta
    }
}

public struct ACPSetSessionConfigOptionResponse: Codable, Sendable {
    public var configOptions: [ACPSessionConfigOption]
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case configOptions
        case meta = "_meta"
    }

    public init(configOptions: [ACPSessionConfigOption], meta: JSON? = nil) {
        self.configOptions = configOptions
        self.meta = meta
    }
}

// MARK: - Content blocks

public enum ACPContentBlock: Codable, Sendable, Equatable {
    case text(String)
    case resource(ACPResourceContent)
    case resourceLink(ACPResourceLink)
    case image(ACPImageContent)
    case audio(ACPAudioContent)

    enum CodingKeys: String, CodingKey {
        case type, text, resource, uri, mimeType, data, name, description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "resource":
            self = .resource(try container.decode(ACPResourceContent.self, forKey: .resource))
        case "resource_link":
            self = .resourceLink(try container.decode(ACPResourceLink.self, forKey: .resource))
        case "image":
            self = .image(try ACPImageContent(from: decoder))
        case "audio":
            self = .audio(try ACPAudioContent(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content block type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .resource(let resource):
            try container.encode("resource", forKey: .type)
            try container.encode(resource, forKey: .resource)
        case .resourceLink(let link):
            try container.encode("resource_link", forKey: .type)
            try container.encode(link, forKey: .resource)
        case .image(let image):
            try container.encode("image", forKey: .type)
            try image.encode(to: encoder)
        case .audio(let audio):
            try container.encode("audio", forKey: .type)
            try audio.encode(to: encoder)
        }
    }
}

public struct ACPResourceContent: Codable, Sendable, Equatable {
    public var uri: String
    public var mimeType: String?
    public var text: String?

    public init(uri: String, mimeType: String? = nil, text: String? = nil) {
        self.uri = uri
        self.mimeType = mimeType
        self.text = text
    }
}

public struct ACPResourceLink: Codable, Sendable, Equatable {
    public var uri: String
    public var name: String?
    public var description: String?
    public var mimeType: String?

    public init(uri: String, name: String? = nil, description: String? = nil, mimeType: String? = nil) {
        self.uri = uri
        self.name = name
        self.description = description
        self.mimeType = mimeType
    }
}

public struct ACPImageContent: Codable, Sendable, Equatable {
    public var mimeType: String
    public var data: String

    public init(mimeType: String, data: String) {
        self.mimeType = mimeType
        self.data = data
    }
}

public struct ACPAudioContent: Codable, Sendable, Equatable {
    public var mimeType: String
    public var data: String

    public init(mimeType: String, data: String) {
        self.mimeType = mimeType
        self.data = data
    }
}

// MARK: - Session updates

public struct ACPSessionUpdateNotification: Codable, Sendable {
    public var sessionId: String
    public var update: ACPSessionUpdate
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case sessionId, update
        case meta = "_meta"
    }

    public init(sessionId: String, update: ACPSessionUpdate, meta: JSON? = nil) {
        self.sessionId = sessionId
        self.update = update
        self.meta = meta
    }
}

public enum ACPSessionUpdate: Codable, Sendable, Equatable {
    case agentMessageChunk(messageId: String?, content: ACPContentBlock)
    case plan(entries: [ACPPlanEntry])
    case toolCall(toolCallId: String, title: String?, kind: String?, status: String?)
    case toolCallUpdate(toolCallId: String, status: String?, content: [ACPContentBlock]?)
    case usageUpdate(used: Int, size: Int, cost: ACPUsageCost?)
    case sessionInfoUpdate(ACPSessionInfoUpdate)
    case currentModeUpdate(modeId: String)
    case configOptionUpdate(configOptions: [ACPSessionConfigOption])

    enum CodingKeys: String, CodingKey {
        case sessionUpdate, messageId, content, entries, toolCallId, title, kind, status, used, size, cost, updatedAt
        case modeId, configOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .sessionUpdate)
        switch kind {
        case "agent_message_chunk":
            self = .agentMessageChunk(
                messageId: try container.decodeIfPresent(String.self, forKey: .messageId),
                content: try container.decode(ACPContentBlock.self, forKey: .content)
            )
        case "plan":
            self = .plan(entries: try container.decode([ACPPlanEntry].self, forKey: .entries))
        case "tool_call":
            self = .toolCall(
                toolCallId: try container.decode(String.self, forKey: .toolCallId),
                title: try container.decodeIfPresent(String.self, forKey: .title),
                kind: try container.decodeIfPresent(String.self, forKey: .kind),
                status: try container.decodeIfPresent(String.self, forKey: .status)
            )
        case "tool_call_update":
            self = .toolCallUpdate(
                toolCallId: try container.decode(String.self, forKey: .toolCallId),
                status: try container.decodeIfPresent(String.self, forKey: .status),
                content: try container.decodeIfPresent([ACPContentBlock].self, forKey: .content)
            )
        case "usage_update":
            self = .usageUpdate(
                used: try container.decode(Int.self, forKey: .used),
                size: try container.decode(Int.self, forKey: .size),
                cost: try container.decodeIfPresent(ACPUsageCost.self, forKey: .cost)
            )
        case "session_info_update":
            self = .sessionInfoUpdate(try ACPSessionInfoUpdate(from: decoder))
        case "current_mode_update":
            self = .currentModeUpdate(
                modeId: try container.decode(String.self, forKey: .modeId)
            )
        case "config_option_update":
            self = .configOptionUpdate(
                configOptions: try container.decode([ACPSessionConfigOption].self, forKey: .configOptions)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .sessionUpdate, in: container, debugDescription: "Unknown session update: \(kind)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .agentMessageChunk(let messageId, let content):
            try container.encode("agent_message_chunk", forKey: .sessionUpdate)
            try container.encodeIfPresent(messageId, forKey: .messageId)
            try container.encode(content, forKey: .content)
        case .plan(let entries):
            try container.encode("plan", forKey: .sessionUpdate)
            try container.encode(entries, forKey: .entries)
        case .toolCall(let toolCallId, let title, let kind, let status):
            try container.encode("tool_call", forKey: .sessionUpdate)
            try container.encode(toolCallId, forKey: .toolCallId)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(kind, forKey: .kind)
            try container.encodeIfPresent(status, forKey: .status)
        case .toolCallUpdate(let toolCallId, let status, let content):
            try container.encode("tool_call_update", forKey: .sessionUpdate)
            try container.encode(toolCallId, forKey: .toolCallId)
            try container.encodeIfPresent(status, forKey: .status)
            try container.encodeIfPresent(content, forKey: .content)
        case .usageUpdate(let used, let size, let cost):
            try container.encode("usage_update", forKey: .sessionUpdate)
            try container.encode(used, forKey: .used)
            try container.encode(size, forKey: .size)
            try container.encodeIfPresent(cost, forKey: .cost)
        case .sessionInfoUpdate(let info):
            try container.encode("session_info_update", forKey: .sessionUpdate)
            try info.encode(to: encoder)
        case .currentModeUpdate(let modeId):
            try container.encode("current_mode_update", forKey: .sessionUpdate)
            try container.encode(modeId, forKey: .modeId)
        case .configOptionUpdate(let configOptions):
            try container.encode("config_option_update", forKey: .sessionUpdate)
            try container.encode(configOptions, forKey: .configOptions)
        }
    }
}

public struct ACPPlanEntry: Codable, Sendable, Equatable {
    public var content: String
    public var priority: String?
    public var status: String?

    public init(content: String, priority: String? = nil, status: String? = nil) {
        self.content = content
        self.priority = priority
        self.status = status
    }
}

public struct ACPUsageCost: Codable, Sendable, Equatable {
    public var amount: Double
    public var currency: String

    public init(amount: Double, currency: String) {
        self.amount = amount
        self.currency = currency
    }
}

// MARK: - Client-side methods (Agent → Client)

public struct ACPReadTextFileRequest: Codable, Sendable {
    public var path: String
    public var line: Int?
    public var limit: Int?
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case path, line, limit
        case meta = "_meta"
    }

    public init(path: String, line: Int? = nil, limit: Int? = nil, meta: JSON? = nil) {
        self.path = path
        self.line = line
        self.limit = limit
        self.meta = meta
    }
}

public struct ACPReadTextFileResponse: Codable, Sendable {
    public var content: String
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case content
        case meta = "_meta"
    }

    public init(content: String, meta: JSON? = nil) {
        self.content = content
        self.meta = meta
    }
}

public struct ACPWriteTextFileRequest: Codable, Sendable {
    public var path: String
    public var content: String
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case path, content
        case meta = "_meta"
    }

    public init(path: String, content: String, meta: JSON? = nil) {
        self.path = path
        self.content = content
        self.meta = meta
    }
}

public struct ACPWriteTextFileResponse: Codable, Sendable {
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"
    }

    public init(meta: JSON? = nil) {
        self.meta = meta
    }
}

public struct ACPRequestPermissionRequest: Codable, Sendable {
    public var sessionId: String
    public var toolCall: ACPToolCallInfo
    public var options: [ACPPermissionOption]
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case sessionId, toolCall, options
        case meta = "_meta"
    }

    public init(sessionId: String, toolCall: ACPToolCallInfo, options: [ACPPermissionOption], meta: JSON? = nil) {
        self.sessionId = sessionId
        self.toolCall = toolCall
        self.options = options
        self.meta = meta
    }
}

public struct ACPToolCallInfo: Codable, Sendable, Equatable {
    public var toolCallId: String
    public var title: String?

    public init(toolCallId: String, title: String? = nil) {
        self.toolCallId = toolCallId
        self.title = title
    }
}

public struct ACPPermissionOption: Codable, Sendable, Equatable {
    public var optionId: String
    public var name: String
    public var kind: String

    public init(optionId: String, name: String, kind: String) {
        self.optionId = optionId
        self.name = name
        self.kind = kind
    }
}

public struct ACPRequestPermissionResponse: Codable, Sendable {
    public var outcome: ACPPermissionOutcome
    public var meta: JSON?

    enum CodingKeys: String, CodingKey {
        case outcome
        case meta = "_meta"
    }

    public init(outcome: ACPPermissionOutcome, meta: JSON? = nil) {
        self.outcome = outcome
        self.meta = meta
    }
}

public enum ACPPermissionOutcome: Codable, Sendable, Equatable {
    case selected(optionId: String)
    case cancelled

    enum CodingKeys: String, CodingKey {
        case outcome, optionId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outcome = try container.decode(String.self, forKey: .outcome)
        switch outcome {
        case "selected":
            self = .selected(optionId: try container.decode(String.self, forKey: .optionId))
        case "cancelled":
            self = .cancelled
        default:
            throw DecodingError.dataCorruptedError(forKey: .outcome, in: container, debugDescription: "Unknown permission outcome: \(outcome)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .selected(let optionId):
            try container.encode("selected", forKey: .outcome)
            try container.encode(optionId, forKey: .optionId)
        case .cancelled:
            try container.encode("cancelled", forKey: .outcome)
        }
    }
}

// MARK: - Terminal stubs

public struct ACPCreateTerminalRequest: Codable, Sendable {
    public var sessionId: String
    public var command: String?
    public var args: [String]?
    public var cwd: String?
    public var env: [String: String]?

    public init(sessionId: String, command: String? = nil, args: [String]? = nil, cwd: String? = nil, env: [String: String]? = nil) {
        self.sessionId = sessionId
        self.command = command
        self.args = args
        self.cwd = cwd
        self.env = env
    }
}

public struct ACPCreateTerminalResponse: Codable, Sendable {
    public var terminalId: String

    public init(terminalId: String) {
        self.terminalId = terminalId
    }
}

public struct ACPTerminalOutputRequest: Codable, Sendable {
    public var sessionId: String
    public var terminalId: String

    public init(sessionId: String, terminalId: String) {
        self.sessionId = sessionId
        self.terminalId = terminalId
    }
}

public struct ACPTerminalOutputResponse: Codable, Sendable {
    public var output: String
    public var truncated: Bool?
    public var exitStatus: ACPTerminalExitStatus?

    public init(output: String, truncated: Bool? = nil, exitStatus: ACPTerminalExitStatus? = nil) {
        self.output = output
        self.truncated = truncated
        self.exitStatus = exitStatus
    }
}

public struct ACPTerminalExitStatus: Codable, Sendable, Equatable {
    public var exitCode: Int?
    public var signal: String?

    public init(exitCode: Int? = nil, signal: String? = nil) {
        self.exitCode = exitCode
        self.signal = signal
    }
}

public struct ACPWaitForExitRequest: Codable, Sendable {
    public var sessionId: String
    public var terminalId: String

    public init(sessionId: String, terminalId: String) {
        self.sessionId = sessionId
        self.terminalId = terminalId
    }
}

public struct ACPWaitForExitResponse: Codable, Sendable {
    public var exitStatus: ACPTerminalExitStatus

    public init(exitStatus: ACPTerminalExitStatus) {
        self.exitStatus = exitStatus
    }
}

public struct ACPKillTerminalRequest: Codable, Sendable {
    public var sessionId: String
    public var terminalId: String

    public init(sessionId: String, terminalId: String) {
        self.sessionId = sessionId
        self.terminalId = terminalId
    }
}

public struct ACPKillTerminalResponse: Codable, Sendable {
    public init() {}
}

public struct ACPReleaseTerminalRequest: Codable, Sendable {
    public var sessionId: String
    public var terminalId: String

    public init(sessionId: String, terminalId: String) {
        self.sessionId = sessionId
        self.terminalId = terminalId
    }
}

public struct ACPReleaseTerminalResponse: Codable, Sendable {
    public init() {}
}
