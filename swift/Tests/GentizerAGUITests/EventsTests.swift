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

    @Test func multimodalSnapshotIsIgnored() {
        // R1: content 배열은 AGUIMessage.content String? 로 디코딩 실패 → 이벤트 무시
        let s = run([
            ["type": "MESSAGES_SNAPSHOT", "messages": [["id": "u", "role": "user", "content": [["type": "text", "text": "x"]]]]],
        ], messages: [AGUIMessage(id: "a", role: "user", content: "A")])
        #expect(s.messages.map(\.id) == ["a"])
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
        let s = run([["type": "STATE_DELTA", "delta": []], ["type": "CUSTOM", "name": "x"], ["no": "type"]])
        #expect(s.messages.isEmpty && s.state == [:])
    }
}
