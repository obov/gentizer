#if os(macOS)
import AppKit
import Gentizer
import SwiftUI
import Testing
@testable import GentizerSwiftUI

private struct Shop: View {
    let showCart: Bool
    let count: Int

    var body: some View {
        VStack {
            Text("shop")
                .agentAction("cart_clear", ActionDef(description: "비우기", confirm: true)) { _ in .number(Double(count)) }
            if showCart {
                Text("cart")
                    .agentState("cart", StateDef(description: "장바구니"), value: [count])
                    .agentView("cart", ViewDef(description: "장바구니 영역"))
            }
        }
    }
}

@MainActor
private func host(_ view: some View, _ rt: AgentRuntime) -> (NSWindow, NSHostingView<AnyView>) {
    let hosting = NSHostingView(rootView: AnyView(view.agentRuntime(rt)))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 200), styleMask: [], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false  // close() 후 ARC 와 이중 해제 방지
    window.contentView = hosting
    window.orderFront(nil)
    return (window, hosting)
}

@MainActor
private func settle() async {
    for _ in 0..<5 {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

@MainActor
@Suite(.serialized)
struct ModifierTests {
    @Test func registersWhileShownAndUnregistersWhenRemoved() async throws {
        let rt = AgentRuntime { _ in true }
        let model = AgentManifestModel(runtime: rt)
        let (window, hosting) = host(Shop(showCart: true, count: 1), rt)
        defer { window.close() }
        await settle()
        #expect(rt.manifest().actions.names == ["cart_clear"])
        #expect(rt.manifest().views.names == ["cart"])
        #expect(rt.readState("cart") == [1])
        #expect(model.manifest == rt.manifest())

        // 클로저 · value 만 변경: 재등록 없이 최신 값
        var changes = 0
        _ = rt.subscribe { changes += 1 }
        hosting.rootView = AnyView(Shop(showCart: true, count: 2).agentRuntime(rt))
        await settle()
        #expect(changes == 0)
        #expect(rt.readState("cart") == [2])
        #expect(try await rt.invoke("cart_clear").get() == 2)

        // 조건부 뷰 제거: 해제
        hosting.rootView = AnyView(Shop(showCart: false, count: 2).agentRuntime(rt))
        await settle()
        #expect(rt.manifest().state.names == [])
        #expect(rt.manifest().views.names == [])
        #expect(model.manifest.views.names == [])
    }

    @Test func noRuntimeNoRegistration() async {
        let rt = AgentRuntime()
        let hosting = NSHostingView(rootView: Text("x").agentView("v", ViewDef(description: "v")))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 50, height: 50), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        await settle()
        #expect(rt.manifest().views.names == [])
    }
}
#endif
