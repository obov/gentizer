import Foundation
import Gentizer
import Testing
@testable import GentizerA2UISwiftUI

@MainActor
struct SurfaceHostTests {
    private let basic = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"

    private func host() throws -> A2UISurfaceHost {
        let rt = AgentRuntime()
        try rt.action("ping", ActionDef(description: "핑")) { _ in "pong" }
        return A2UISurfaceHost(rt, catalogId: "cat")
    }

    private func json(_ s: String) throws -> GentizerJSONValue {
        try JSONDecoder().decode(GentizerJSONValue.self, from: Data(s.utf8))
    }

    private func create(_ h: A2UISurfaceHost) async throws {
        #expect(await h.process(message: try json(#"{"version":"1.0","createSurface":{"surfaceId":"s1","catalogId":"\#(basic)"}}"#)) == nil)
        #expect(await h.process(message: try json(#"{"version":"1.0","updateComponents":{"surfaceId":"s1","components":[{"id":"root","component":"Text","text":"안녕"}]}}"#)) == nil)
    }

    @Test func createAndUpdateActivatesSurface() async throws {
        let h = try host()
        try await create(h)
        #expect(h.surfaceIDs == ["s1"])
        #expect(h.surface("s1")?.rootNode?.type == "Text")
    }

    @Test func deleteDeactivates() async throws {
        let h = try host()
        try await create(h)
        _ = await h.process(message: try json(#"{"version":"1.0","deleteSurface":{"surfaceId":"s1"}}"#))
        #expect(h.surfaceIDs.isEmpty)
        #expect(h.surface("s1") == nil)
    }

    @Test func surfaceCallGoesToBridge() async throws {
        let h = try host()
        let call = #"{"version":"1.0","callRendererFunction":{"functionCallId":"c1","surfaceId":"s1","callFunction":{"@call":"ping"}}}"#
        let before = await h.process(message: try json(call))
        #expect(before?["rendererFunctionResponse"]?["error"]?["message"] == "Surface not found: s1")
        try await create(h)
        let after = await h.process(message: try json(call))
        #expect(after == ["version": "1.0", "rendererFunctionResponse": ["functionCallId": "c1", "value": "pong"]])
    }
}
