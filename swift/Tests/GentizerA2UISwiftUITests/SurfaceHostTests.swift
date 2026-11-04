import Foundation
import Gentizer
import Testing
@testable import GentizerA2UISwiftUI

// TS packages/a2ui/test/surface-host.test.ts 와 같은 케이스 (A2UI Swift 가 내는 메시지 형태 기준)

@MainActor
final class Sent {
    var messages: [GentizerJSONValue] = []
}

@MainActor
struct SurfaceHostTests {
    private let basic = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"

    private func host(_ rt: AgentRuntime = AgentRuntime(), stateSync: Bool = true,
                      triggerSurfaceId: String = "gentizer") throws -> (A2UISurfaceHost, Sent) {
        if rt.manifest().actions.count == 0 {
            try rt.action("ping", ActionDef(description: "핑")) { _ in "pong" }
        }
        let sent = Sent()
        let h = A2UISurfaceHost(rt, catalogId: "cat", stateSync: stateSync, triggerSurfaceId: triggerSurfaceId) {
            sent.messages.append($0)
        }
        return (h, sent)
    }

    private func json(_ s: String) throws -> GentizerJSONValue {
        try JSONDecoder().decode(GentizerJSONValue.self, from: Data(s.utf8))
    }

    private func create(_ h: A2UISurfaceHost, _ id: String = "s1", sendDataModel: Bool = false) async throws {
        await h.process(message: try json(#"{"version":"1.0","createSurface":{"surfaceId":"\#(id)","catalogId":"\#(basic)","sendDataModel":\#(sendDataModel)}}"#))
        await h.process(message: try json(#"{"version":"1.0","updateComponents":{"surfaceId":"\#(id)","components":[{"id":"root","component":"Button","child":"t","action":{"event":{"name":"buy","context":{"id":2}}}},{"id":"t","component":"Text","text":"담기"}]}}"#))
    }

    /// outboundListener 는 Task 로 메인 액터에 넘긴다
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func createAndUpdateActivatesSurface() async throws {
        let (h, _) = try host()
        try await create(h)
        #expect(h.surfaceIDs == ["s1"])
        #expect(h.surface("s1")?.rootNode?.type == "Button")
    }

    @Test func deleteDeactivates() async throws {
        let (h, _) = try host()
        try await create(h)
        await h.process(message: try json(#"{"version":"1.0","deleteSurface":{"surfaceId":"s1"}}"#))
        #expect(h.surfaceIDs.isEmpty)
        #expect(h.surface("s1") == nil)
    }

    @Test func surfaceCallResponseIsSent() async throws {
        let (h, sent) = try host()
        let call = #"{"version":"1.0","callRendererFunction":{"functionCallId":"c1","surfaceId":"s1","callFunction":{"@call":"ping"}}}"#
        await h.process(message: try json(call))
        #expect(sent.messages.last?["rendererFunctionResponse"]?["error"]?["message"] == "Surface not found: s1")
        try await create(h)
        await h.process(message: try json(call))
        #expect(sent.messages.last == ["version": "1.0", "rendererFunctionResponse": ["functionCallId": "c1", "value": "pong"]])
    }

    @Test func invalidMessageSendsError() async throws {
        let (h, sent) = try host()
        await h.process(message: "garbage")
        await h.process(message: try json(#"{"version":"1.0","createSurface":{"surfaceId":"x","catalogId":"nope"}}"#))
        await settle()
        #expect(sent.messages.count == 2)
        #expect(sent.messages.allSatisfy { $0["error"]?["code"]?.stringValue != nil })
    }

    @Test func componentActionIsSent() async throws {
        let (h, sent) = try host()
        try await create(h)
        let action = try #require(h.surface("s1")?.rootNode?.action(for: "action"))
        action()
        await settle()
        let a = try #require(sent.messages.last?["action"])
        #expect(a["name"] == "buy" && a["surfaceId"] == "s1" && a["sourceComponentId"] == "root" && a["context"] == ["id": 2])
    }

    @Test func triggerSendsAction() async throws {
        let rt = AgentRuntime()
        let (h, sent) = try host(rt, triggerSurfaceId: "app")
        defer { withExtendedLifetime(h) {} }
        try rt.trigger("form_saved", payload: ["id": 7])
        let a = try #require(sent.messages.last?["action"])
        #expect(a["name"] == "form_saved" && a["surfaceId"] == "app" && a["sourceComponentId"] == "gentizer" && a["context"] == ["id": 7])
        #expect(a["timestamp"]?.stringValue.flatMap { ISO8601DateFormatter.fraction.date(from: $0) } != nil)
    }

    @Test func callAgentFunctionResolvesAndRejects() async throws {
        let (h, sent) = try host()
        try await create(h)
        async let value = h.callAgentFunction(surfaceID: "s1", name: "lookup", args: ["q": 1])
        await settle()
        let call = try #require(sent.messages.last?["callAgentFunction"])
        #expect(call["surfaceId"] == "s1" && call["callFunction"]?["@call"] == "lookup" && call["callFunction"]?["args"] == ["q": 1])
        let id = call["functionCallId"]?.stringValue ?? ""
        await h.process(message: ["version": "1.0", "agentFunctionResponse": ["functionCallId": .string(id), "value": 42]])
        #expect(try await value == 42)

        let failing = Task { try await h.callAgentFunction(surfaceID: "s1", name: "lookup") }
        await settle()
        let id2 = sent.messages.last?["callAgentFunction"]?["functionCallId"]?.stringValue ?? ""
        await h.process(message: ["version": "1.0", "agentFunctionResponse": ["functionCallId": .string(id2), "error": ["code": "X", "message": "실패"]]])
        await #expect(throws: (any Error).self) { try await failing.value }
    }

    @Test func stateAndViewsSync() async throws {
        let rt = AgentRuntime()
        var cart: GentizerJSONValue = [1]
        let offCart = try rt.state("cart", StateDef(description: "장바구니")) { cart }
        try rt.state("empty", StateDef(description: "없음")) { nil }
        try rt.view("list", ViewDef(description: "상품 목록"))
        let (h, _) = try host(rt)
        try await create(h, sendDataModel: true)
        #expect(h.dataModel() == ["version": "1.0", "surfaces": ["s1": ["gentizer": [
            "state": ["cart": [1]], "views": ["list": "상품 목록"],
        ]]]])
        cart = [1, 2]
        h.syncState()
        #expect(h.dataModel()["surfaces"]?["s1"]?["gentizer"]?["state"]?["cart"] == [1, 2])
        offCart()
        #expect(h.dataModel()["surfaces"]?["s1"]?["gentizer"]?["state"] == [:])
    }

    @Test func stateSyncOff() async throws {
        let rt = AgentRuntime()
        try rt.state("cart", StateDef(description: "장바구니")) { [1] }
        let (h, _) = try host(rt, stateSync: false)
        try await create(h, sendDataModel: true)
        #expect(h.dataModel() == ["version": "1.0", "surfaces": ["s1": [:]]])
    }
}

extension ISO8601DateFormatter {
    static var fraction: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }
}
