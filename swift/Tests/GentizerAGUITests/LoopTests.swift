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

/// script 가 throw 하는 round 가 있는 가짜 agent (RUN_ERROR 대신)
@MainActor
private final class FailingAgent: AGUIAgent {
    private(set) var messages: [AGUIMessage] = []
    private(set) var runs = 0
    private let failRound: Int

    init(failRound: Int) { self.failRound = failRound }

    func runAgent(_ params: AGUIRunParameters) async throws {
        runs += 1
        if runs == failRound { throw AGUIError.run(message: "boom", code: nil) }
    }

    func addMessages(_ messages: [AGUIMessage]) { self.messages += messages }
}

private func triggerNames(_ messages: [AGUIMessage]) -> [String] {
    messages.compactMap { m in
        guard m.role == "user", let v = parseTrigger(m.content) else { return nil }
        return v
    }
}

private func parseTrigger(_ s: String?) -> String? {
    guard let s, let v = try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) else { return nil }
    return v["gentizer_trigger"]?["name"]?.stringValue
}

private func settle() async {
    for _ in 0..<20 { await Task.yield() }
}

@MainActor
struct ConnectTriggersTests {
    @Test func queuedInOrder() async throws {
        let rt = AgentRuntime()
        let agent = ScriptedAgent { _ in [] }
        let off = connectTriggers(agent, rt)
        try rt.trigger("form_saved", payload: ["id": 1])
        try rt.trigger("page_opened")
        await settle()
        #expect(agent.sentMessages.map(triggerNames) == [["form_saved"], ["form_saved", "page_opened"]])
        off()
    }

    @Test func errorReportedAndNextContinues() async throws {
        let rt = AgentRuntime()
        let agent = FailingAgent(failRound: 1)
        var errors: [String] = []
        _ = connectTriggers(agent, rt, onError: { _, e in errors.append(e.name) })
        try rt.trigger("first")
        try rt.trigger("second")
        await settle()
        #expect(errors == ["first"])
        #expect(agent.runs == 2)
    }

    @Test func disconnectedDoesNotRun() async throws {
        let rt = AgentRuntime()
        let agent = ScriptedAgent { _ in [] }
        let off = connectTriggers(agent, rt)
        off()
        try rt.trigger("form_saved")
        await settle()
        #expect(agent.inputs.isEmpty)
    }
}
