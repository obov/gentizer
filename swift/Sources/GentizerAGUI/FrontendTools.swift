import Foundation
import Gentizer

private let emptyInput: JSONValue = ["type": "object", "properties": [:]]

/// JSON 문자열 (키 정렬). AG-UI content · context value 용
func jsonString(_ v: JSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? String(decoding: encoder.encode(v), as: UTF8.self)) ?? "null"
}

/// 액션마다 { name, description, parameters = input (생략 시 빈 object) }. 순서 = 등록 순서
public func toAGUITools(_ manifest: Manifest) -> [AGUITool] {
    manifest.actions.map { AGUITool(name: $0.name, description: $0.def.description, parameters: $0.def.input ?? emptyInput) }
}

public let viewsContextDescription = "gentizer views: 현재 화면에 표시된 영역"

/// 상태마다 { description: "<name>: <description>", value: JSON 문자열 (값 없음 = null) }.
/// 화면이 있으면 끝에 { description: viewsContextDescription, value: { <name>: <description> } }
@MainActor
public func toAGUIContext(_ runtime: AgentRuntime) -> [AGUIContext] {
    let manifest = runtime.manifest()
    var out = manifest.state.map {
        AGUIContext(description: "\($0.name): \($0.def.description)", value: jsonString(runtime.readState($0.name) ?? .null))
    }
    if manifest.views.count > 0 {
        let views = JSONValue.object(Dictionary(manifest.views.map { ($0.name, JSONValue.string($0.def.description)) },
                                                uniquingKeysWith: { first, _ in first }))
        out.append(AGUIContext(description: viewsContextDescription, value: jsonString(views)))
    }
    return out
}

/// P2 trigger → user 메시지. content 의 gentizer_trigger 키로 일반 채팅과 구분
public func toAGUITriggerMessage(_ event: TriggerEvent) -> AGUIMessage {
    let content: JSONValue = ["gentizer_trigger": ["name": .string(event.name), "payload": .object(event.payload)]]
    return AGUIMessage(id: "gentizer-trigger-\(UUID().uuidString.lowercased())", role: "user", content: jsonString(content))
}

/// 응답이 없는 · 등록된 이름의 tool call 을 순서대로 실행하고 tool 메시지를 돌려준다
@MainActor
public func runFrontendTools(_ runtime: AgentRuntime, _ messages: [AGUIMessage]) async -> [AGUIMessage] {
    let answered = Set(messages.compactMap { $0.role == "tool" ? $0.toolCallId : nil })
    let registered = Set(runtime.manifest().actions.names)
    var out: [AGUIMessage] = []
    for message in messages where message.role == "assistant" {
        for call in message.toolCalls ?? [] where !answered.contains(call.id) && registered.contains(call.function.name) {
            let result: InvokeResult
            if let args = parseArguments(call.function.arguments) {
                result = await runtime.invoke(call.function.name, args: args)
            } else {
                result = .failure(InvokeError(code: .invalidArgs, message: "arguments 는 JSON object"))
            }
            out.append(toolMessage(call.id, result))
        }
    }
    return out
}

/// "" = {}. 파싱 실패 · object 아님 = nil
private func parseArguments(_ s: String) -> JSONValue? {
    if s.isEmpty { return .object([:]) }
    guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)), v.objectValue != nil else { return nil }
    return v
}

private func toolMessage(_ toolCallId: String, _ r: InvokeResult) -> AGUIMessage {
    let id = "gentizer-\(toolCallId)"
    switch r {
    case .success(let value):
        return AGUIMessage(id: id, role: "tool", content: jsonString(value), toolCallId: toolCallId)
    case .failure(let e):
        let content: JSONValue = ["error": ["code": .string(e.code.rawValue), "message": .string(e.message)]]
        return AGUIMessage(id: id, role: "tool", content: jsonString(content), toolCallId: toolCallId,
                           error: "\(e.code.rawValue): \(e.message)")
    }
}
