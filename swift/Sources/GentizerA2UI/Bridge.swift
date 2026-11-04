import Gentizer

/// A2UI v1.0 callRendererFunction → runtime.invoke → rendererFunctionResponse
@MainActor
public final class A2UIBridge {
    public let runtime: AgentRuntime
    public let catalogId: String

    public init(_ runtime: AgentRuntime, catalogId: String) {
        self.runtime = runtime
        self.catalogId = catalogId
    }

    /// 현재 등록된 액션의 A2UI v1.0 catalog. 에이전트에 보낼 정의
    public func catalog() throws -> JSONValue {
        try toA2uiCatalog(runtime.manifest(), catalogId: catalogId)
    }

    /// throw 없음. 실패는 응답 error
    public func handle(_ message: A2UICallRendererFunctionMessage) async -> A2UIRendererFunctionResponseMessage {
        let body = message.callRendererFunction
        let call = body.callFunction
        func respond(_ value: JSONValue = .null, error: A2UIFunctionError? = nil) -> A2UIRendererFunctionResponseMessage {
            A2UIRendererFunctionResponseMessage(
                version: message.version,
                rendererFunctionResponse: .init(functionCallId: body.functionCallId, value: value, error: error))
        }
        func invalid(_ m: String) -> A2UIRendererFunctionResponseMessage {
            respond(error: A2UIFunctionError(code: A2UIFunctionError.invalidFunctionCall, message: m))
        }

        if let surfaceId = body.surfaceId { return invalid("Surface not found: \(surfaceId)") }
        let target = call.catalogId ?? catalogId
        guard target == catalogId else { return invalid("Catalog not found: \(target)") }
        guard message.version == "1.0" else {
            return invalid("Catalog '\(catalogId)' specification version (1.0) does not match message protocol version (\(message.version)).")
        }
        guard runtime.manifest().actions.names.contains(call.call) else { return invalid("Function not found: \(call.call)") }

        switch await runtime.invoke(call.call, args: .object(call.args ?? [:])) {
        case .success(let value):
            return respond(value)
        case .failure(let e) where e.code == .invalidArgs:
            return invalid("Invalid function arguments for '\(call.call)': \(e.message)")
        case .failure(let e):
            return respond(error: A2UIFunctionError(code: A2UIFunctionError.executionError, message: "\(e.code.rawValue): \(e.message)"))
        }
    }
}
