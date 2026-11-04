import Foundation
import Gentizer
import Testing
@testable import GentizerAGUI

// 규칙은 conformance/ag-ui. 여기는 Swift 고유 (AG-UI JSON 디코딩 · 직렬화 형태)

struct MessagesTests {
    @Test func decodesAgUiMessages() throws {
        let json = #"""
        [{"id":"a1","role":"assistant","toolCalls":[{"id":"t1","type":"function","function":{"name":"cart_add","arguments":"{}"}}]},
         {"id":"r1","role":"tool","toolCallId":"t1","content":"1"},
         {"id":"u1","role":"user","content":"안녕"}]
        """#
        let messages = try JSONDecoder().decode([AGUIMessage].self, from: Data(json.utf8))
        #expect(messages[0].toolCalls?.first?.function.name == "cart_add")
        #expect(messages[1].toolCallId == "t1")
        #expect(messages[2].content == "안녕")
    }

    @Test func structuredContentRoundTrip() throws {
        let json = #"[{"id":"p1","role":"activity","activityType":"PLAN","content":{"steps":["a"]}},{"id":"r1","role":"reasoning","content":"t","encryptedValue":"E"}]"#
        let messages = try JSONDecoder().decode([AGUIMessage].self, from: Data(json.utf8))
        #expect(messages[0].structuredContent == ["steps": ["a"]] && messages[0].content == nil && messages[0].activityType == "PLAN")
        #expect(messages[1].content == "t" && messages[1].encryptedValue == "E")
        let back = try JSONValue(encoding: messages)
        #expect(back == (try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))))
    }

    @Test func integersSerializeWithoutFraction() {
        #expect(jsonString([1, 1.5, "a/b"]) == #"[1,1.5,"a/b"]"#)
        #expect(jsonString(["b": 1, "a": nil]) == #"{"a":null,"b":1}"#)
    }

    @Test @MainActor func contextUsesNullForMissingValue() throws {
        let rt = AgentRuntime()
        try rt.state("empty", StateDef(description: "없음")) { nil }
        #expect(toAGUIContext(rt) == [AGUIContext(description: "empty: 없음", value: "null")])
    }
}
