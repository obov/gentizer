import Gentizer

/// AG-UI tool 정의 (RunAgentInput.tools 원소)
public struct AGUITool: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var parameters: JSONValue

    public init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// AG-UI context (RunAgentInput.context 원소). value 는 JSON 문자열
public struct AGUIContext: Codable, Equatable, Sendable {
    public var description: String
    public var value: String

    public init(description: String, value: String) {
        self.description = description
        self.value = value
    }
}

public struct AGUIToolCall: Codable, Equatable, Sendable {
    public struct Function: Codable, Equatable, Sendable {
        public var name: String
        public var arguments: String

        public init(name: String, arguments: String) {
            self.name = name
            self.arguments = arguments
        }
    }

    public var id: String
    public var type: String
    public var function: Function
    /// REASONING_ENCRYPTED_VALUE (subtype tool-call)
    public var encryptedValue: String?

    public init(id: String, type: String = "function", function: Function, encryptedValue: String? = nil) {
        self.id = id
        self.type = type
        self.function = function
        self.encryptedValue = encryptedValue
    }
}

/// AG-UI 메시지. role 은 developer · system · assistant · user · tool · reasoning · activity 등 문자열 그대로.
/// JSON content 가 문자열이면 content, object 등 그 외 (activity) 면 structuredContent
public struct AGUIMessage: Codable, Equatable, Sendable {
    public var id: String
    public var role: String
    public var content: String?
    public var toolCalls: [AGUIToolCall]?
    public var toolCallId: String?
    public var error: String?
    public var activityType: String?
    public var structuredContent: JSONValue?
    public var encryptedValue: String?

    public init(id: String, role: String, content: String? = nil, toolCalls: [AGUIToolCall]? = nil,
                toolCallId: String? = nil, error: String? = nil, activityType: String? = nil,
                structuredContent: JSONValue? = nil, encryptedValue: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.error = error
        self.activityType = activityType
        self.structuredContent = structuredContent
        self.encryptedValue = encryptedValue
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, toolCalls, toolCallId, error, activityType, encryptedValue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        role = try c.decode(String.self, forKey: .role)
        switch try c.decodeIfPresent(JSONValue.self, forKey: .content) {
        case .string(let s): content = s
        case .null, nil: break
        case let other?: structuredContent = other
        }
        toolCalls = try c.decodeIfPresent([AGUIToolCall].self, forKey: .toolCalls)
        toolCallId = try c.decodeIfPresent(String.self, forKey: .toolCallId)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        activityType = try c.decodeIfPresent(String.self, forKey: .activityType)
        encryptedValue = try c.decodeIfPresent(String.self, forKey: .encryptedValue)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(role, forKey: .role)
        if let structuredContent { try c.encode(structuredContent, forKey: .content) } else { try c.encodeIfPresent(content, forKey: .content) }
        try c.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try c.encodeIfPresent(toolCallId, forKey: .toolCallId)
        try c.encodeIfPresent(error, forKey: .error)
        try c.encodeIfPresent(activityType, forKey: .activityType)
        try c.encodeIfPresent(encryptedValue, forKey: .encryptedValue)
    }
}
