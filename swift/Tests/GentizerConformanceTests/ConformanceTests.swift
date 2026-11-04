import Foundation
@testable import Gentizer
import GentizerA2UI
import GentizerAGUI
import Testing

/// suite → skip 사유. 구현하면 지우고 아래 실행 테스트를 채운다
let skippedSuites: [String: String] = [:]

let allSuites = ["validate", "catalog", "runtime", "ag-ui", "a2ui"]

func cases(_ suite: String) throws -> [LoadedCase] {
    try loadSuite(suite, in: try conformanceDirectory())
}

@Suite("conformance 형식")
struct ConformanceFormatTests {
    @Test("suite 케이스 로드", arguments: allSuites)
    func loads(suite: String) throws {
        let cases = try loadSuite(suite, in: try conformanceDirectory())
        #expect(!cases.isEmpty)
        if let reason = skippedSuites[suite] {
            print("conformance \(suite): \(cases.count)개 skip (\(reason))")
        }
    }

    @Test("suite 불일치 · id 중복은 실패")
    func rejectsBadFiles() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("gentizer-conf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let dir = tmp.appendingPathComponent("validate")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let write = { (s: String) in try Data(s.utf8).write(to: dir.appendingPathComponent("a.json")) }

        try write(#"{"suite":"catalog","cases":[{"name":"x"}]}"#)
        #expect(throws: ConformanceError.self) { try loadSuite("validate", in: tmp) }
        try write(#"{"suite":"validate","cases":[{"name":"x"},{"name":"x"}]}"#)
        #expect(throws: ConformanceError.self) { try loadSuite("validate", in: tmp) }
        try FileManager.default.removeItem(at: dir.appendingPathComponent("a.json"))
        #expect(throws: ConformanceError.self) { try loadSuite("validate", in: tmp) }
    }

    @Test("배포 저장소 위치 Tests/Conformance 도 찾음")
    func findsExportedLocation() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("gentizer-pkg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pkg = tmp.appendingPathComponent("gentizer-swift")
        let conf = pkg.appendingPathComponent("Tests/Conformance")
        try FileManager.default.createDirectory(at: conf, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: conf.appendingPathComponent("schema.json"))
        #expect(try conformanceDirectory(packageRoot: pkg).standardizedFileURL == conf.standardizedFileURL)
    }
}

@Suite("conformance validate")
struct ValidateConformance {
    @Test(arguments: try cases("validate"))
    func run(_ c: LoadedCase) throws {
        let result = validateManifest(c.value["manifest"] ?? .null)
        let expect = try #require(c.value["expect"])
        if expect["ok"] == .bool(true) {
            #expect(result == .ok)
        } else {
            let want = (expect["errorPaths"]?.arrayValue ?? []).compactMap(\.stringValue).sorted()
            #expect(result != .ok)
            #expect(result.errors.map(\.path).sorted() == want)
        }
    }
}

@Suite("conformance catalog")
struct CatalogConformance {
    @Test(arguments: try cases("catalog"))
    func run(_ c: LoadedCase) throws {
        let catalogId = try #require(c.value["catalogId"]?.stringValue)
        let build = { try toA2uiCatalog(Manifest(json: c.value["manifest"] ?? .null), catalogId: catalogId) }
        if c.value["error"] == "INVALID_MANIFEST" {
            #expect(throws: InvalidManifestError.self) { try build() }
        } else {
            #expect(try build() == c.value["catalog"])
        }
    }
}

@Suite("conformance runtime")
@MainActor
struct RuntimeConformance {
    @Test(arguments: try cases("runtime"))
    func run(_ c: LoadedCase) async throws {
        let recorder = ConfirmRecorder()
        let rt = recorder.makeRuntime(c.value["confirm"]?.stringValue)
        var handles: [String: @MainActor () -> Void] = [:]
        for (i, step) in (c.value["steps"]?.arrayValue ?? []).enumerated() {
            let op = step["op"]?.stringValue ?? ""
            let at = Comment(rawValue: "\(c.id) step \(i) \(op)")
            let name = step["name"]?.stringValue ?? ""
            switch op {
            case "register":
                if step["expectError"] == "DUPLICATE_NAME" {
                    #expect(throws: DuplicateNameError.self, at) { try register(rt, step) }
                } else {
                    let off = try register(rt, step)
                    if let h = step["handle"]?.stringValue { handles[h] = off }
                }
            case "unregister":
                let off = try #require(handles[step["handle"]?.stringValue ?? ""], at)
                off()
            case "invoke":
                let before = recorder.calls.count
                let r = if let args = step["args"] { await rt.invoke(name, args: args) } else { await rt.invoke(name) }
                let expect = step["expect"] ?? .null
                switch r {
                case .success(let value):
                    #expect(expect["ok"] == true && expect["value"] == value, at)
                case .failure(let e):
                    #expect(expect["ok"] == false && expect["code"] == .string(e.code.rawValue), at)
                }
                if let want = step["expectConfirm"] {
                    let made = recorder.calls[before...].map(\.json)
                    #expect(made == (want == .null ? [] : [want]), at)
                }
            case "manifest":
                let m = rt.manifest()
                #expect(m.json == step["expect"], at)
                for (section, order) in step["expectOrder"]?.objectValue ?? [:] {
                    let names = switch section {
                    case "actions": m.actions.names
                    case "state": m.state.names
                    default: m.views.names
                    }
                    #expect(names.map(JSONValue.string) == order.arrayValue, at)
                }
            case "readState":
                #expect((rt.readState(name) ?? .null) == step["expect"], at)
            default:
                Issue.record(Comment(rawValue: "알 수 없는 op \(op)"))
            }
        }
    }
}

@Suite("conformance ag-ui")
@MainActor
struct AgUiConformance {
    @Test(arguments: try cases("ag-ui"))
    func run(_ c: LoadedCase) async throws {
        let recorder = ConfirmRecorder()
        let rt = recorder.makeRuntime(c.value["confirm"]?.stringValue)
        try registerDecls(rt, actions: c.value["actions"], states: c.value["states"])
        let expect = c.value["expect"]?.arrayValue ?? []
        switch c.value["op"]?.stringValue {
        case "tools":
            #expect(try JSONValue(encoding: toAGUITools(rt.manifest())) == .array(expect))
        case "context":
            let got = toAGUIContext(rt).map { ["description": .string($0.description), "value": parseJSON($0.value) ?? "<invalid>"] as JSONValue }
            #expect(got == expect)
        case "runFrontendTools":
            let messages = try (c.value["messages"] ?? []).decode(as: [AGUIMessage].self)
            let out = await runFrontendTools(rt, messages)
            #expect(out.map(\.id) == out.map { "gentizer-\($0.toolCallId ?? "")" })
            #expect(out.allSatisfy { $0.role == "tool" })
            let got: [JSONValue] = out.map { m in
                var content = parseJSON(m.content) ?? "<invalid>"
                if let code = content["error"]?["code"] { content = ["error": ["code": code]] }
                var o: [String: JSONValue] = ["toolCallId": .string(m.toolCallId ?? ""), "content": content]
                if let e = m.error { o["errorCode"] = .string(String(e.prefix { $0 != ":" })) }
                return .object(o)
            }
            #expect(got == expect)
            for m in out where m.error != nil {
                #expect(m.error!.hasPrefix("\(m.error!.prefix { $0 != ":" }): "))
            }
        default:
            Issue.record(Comment(rawValue: "알 수 없는 op"))
        }
    }
}

@Suite("conformance a2ui")
@MainActor
struct A2uiConformance {
    @Test(arguments: try cases("a2ui"))
    func run(_ c: LoadedCase) async throws {
        let recorder = ConfirmRecorder()
        let rt = recorder.makeRuntime(c.value["confirm"]?.stringValue)
        try registerDecls(rt, actions: c.value["actions"], states: nil)
        let message = try (c.value["message"] ?? .null).decode(as: A2UICallRendererFunctionMessage.self)
        let bridge = A2UIBridge(rt, catalogId: c.value["catalogId"]?.stringValue ?? "")
        let r = await bridge.handle(message).rendererFunctionResponse
        #expect(r.functionCallId == message.callRendererFunction.functionCallId)
        let expect = c.value["expect"] ?? .null
        if let code = expect["errorCode"]?.stringValue {
            #expect(r.error?.code == code)
            if let prefix = expect["messagePrefix"]?.stringValue {
                #expect(r.error?.message.hasPrefix(prefix) == true, "\(r.error?.message ?? "")")
            }
        } else {
            #expect(r.error == nil)
            #expect(r.value == expect["value"])
        }
    }
}
