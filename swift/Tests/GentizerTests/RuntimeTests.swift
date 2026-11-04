import Foundation
import Testing
@testable import Gentizer

// 등록 · invoke · confirm 규칙은 conformance/runtime. 여기는 Swift 고유 (구독 · 클로저 · async · Codable)

@MainActor
struct RuntimeTests {
    @Test func subscribeCalledPerChangeUntilUnsubscribed() throws {
        let rt = AgentRuntime()
        var count = 0
        let unsub = rt.subscribe { count += 1 }
        let off = try rt.action("a", ActionDef(description: "a")) { _ in .null }
        off()
        off()
        #expect(count == 2)
        unsub()
        try rt.action("a", ActionDef(description: "a")) { _ in .null }
        #expect(count == 2)
    }

    @Test func readStateIsReadAtCallTime() throws {
        let rt = AgentRuntime()
        var n = 1
        try rt.state("count", StateDef(description: "개수")) { .number(Double(n)) }
        n = 2
        #expect(rt.readState("count") == 2)
    }

    @Test func asyncRunAndAsyncConfirm() async throws {
        let rt = AgentRuntime { _ in
            try await Task.sleep(nanoseconds: 1_000_000)
            return true
        }
        try rt.action("pay", ActionDef(description: "결제", confirm: true)) { _ in
            try await Task.sleep(nanoseconds: 1_000_000)
            return 42
        }
        #expect(try await rt.invoke("pay").get() == 42)
    }

    @Test func catalogRejectsInvalidRegisteredName() throws {
        let rt = AgentRuntime()
        try rt.action("Bad", ActionDef(description: "x")) { _ in .null }
        #expect(throws: InvalidManifestError.self) { try toA2uiCatalog(rt.manifest(), catalogId: "x") }
    }
}

struct JSONValueTests {
    struct Item: Codable, Equatable {
        let id: Int
        let name: String
        let tags: [String]
    }

    @Test func encodableRoundTrip() throws {
        let item = Item(id: 1, name: "사과", tags: ["과일"])
        let json = try JSONValue(encoding: item)
        #expect(json == ["id": 1, "name": "사과", "tags": ["과일"]])
        #expect(try json.decode(as: Item.self) == item)
    }

    @Test func boolAndNumberStayDistinct() throws {
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(#"[true, 1, 0, false, 1.5, null]"#.utf8))
        #expect(v == [true, 1, 0, false, 1.5, nil])
    }
}
