import Foundation
import Testing

/// suite → skip 사유. 구현하면 지우고 아래 실행 테스트를 채운다
let skippedSuites: [String: String] = [
    "validate": "Swift core 미구현",
    "catalog": "Swift core 미구현",
    "runtime": "Swift core 미구현",
    "ag-ui": "Swift AG-UI 어댑터 미구현",
    "a2ui": "Swift A2UI 브리지 미구현",
]

let allSuites = ["validate", "catalog", "runtime", "ag-ui", "a2ui"]

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

@Suite("conformance 실행")
struct ConformanceRunTests {
    @Test("validate", .disabled("Swift core 미구현")) func validate() {}
    @Test("catalog", .disabled("Swift core 미구현")) func catalog() {}
    @Test("runtime", .disabled("Swift core 미구현")) func runtime() {}
    @Test("ag-ui", .disabled("Swift AG-UI 어댑터 미구현")) func agUi() {}
    @Test("a2ui", .disabled("Swift A2UI 브리지 미구현")) func a2ui() {}
}
