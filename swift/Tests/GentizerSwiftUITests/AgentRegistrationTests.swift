import Gentizer
import Testing
@testable import GentizerSwiftUI

@MainActor
struct AgentRegistrationTests {
    @Test func registersAndUnregisters() {
        let rt = AgentRuntime()
        let reg = AgentRegistration()
        reg.update(runtime: rt, name: "cart_add", kind: .action(ActionDef(description: "담기")))
        #expect(rt.manifest().actions.names == ["cart_add"])
        reg.unregister()
        #expect(rt.manifest().actions.names == [])
    }

    @Test func sameKeyIsIdempotentAndUsesLatestClosure() async throws {
        let rt = AgentRuntime()
        var changes = 0
        _ = rt.subscribe { changes += 1 }
        let reg = AgentRegistration()
        let def = ActionDef(description: "담기")
        reg.run = { _ in 1 }
        reg.update(runtime: rt, name: "a", kind: .action(def))
        reg.run = { _ in 2 }
        reg.update(runtime: rt, name: "a", kind: .action(def))
        #expect(changes == 1)
        #expect(try await rt.invoke("a").get() == 2)
    }

    @Test func defChangeReregisters() {
        let rt = AgentRuntime()
        let reg = AgentRegistration()
        reg.update(runtime: rt, name: "cart", kind: .state(StateDef(description: "a")))
        reg.update(runtime: rt, name: "cart", kind: .state(StateDef(description: "b")))
        #expect(rt.manifest().state["cart"] == StateDef(description: "b"))
        reg.update(runtime: rt, name: "cart2", kind: .state(StateDef(description: "b")))
        #expect(rt.manifest().state.names == ["cart2"])
    }

    @Test func stateReadsLatestValue() {
        let rt = AgentRuntime()
        let reg = AgentRegistration()
        reg.read = { 1 }
        reg.update(runtime: rt, name: "n", kind: .state(StateDef(description: "n")))
        reg.read = { 2 }
        #expect(rt.readState("n") == 2)
    }

    @Test func duplicateIsIgnored() {
        let rt = AgentRuntime()
        let a = AgentRegistration()
        let b = AgentRegistration()
        a.update(runtime: rt, name: "v", kind: .view(ViewDef(description: "a")))
        b.update(runtime: rt, name: "v", kind: .view(ViewDef(description: "b")))
        #expect(!b.isRegistered)
        #expect(rt.manifest().views["v"] == ViewDef(description: "a"))
        b.unregister()
        #expect(rt.manifest().views.names == ["v"])
    }

    @Test func nilRuntimeUnregisters() {
        let rt = AgentRuntime()
        let reg = AgentRegistration()
        reg.update(runtime: rt, name: "v", kind: .view(ViewDef(description: "a")))
        reg.update(runtime: nil, name: "v", kind: .view(ViewDef(description: "a")))
        #expect(rt.manifest().views.names == [])
    }
}
