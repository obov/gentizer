import Foundation
import Gentizer
import SwiftUI
import Testing
@testable import GentizerA2UISwiftUI

// specs/a2ui.md '앱 컴포넌트 catalog'

@MainActor
final class Seen {
    var props: [String: String] = [:]
    var built = 0
    var buy: (() -> Void)?
}

@MainActor
struct AppComponentTests {
    private func card(_ seen: Seen) -> A2UIAppComponent {
        A2UIAppComponent("ProductCard", description: "상품 카드",
                         properties: ["name": A2UIProp.string, "price": A2UIProp.number,
                                      "soldOut": A2UIProp.bool, "action": A2UIProp.action,
                                      "badge": A2UIProp.child],
                         required: ["name"]) { props in
            let _ = {
                seen.built += 1
                seen.props = ["name": props.string("name") ?? "-", "price": props.double("price").map { String($0) } ?? "-",
                              "soldOut": props.bool("soldOut").map { String($0) } ?? "-",
                              "hasBadge": String(props.child("badge") != nil)]
                seen.buy = props.action("action")
            }()
            Text(props.string("name") ?? "")
        }
    }

    private func json(_ s: String) throws -> GentizerJSONValue {
        try JSONDecoder().decode(GentizerJSONValue.self, from: Data(s.utf8))
    }

    private func host(_ components: [A2UIAppComponent], sent: Sent) throws -> A2UISurfaceHost {
        try A2UISurfaceHost(AgentRuntime(), catalogId: "cat", components: components) { sent.messages.append($0) }
    }

    @Test func appCatalogSurfaceAndProps() async throws {
        let seen = Seen()
        let sent = Sent()
        let h = try host([card(seen)], sent: sent)
        await h.process(message: try json(#"{"version":"1.0","createSurface":{"surfaceId":"s1","catalogId":"cat#components"}}"#))
        await h.process(message: try json(#"""
        {"version":"1.0","updateComponents":{"surfaceId":"s1","components":[
          {"id":"root","component":"ProductCard","name":"러닝화","price":59000,"soldOut":false,
           "action":{"event":{"name":"buy","context":{"id":1}}}}]}}
        """#))
        #expect(sent.messages.isEmpty)
        let root = try #require(h.surface("s1")?.rootNode)
        #expect(root.type == "ProductCard")

        // SurfaceView 가 앱 builder 를 호출
        let renderer = ImageRenderer(content: A2UISurfaceView(host: h, surfaceID: "s1").frame(width: 200, height: 100))
        _ = renderer.cgImage
        #expect(seen.built > 0)
        #expect(seen.props == ["name": "러닝화", "price": "59000.0", "soldOut": "false", "hasBadge": "false"])
        seen.buy?()
        for _ in 0..<20 { await Task.yield() }
        #expect(sent.messages.last?["action"]?["name"] == "buy")
    }

    @Test func basicComponentsInAppCatalogAndMissingRequired() async throws {
        let sent = Sent()
        let h = try host([card(Seen())], sent: sent)
        await h.process(message: try json(#"{"version":"1.0","createSurface":{"surfaceId":"s1","catalogId":"cat#components"}}"#))
        await h.process(message: try json(#"{"version":"1.0","updateComponents":{"surfaceId":"s1","components":[{"id":"root","component":"Column","children":["c"]},{"id":"c","component":"ProductCard"}]}}"#))
        for _ in 0..<20 { await Task.yield() }
        #expect(sent.messages.contains { $0["error"]?["code"] == "VALIDATION_FAILED" })
    }

    @Test func componentCatalogJSON() throws {
        let h = try host([card(Seen())], sent: Sent())
        let c = try #require(h.componentCatalog())
        #expect(c["catalogId"] == "cat#components" && c["protocolVersion"] == "1.0")
        #expect(c["components"]?["ProductCard"]?["required"] == ["component", "name"])
        #expect(c["components"]?["ProductCard"]?["properties"]?["component"] == ["const": "ProductCard"])
        #expect(c["components"]?["ProductCard"]?["description"] == "상품 카드")
    }

    @Test func overridesBasicNameAndNoComponents() async throws {
        let seen = Seen()
        let text = A2UIAppComponent("Text", description: "앱 텍스트", properties: ["text": ["type": "string"]]) { props in
            let _ = { seen.built += 1 }()
            Text(props.string("text") ?? "")
        }
        let h = try host([text], sent: Sent())
        await h.process(message: try json(#"{"version":"1.0","createSurface":{"surfaceId":"s1","catalogId":"cat#components"}}"#))
        await h.process(message: try json(#"{"version":"1.0","updateComponents":{"surfaceId":"s1","components":[{"id":"root","component":"Text","text":"x"}]}}"#))
        _ = ImageRenderer(content: A2UISurfaceView(host: h, surfaceID: "s1").frame(width: 100, height: 50)).cgImage
        #expect(seen.built > 0)
        #expect(try host([], sent: Sent()).componentCatalog() == nil)
    }
}
