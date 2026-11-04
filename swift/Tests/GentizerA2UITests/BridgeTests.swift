import Foundation
import Gentizer
import Testing
@testable import GentizerA2UI

// 규칙은 conformance/a2ui. 여기는 Swift 고유 (JSON 형태 · surfaceId · version)

@MainActor
struct BridgeTests {
    private func bridge() throws -> A2UIBridge {
        let rt = AgentRuntime()
        try rt.action("ping", ActionDef(description: "핑")) { _ in .null }
        return A2UIBridge(rt, catalogId: "cat")
    }

    private func message(_ json: String) throws -> A2UICallRendererFunctionMessage {
        try JSONDecoder().decode(A2UICallRendererFunctionMessage.self, from: Data(json.utf8))
    }

    private func encoded(_ r: A2UIRendererFunctionResponseMessage) throws -> JSONValue {
        try JSONValue(encoding: r)
    }

    @Test func decodesCallKeys() throws {
        let m = try message(#"{"version":"1.0","callRendererFunction":{"functionCallId":"c1","callFunction":{"@call":"ping","args":{"a":1}}}}"#)
        #expect(m.callRendererFunction.callFunction == A2UIFunctionCall(call: "ping", args: ["a": 1]))
        let legacy = try message(#"{"version":"1.0","callRendererFunction":{"functionCallId":"c1","callFunction":{"call":"ping"}}}"#)
        #expect(legacy.callRendererFunction.callFunction.call == "ping")
        #expect(try JSONValue(encoding: m.callRendererFunction.callFunction) == ["@call": "ping", "args": ["a": 1]])
    }

    @Test func nullValueKeepsKey() async throws {
        let r = try await bridge().handle(message(#"{"version":"1.0","callRendererFunction":{"functionCallId":"c1","callFunction":{"@call":"ping"}}}"#))
        #expect(try encoded(r) == ["version": "1.0", "rendererFunctionResponse": ["functionCallId": "c1", "value": nil]])
    }

    @Test func errorOmitsValue() async throws {
        let r = try await bridge().handle(message(#"{"version":"1.0","callRendererFunction":{"functionCallId":"c2","callFunction":{"@call":"none"}}}"#))
        #expect(try encoded(r) == ["version": "1.0", "rendererFunctionResponse": [
            "functionCallId": "c2", "error": ["code": "INVALID_FUNCTION_CALL", "message": "Function not found: none"]]])
    }

    @Test func surfaceIdRejected() async throws {
        let r = try await bridge().handle(message(#"{"version":"1.0","callRendererFunction":{"functionCallId":"c3","surfaceId":"s1","callFunction":{"@call":"ping"}}}"#))
        #expect(r.rendererFunctionResponse.error == A2UIFunctionError(code: "INVALID_FUNCTION_CALL", message: "Surface not found: s1"))
    }

    @Test func otherVersionRejected() async throws {
        let r = try await bridge().handle(message(#"{"version":"0.9","callRendererFunction":{"functionCallId":"c4","callFunction":{"@call":"ping"}}}"#))
        #expect(r.version == "0.9")
        #expect(r.rendererFunctionResponse.error?.code == "INVALID_FUNCTION_CALL")
    }

    @Test func catalogMatchesCore() throws {
        let b = try bridge()
        #expect(try b.catalog() == toA2uiCatalog(b.runtime.manifest(), catalogId: "cat"))
    }
}
