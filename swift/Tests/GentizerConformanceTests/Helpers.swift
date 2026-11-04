import Foundation
@testable import Gentizer

struct BehaviorError: Error, CustomStringConvertible {
    let description: String
}

/// specs/conformance.md 'action · state 선언' behavior → 실행 함수
func behaviorRun(_ b: JSONValue?) -> ActionRun {
    { args in
        if let message = b?["throws"]?.stringValue { throw BehaviorError(description: message) }
        if b?["echoArgs"] == .bool(true) { return .object(args) }
        return b?["returns"] ?? .null
    }
}

/// confirm 모드대로 runtime 생성. 호출된 confirm 인자는 calls 에 쌓인다
@MainActor
final class ConfirmRecorder {
    var calls: [ConfirmRequest] = []

    func makeRuntime(_ mode: String?) -> AgentRuntime {
        switch mode ?? "absent" {
        case "absent":
            return AgentRuntime()
        case let mode:
            return AgentRuntime { [unowned self] req in
                self.calls.append(req)
                if mode == "throw" { throw BehaviorError(description: "confirm 실패") }
                return mode == "approve"
            }
        }
    }
}

extension ConfirmRequest {
    var json: JSONValue { ["name": .string(name), "description": .string(description), "args": .object(args)] }
}

/// runtime step register → 해제 함수
@MainActor
func register(_ rt: AgentRuntime, _ step: JSONValue) throws -> @MainActor () -> Void {
    let name = step["name"]?.stringValue ?? ""
    let def = step["def"] ?? .null
    let off: AgentUnregister
    switch step["kind"]?.stringValue {
    case "action":
        off = try rt.action(name, ActionDef(validated: def), run: behaviorRun(step["behavior"] ?? ["returns": nil]))
    case "state":
        let value = step["value"]
        off = try rt.state(name, StateDef(validated: def)) { value }
    default:
        off = try rt.view(name, ViewDef(validated: def))
    }
    return { off() }
}

/// ag-ui · a2ui suite 의 actions · states 선언 등록
@MainActor
func registerDecls(_ rt: AgentRuntime, actions: JSONValue?, states: JSONValue?) throws {
    for a in actions?.arrayValue ?? [] {
        try rt.action(a["name"]?.stringValue ?? "", ActionDef(validated: a["def"] ?? .null), run: behaviorRun(a["behavior"]))
    }
    for s in states?.arrayValue ?? [] {
        let value = s["value"]
        try rt.state(s["name"]?.stringValue ?? "", StateDef(validated: s["def"] ?? .null)) { value }
    }
}

func parseJSON(_ s: String?) -> JSONValue? {
    guard let s else { return nil }
    return try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))
}
