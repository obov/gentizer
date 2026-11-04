import Foundation
import Gentizer
import Testing
@testable import GentizerAGUI

// specs/ag-ui.md 'Swift' SSE · 이벤트 반영

struct SSEParserTests {
    private func parse(_ s: String) -> [String] {
        var p = SSEParser()
        var out = Array(s.utf8).compactMap { p.feed($0) }
        if let last = p.finish() { out.append(last) }
        return out
    }

    @Test func splitsOnBlankLine() {
        #expect(parse("data: {\"a\":1}\n\ndata: {\"b\":2}\n\n") == [#"{"a":1}"#, #"{"b":2}"#])
    }

    @Test func crlfAndMultipleDataLines() {
        #expect(parse("data: a\r\ndata:b\r\n\r\n") == ["a\nb"])
    }

    @Test func ignoresCommentsAndOtherFields() {
        #expect(parse(": ping\nevent: x\nid: 1\ndata: v\n\n: only comment\n\n") == ["v"])
    }

    @Test func flushesLastEventWithoutBlankLine() {
        #expect(parse("data: end") == ["end"])
    }

    @Test func multibyteSplitAcrossFeeds() {
        #expect(parse("data: 안녕\n\n") == ["안녕"])
    }
}

struct EventStateTests {
    private func run(_ events: [JSONValue], messages: [AGUIMessage] = []) -> AGUIEventState {
        var s = AGUIEventState(messages: messages, state: [:])
        for e in events { s.apply(e) }
        return s
    }

    @Test func textMessage() {
        let s = run([
            ["type": "TEXT_MESSAGE_START", "messageId": "m1", "role": "assistant"],
            ["type": "TEXT_MESSAGE_CONTENT", "messageId": "m1", "delta": "안"],
            ["type": "TEXT_MESSAGE_CONTENT", "messageId": "m1", "delta": "녕"],
            ["type": "TEXT_MESSAGE_CONTENT", "messageId": "none", "delta": "x"],
            ["type": "TEXT_MESSAGE_END", "messageId": "m1"],
        ])
        #expect(s.messages == [AGUIMessage(id: "m1", role: "assistant", content: "안녕")])
    }

    @Test func textChunkUsesPreviousId() {
        let s = run([
            ["type": "TEXT_MESSAGE_CHUNK", "messageId": "m1", "delta": "a"],
            ["type": "TEXT_MESSAGE_CHUNK", "delta": "b"],
        ])
        #expect(s.messages == [AGUIMessage(id: "m1", role: "assistant", content: "ab")])
    }

    @Test func toolCallAttachesToParentAssistant() {
        let s = run([
            ["type": "TEXT_MESSAGE_START", "messageId": "m1"],
            ["type": "TOOL_CALL_START", "toolCallId": "t1", "toolCallName": "cart_add", "parentMessageId": "m1"],
            ["type": "TOOL_CALL_ARGS", "toolCallId": "t1", "delta": "{\"id\":"],
            ["type": "TOOL_CALL_ARGS", "toolCallId": "t1", "delta": "1}"],
            ["type": "TOOL_CALL_END", "toolCallId": "t1"],
        ])
        #expect(s.messages.count == 1)
        #expect(s.messages[0].toolCalls == [AGUIToolCall(id: "t1", function: .init(name: "cart_add", arguments: #"{"id":1}"#))])
    }

    @Test func toolCallParentMissingOrNotAssistant() {
        let s = run([
            ["type": "TOOL_CALL_START", "toolCallId": "t1", "toolCallName": "a", "parentMessageId": "p1"],
            ["type": "TOOL_CALL_START", "toolCallId": "t2", "toolCallName": "b"],
            ["type": "TOOL_CALL_START", "toolCallId": "t3", "toolCallName": "c", "parentMessageId": "u1"],
        ], messages: [AGUIMessage(id: "u1", role: "user", content: "hi")])
        #expect(s.messages.map(\.id) == ["u1", "p1", "t2", "t3"])
        #expect(s.messages[3].toolCalls?.first?.function.name == "c")
    }

    @Test func toolCallStartSameIdUpdatesName() {
        let s = run([
            ["type": "TOOL_CALL_START", "toolCallId": "t1", "toolCallName": "a"],
            ["type": "TOOL_CALL_START", "toolCallId": "t1", "toolCallName": "b"],
        ])
        #expect(s.messages.count == 1)
        #expect(s.messages[0].toolCalls?.map(\.function.name) == ["b"])
    }

