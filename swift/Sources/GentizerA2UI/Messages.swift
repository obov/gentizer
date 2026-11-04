import Gentizer

/// A2UI v1.0 callFunction. @call 키 (구형 call 도 읽음)
public struct A2UIFunctionCall: Codable, Equatable, Sendable {
    public var call: String
    public var catalogId: String?
    public var args: [String: JSONValue]?

    public init(call: String, catalogId: String? = nil, args: [String: JSONValue]? = nil) {
        self.call = call
        self.catalogId = catalogId
        self.args = args
    }

    private enum CodingKeys: String, CodingKey {
        case call = "@call", legacyCall = "call", catalogId, args
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let call = try c.decodeIfPresent(String.self, forKey: .call) {
            self.call = call
        } else {
            call = try c.decode(String.self, forKey: .legacyCall)
        }
        catalogId = try c.decodeIfPresent(String.self, forKey: .catalogId)
        args = try c.decodeIfPresent([String: JSONValue].self, forKey: .args)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(call, forKey: .call)
        try c.encodeIfPresent(catalogId, forKey: .catalogId)
        try c.encodeIfPresent(args, forKey: .args)
    }
}

/// { version, callRendererFunction: { functionCallId, surfaceId?, callFunction } }
public struct A2UICallRendererFunctionMessage: Codable, Equatable, Sendable {
    public struct Body: Codable, Equatable, Sendable {
        public var functionCallId: String
        public var surfaceId: String?
        public var callFunction: A2UIFunctionCall

        public init(functionCallId: String, surfaceId: String? = nil, callFunction: A2UIFunctionCall) {
            self.functionCallId = functionCallId
            self.surfaceId = surfaceId
            self.callFunction = callFunction
        }
    }

    public var version: String
    public var callRendererFunction: Body

    public init(version: String = "1.0", callRendererFunction: Body) {
        self.version = version
        self.callRendererFunction = callRendererFunction
    }
}

public struct A2UIFunctionError: Codable, Equatable, Sendable {
    public static let invalidFunctionCall = "INVALID_FUNCTION_CALL"
    public static let executionError = "EXECUTION_ERROR"

    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

/// { version, rendererFunctionResponse: { functionCallId, value | error } }. 성공은 value 키 유지 (null 포함)
public struct A2UIRendererFunctionResponseMessage: Codable, Equatable, Sendable {
    public struct Body: Codable, Equatable, Sendable {
        public var functionCallId: String
        public var value: JSONValue
        public var error: A2UIFunctionError?

        public init(functionCallId: String, value: JSONValue = .null, error: A2UIFunctionError? = nil) {
            self.functionCallId = functionCallId
            self.value = value
            self.error = error
        }

        private enum CodingKeys: String, CodingKey { case functionCallId, value, error }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            functionCallId = try c.decode(String.self, forKey: .functionCallId)
            value = try c.decodeIfPresent(JSONValue.self, forKey: .value) ?? .null
            error = try c.decodeIfPresent(A2UIFunctionError.self, forKey: .error)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(functionCallId, forKey: .functionCallId)
            if let error {
                try c.encode(error, forKey: .error)
            } else {
                try c.encode(value, forKey: .value)
            }
        }
    }

    public var version: String
    public var rendererFunctionResponse: Body

    public init(version: String, rendererFunctionResponse: Body) {
        self.version = version
        self.rendererFunctionResponse = rendererFunctionResponse
    }
}
