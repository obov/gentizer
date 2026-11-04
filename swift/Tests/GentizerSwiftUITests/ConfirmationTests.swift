import Gentizer
import SwiftUI
import Testing
@testable import GentizerSwiftUI

@MainActor
private func yield() async {
    for _ in 0..<20 { await Task.yield() }
}

@MainActor
struct ConfirmationTests {
    private func setup() throws -> (AgentRuntime, AgentConfirmation, () -> Int) {
        let confirmation = AgentConfirmation()
        let rt = AgentRuntime(confirm: confirmation.confirm)
        var runs = 0
        try rt.action("cart_clear", ActionDef(description: "비우기", confirm: true)) { _ in
            runs += 1
            return .number(Double(runs))
        }
        return (rt, confirmation, { runs })
    }

    @Test func approveRunsAndDenyDenies() async throws {
        let (rt, c, runs) = try setup()
        let first = Task { await rt.invoke("cart_clear", args: ["all": true]) }
        await yield()
        #expect(c.request == ConfirmRequest(name: "cart_clear", description: "비우기", args: ["all": true]))
        #expect(c.request?.alertMessage == "비우기\n{\"all\":true}")
        c.approve()
        #expect(try await first.value.get() == 1)
        #expect(c.request == nil)

        let second = Task { await rt.invoke("cart_clear") }
        await yield()
        c.deny()
        #expect(await second.value == .failure(InvokeError(code: .denied, message: "사용자 승인 없음: cart_clear")))
        #expect(runs() == 1)
    }

    @Test func queuedInOrder() async throws {
        let (rt, c, _) = try setup()
        let a = Task { await rt.invoke("cart_clear", args: ["n": 1]) }
        await yield()
        let b = Task { await rt.invoke("cart_clear", args: ["n": 2]) }
        await yield()
        #expect(c.request?.args == ["n": 1])
        c.deny()
        await yield()
        #expect(c.request?.args == ["n": 2])
        c.approve()
        #expect((try? await a.value.get()) == nil)
        #expect(try await b.value.get() == 1)
    }

    @Test func cancelledWaitIsDeniedAndNextShown() async throws {
        let c = AgentConfirmation()
        let first = Task { await c.confirm(ConfirmRequest(name: "a", description: "a", args: [:])) }
        await yield()
        let second = Task { await c.confirm(ConfirmRequest(name: "b", description: "b", args: [:])) }
        await yield()
        first.cancel()
        #expect(await first.value == false)
        await yield()
        #expect(c.request?.name == "b")
        c.approve()
        #expect(await second.value == true)
    }

    #if os(macOS)
    @Test func modifierRenders() async throws {
        let c = AgentConfirmation()
        let hosting = NSHostingView(rootView: Text("x").agentConfirmation(c))
        hosting.frame = .init(x: 0, y: 0, width: 100, height: 50)
        hosting.layoutSubtreeIfNeeded()
        let pending = Task { await c.confirm(ConfirmRequest(name: "a", description: "a", args: [:])) }
        await yield()
        hosting.layoutSubtreeIfNeeded()
        c.approve()
        #expect(await pending.value == true)
    }
    #endif
}
