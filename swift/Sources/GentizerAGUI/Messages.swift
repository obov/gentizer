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

    public init(id: String, type: String = "function", function: Function) {
        self.id = id
        self.type = type
        self.function = function
    }
}

/// AG-UI 메시지. role 은 developer · system · assistant · user · tool 등 문자열 그대로
public struct AGUIMessage: Codable, Equatable, Sendable {
    public var id: String
    public var role: String
    public var content: String?
    public var toolCalls: [AGUIToolCall]?
    public var toolCallId: String?
    public var error: String?

    public init(id: String, role: String, content: String? = nil, toolCalls: [AGUIToolCall]? = nil,
                toolCallId: String? = nil, error: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.error = error
    }
}
