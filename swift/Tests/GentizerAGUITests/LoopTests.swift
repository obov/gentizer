import Foundation
import Gentizer
import Testing
@testable import GentizerAGUI

// TS packages/ag-ui/test/loop.test.ts 와 같은 케이스

/// round 마다 script 가 낸 이벤트를 반영하는 가짜 agent
@MainActor
final class ScriptedAgent: AGUIAgent {
    private(set) var messages: [AGUIMessage] = []
    private(set) var inputs: [AGUIRunParameters] = []
    private(set) var sentMessages: [[AGUIMessage]] = []
    private let script: (Int) -> [JSONValue]

    init(_ script: @escaping (Int) -> [JSONValue]) { self.script = script }

    func runAgent(_ params: AGUIRunParameters) async throws {
        inputs.append(params)
        sentMessages.append(messages)
        var s = AGUIEventState(messages: messages, state: [:])
        for e in script(inputs.count) { s.apply(e) }
        messages = s.messages
    }

    func addMessages(_ messages: [AGUIMessage]) { self.messages += messages }
}

private func toolCall(_ id: String, _ name: String, _ args: String) -> [JSONValue] {
    [
        ["type": "TOOL_CALL_START", "toolCallId": .string(id), "toolCallName": .string(name), "parentMessageId": .string("m-\(id)")],
        ["type": "TOOL_CALL_ARGS", "toolCallId": .string(id), "delta": .string(args)],
        ["type": "TOOL_CALL_END", "toolCallId": .string(id)],
    ]
}

private func text(_ id: String, _ s: String) -> [JSONValue] {
    [
        ["type": "TEXT_MESSAGE_START", "messageId": .string(id), "role": "assistant"],
        ["type": "TEXT_MESSAGE_CONTENT", "messageId": .string(id), "delta": .string(s)],
        ["type": "TEXT_MESSAGE_END", "messageId": .string(id)],
    ]
}

@MainActor
struct LoopTests {
    @Test func toolRoundThenTextRoundEnds() async throws {
        let rt = AgentRuntime()
        try rt.action("filter_set", ActionDef(description: "필터")) { a in .string("set \(a["category"]?.stringValue ?? "")") }
        let agent = ScriptedAgent { $0 == 1 ? toolCall("t1", "filter_set", #"{"category":"shoes"}"#) : text("m2", "완료") }
        let r = try await runWithFrontendTools(agent, rt)
        #expect(r.rounds == 2)
        #expect(r.toolMessages == [AGUIMessage(id: "gentizer-t1", role: "tool", content: #""set shoes""#, toolCallId: "t1")])
        #expect(agent.messages.contains { $0.role == "tool" && $0.toolCallId == "t1" })
        #expect(agent.sentMessages[1].first { $0.role == "tool" }?.toolCallId == "t1")
        #expect(agent.inputs[0].tools.map(\.name) == ["filter_set"])
    }

    @Test func stopsAtMaxRounds() async throws {
        let rt = AgentRuntime()
        try rt.action("ping", ActionDef(description: "핑")) { _ in "pong" }
        let agent = ScriptedAgent { toolCall("t\($0)", "ping", "{}") }
        let r = try await runWithFrontendTools(agent, rt, maxRounds: 3)
        #expect(r.rounds == 3)
        #expect(r.toolMessages.count == 3)
        #expect(agent.inputs.count == 3)
    }

    @Test func recomputesToolsAndContextEachRound() async throws {
        let rt = AgentRuntime()
        var count = 0
        try rt.state("count", StateDef(description: "개수")) { .number(Double(count)) }
        try rt.action("open", ActionDef(description: "열기")) { _ in
            count += 1
            try rt.action("close", ActionDef(description: "닫기")) { _ in .null }
            return .null
        }
        let agent = ScriptedAgent { $0 == 1 ? toolCall("t1", "open", "{}") : [] }
        _ = try await runWithFrontendTools(agent, rt, AGUIRunParameters(
            tools: [AGUITool(name: "backend", description: "b", parameters: [:])],
            context: [AGUIContext(description: "extra", value: "1")]))
        #expect(agent.inputs.map { $0.tools.map(\.name) } == [["open", "backend"], ["open", "close", "backend"]])
        #expect(agent.inputs.map { $0.context.map(\.value) } == [["0", "1"], ["1", "1"]])
    }

    @Test func runErrorPropagates() async throws {
        let rt = AgentRuntime()
        final class Failing: AGUIAgent {
            var messages: [AGUIMessage] = []
            func runAgent(_ params: AGUIRunParameters) async throws { throw AGUIError.run(message: "x", code: nil) }
            func addMessages(_ messages: [AGUIMessage]) {}
        }
        await #expect(throws: AGUIError.run(message: "x", code: nil)) { try await runWithFrontendTools(Failing(), rt) }
    }
}
