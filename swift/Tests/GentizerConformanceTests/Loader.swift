import Foundation
import Testing

/// conformance 케이스 하나. id = <suite>/<파일명>#<name>
struct LoadedCase: Sendable, CustomTestStringConvertible {
    let id: String
    let value: JSONValue
    var testDescription: String { id }
}

enum ConformanceError: Error, CustomStringConvertible {
    case notFound([String])
    case empty(String)
    case suiteMismatch(file: String, suite: String?)
    case missingName(file: String)
    case duplicate(String)

    var description: String {
        switch self {
        case .notFound(let tried): "conformance 폴더 없음: \(tried.joined(separator: " · "))"
        case .empty(let suite): "conformance/\(suite) 케이스 파일 없음"
        case .suiteMismatch(let file, let suite): "\(file) suite 불일치: \(suite ?? "없음")"
        case .missingName(let file): "\(file) name 없는 케이스"
        case .duplicate(let id): "케이스 id 중복: \(id)"
        }
    }
}

/// 케이스 위치: 개발 저장소 루트 conformance/ → 배포 저장소 Tests/Conformance/ (specs/swift.md)
func conformanceDirectory(packageRoot: URL = packageRoot()) throws -> URL {
    let candidates = [
        packageRoot.deletingLastPathComponent().appendingPathComponent("conformance"),
        packageRoot.appendingPathComponent("Tests/Conformance"),
    ]
    for dir in candidates where FileManager.default.fileExists(atPath: dir.appendingPathComponent("schema.json").path) {
        return dir
    }
    throw ConformanceError.notFound(candidates.map(\.path))
}

func packageRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

/// conformance/<suite>/*.json 전부. 파일 없음 · suite 불일치 · name 없음 · id 중복은 throw
func loadSuite(_ suite: String, in dir: URL) throws -> [LoadedCase] {
    let suiteDir = dir.appendingPathComponent(suite)
    let files = (try? FileManager.default.contentsOfDirectory(atPath: suiteDir.path)) ?? []
    let jsonFiles = files.filter { $0.hasSuffix(".json") }.sorted()
    if jsonFiles.isEmpty { throw ConformanceError.empty(suite) }
    var out: [LoadedCase] = []
    var seen = Set<String>()
    for f in jsonFiles {
        let label = "conformance/\(suite)/\(f)"
        let data = try Data(contentsOf: suiteDir.appendingPathComponent(f))
        let file = try JSONDecoder().decode(JSONValue.self, from: data)
        guard file["suite"]?.stringValue == suite else {
            throw ConformanceError.suiteMismatch(file: label, suite: file["suite"]?.stringValue)
        }
        guard case .array(let cases)? = file["cases"] else { throw ConformanceError.empty(suite) }
        for c in cases {
            guard let name = c["name"]?.stringValue else { throw ConformanceError.missingName(file: label) }
            let id = "\(suite)/\(f.dropLast(5))#\(name)"
            if !seen.insert(id).inserted { throw ConformanceError.duplicate(id) }
            out.append(LoadedCase(id: id, value: c))
        }
    }
    return out
}