    @Test func toolCallChunk() {
        let s = run([
            ["type": "TOOL_CALL_CHUNK", "toolCallId": "t1", "toolCallName": "a", "parentMessageId": "m1", "delta": "{"],
            ["type": "TOOL_CALL_CHUNK", "delta": "}"],
        ])
        #expect(s.messages == [AGUIMessage(id: "m1", role: "assistant",
                                           toolCalls: [AGUIToolCall(id: "t1", function: .init(name: "a", arguments: "{}"))])])
    }

    @Test func toolResultInsertedAfterAssistantAndTools() {
        let call = { (id: String) in AGUIToolCall(id: id, function: .init(name: "x", arguments: "{}")) }
        let base = [
            AGUIMessage(id: "a1", role: "assistant", toolCalls: [call("t1"), call("t2")]),
            AGUIMessage(id: "r1", role: "tool", content: "1", toolCallId: "t1"),
            AGUIMessage(id: "u1", role: "user", content: "next"),
        ]
        let s = run([
            ["type": "TOOL_CALL_RESULT", "messageId": "r2", "toolCallId": "t2", "content": "2"],
            ["type": "TOOL_CALL_RESULT", "messageId": "r1", "toolCallId": "t1", "content": "1b"],
            ["type": "TOOL_CALL_RESULT", "messageId": "r9", "toolCallId": "t9", "content": "9"],
        ], messages: base)
        #expect(s.messages.map(\.id) == ["a1", "r1", "r2", "u1", "r9"])
        #expect(s.messages[1].content == "1b")
    }

    @Test func messagesSnapshotReplacesAndAppends() {
        let s = run([
            ["type": "MESSAGES_SNAPSHOT", "messages": [
                ["id": "b", "role": "assistant", "content": "B2"],
                ["id": "c", "role": "user", "content": "C"],
            ]],
        ], messages: [
            AGUIMessage(id: "a", role: "user", content: "A"),
            AGUIMessage(id: "b", role: "assistant", content: "B"),
        ])
        #expect(s.messages == [AGUIMessage(id: "b", role: "assistant", content: "B2"),
                               AGUIMessage(id: "c", role: "user", content: "C")])
    }

    @Test func multimodalSnapshotKeepsStructuredContent() {
        // content 배열 (multimodal) 은 structuredContent 로 보존
        let s = run([
            ["type": "MESSAGES_SNAPSHOT", "messages": [["id": "u", "role": "user", "content": [["type": "text", "text": "x"]]]]],
        ], messages: [AGUIMessage(id: "a", role: "user", content: "A")])
        #expect(s.messages == [AGUIMessage(id: "u", role: "user", structuredContent: [["type": "text", "text": "x"]])])
    }

    @Test func stateSnapshotAndRunError() {
        var s = run([
            ["type": "STATE_SNAPSHOT", "snapshot": ["n": 1]],
            ["type": "RUN_ERROR", "message": "boom", "code": "E1"],
            ["type": "TEXT_MESSAGE_START", "messageId": "after"],
        ])
        #expect(s.state == ["n": 1])
        #expect(s.runError == .run(message: "boom", code: "E1"))
        #expect(s.messages.isEmpty)
        s.apply(data: "not json")
        #expect(s.messages.isEmpty)
    }

    @Test func unknownTypeIgnored() {
        let s = run([["type": "SUBAGENT_STARTED"], ["type": "CUSTOM", "name": "x"], ["no": "type"]])
        #expect(s.messages.isEmpty && s.state == [:])
    }

    private func state(_ initial: JSONValue, _ delta: JSONValue) -> JSONValue {
        var s = AGUIEventState(messages: [], state: initial)
        s.apply(["type": "STATE_DELTA", "delta": delta])
        return s.state
    }

    @Test func stateDeltaOps() {
        let doc: JSONValue = ["a": 1, "list": [1, 2], "o": ["x": "y"]]
        #expect(state(doc, [["op": "add", "path": "/b", "value": 2]]) == ["a": 1, "b": 2, "list": [1, 2], "o": ["x": "y"]])
        #expect(state(doc, [["op": "add", "path": "/list/-", "value": 3]])["list"] == [1, 2, 3])
        #expect(state(doc, [["op": "add", "path": "/list/0", "value": 0]])["list"] == [0, 1, 2])
        #expect(state(doc, [["op": "remove", "path": "/o/x"]])["o"] == [:])
        #expect(state(doc, [["op": "replace", "path": "/a", "value": "z"]])["a"] == "z")
        #expect(state(doc, [["op": "move", "from": "/a", "path": "/o/a"]]) == ["list": [1, 2], "o": ["x": "y", "a": 1]])
        #expect(state(doc, [["op": "copy", "from": "/list", "path": "/c"]])["c"] == [1, 2])
        #expect(state(doc, [["op": "replace", "path": "", "value": ["n": 1]]]) == ["n": 1])
        #expect(state(["a~b": ["c/d": 1]], [["op": "replace", "path": "/a~0b/c~1d", "value": 2]]) == ["a~b": ["c/d": 2]])
    }

    @Test func stateDeltaFailureKeepsState() {
        let doc: JSONValue = ["a": 1]
        #expect(state(doc, [["op": "add", "path": "/b", "value": 2], ["op": "test", "path": "/a", "value": 9]]) == doc)
        #expect(state(doc, [["op": "remove", "path": "/missing"]]) == doc)
        #expect(state(doc, [["op": "replace", "path": "/missing", "value": 1]]) == doc)
        #expect(state(doc, [["op": "add", "path": "/x/y", "value": 1]]) == doc)
        #expect(state(doc, [["op": "nope", "path": "/a"]]) == doc)
        #expect(state(doc, [["op": "test", "path": "/a", "value": 1]]) == doc)
    }

    @Test func reasoningMessages() {
        let s = run([
            ["type": "REASONING_START", "messageId": "r"],
            ["type": "REASONING_MESSAGE_START", "messageId": "r1", "role": "reasoning"],
            ["type": "REASONING_MESSAGE_CONTENT", "messageId": "r1", "delta": "생"],
            ["type": "REASONING_MESSAGE_CONTENT", "messageId": "r1", "delta": "각"],
            ["type": "REASONING_MESSAGE_CONTENT", "messageId": "none", "delta": "x"],
            ["type": "REASONING_MESSAGE_END", "messageId": "r1"],
            ["type": "REASONING_MESSAGE_CHUNK", "messageId": "r2", "delta": "a"],
            ["type": "REASONING_MESSAGE_CHUNK", "delta": "b"],
            ["type": "REASONING_END", "messageId": "r"],
        ])
        #expect(s.messages == [AGUIMessage(id: "r1", role: "reasoning", content: "생각"),
                               AGUIMessage(id: "r2", role: "reasoning", content: "ab")])
    }

    @Test func encryptedValue() {
        let s = run([
            ["type": "TOOL_CALL_START", "toolCallId": "t1", "toolCallName": "x", "parentMessageId": "a1"],
            ["type": "REASONING_MESSAGE_START", "messageId": "r1", "role": "reasoning"],
            ["type": "REASONING_ENCRYPTED_VALUE", "subtype": "tool-call", "entityId": "t1", "encryptedValue": "E1"],
            ["type": "REASONING_ENCRYPTED_VALUE", "subtype": "message", "entityId": "r1", "encryptedValue": "E2"],
        ])
        #expect(s.messages[0].toolCalls?[0].encryptedValue == "E1")
        #expect(s.messages[1].encryptedValue == "E2")
    }

    @Test func activitySnapshotAndDelta() {
        var s = run([
            ["type": "ACTIVITY_SNAPSHOT", "messageId": "p1", "activityType": "PLAN", "content": ["steps": ["a"]]],
            ["type": "ACTIVITY_DELTA", "messageId": "p1", "activityType": "PLAN", "patch": [["op": "add", "path": "/steps/-", "value": "b"]]],
            ["type": "ACTIVITY_DELTA", "messageId": "p1", "activityType": "PLAN", "patch": [["op": "remove", "path": "/none"]]],
            ["type": "ACTIVITY_DELTA", "messageId": "none", "activityType": "PLAN", "patch": []],
        ])
        #expect(s.messages == [AGUIMessage(id: "p1", role: "activity", activityType: "PLAN", structuredContent: ["steps": ["a", "b"]])])
        s.apply(["type": "ACTIVITY_SNAPSHOT", "messageId": "p1", "activityType": "PLAN", "content": ["steps": []], "replace": false])
        #expect(s.messages[0].structuredContent == ["steps": ["a", "b"]])
        s.apply(["type": "ACTIVITY_SNAPSHOT", "messageId": "p1", "activityType": "PLAN2", "content": ["steps": []]])
        #expect(s.messages[0].activityType == "PLAN2" && s.messages[0].structuredContent == ["steps": []])
    }

    @Test func activitySnapshotReplacesNonActivity() {
        let s = run([["type": "ACTIVITY_SNAPSHOT", "messageId": "m1", "activityType": "A", "content": [:]]],
                    messages: [AGUIMessage(id: "m1", role: "assistant", content: "x")])
        #expect(s.messages == [AGUIMessage(id: "m1", role: "activity", activityType: "A", structuredContent: [:])])
    }

    @Test func snapshotKeepsActivityAndReasoningWhenAbsent() {
        let old = [AGUIMessage(id: "u1", role: "user", content: "a"),
                   AGUIMessage(id: "p1", role: "activity", activityType: "A", structuredContent: [:]),
                   AGUIMessage(id: "r1", role: "reasoning", content: "t")]
        let kept = run([["type": "MESSAGES_SNAPSHOT", "messages": [["id": "u2", "role": "user", "content": "b"]]]], messages: old)
        #expect(kept.messages.map(\.id) == ["p1", "r1", "u2"])
        let replaced = run([["type": "MESSAGES_SNAPSHOT", "messages": [
            ["id": "p2", "role": "activity", "activityType": "A", "content": [:]],
            ["id": "r2", "role": "reasoning", "content": "u"],
        ]]], messages: old)
        #expect(replaced.messages.map(\.id) == ["p2", "r2"])
    }
}
