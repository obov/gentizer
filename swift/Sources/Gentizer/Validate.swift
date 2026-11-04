import Foundation

public struct ValidationError: Equatable, Sendable {
    public let path: String
    public let message: String
}

public enum ValidationResult: Equatable, Sendable {
    case ok
    case invalid([ValidationError])

    public var errors: [ValidationError] {
        if case .invalid(let e) = self { return e }
        return []
    }
}

/// manifest 규칙 위반을 모두 수집한다 (TS validateManifest 와 같은 path)
public func validateManifest(_ m: JSONValue) -> ValidationResult {
    guard case .object(let root) = m else {
        return .invalid([ValidationError(path: "", message: "manifest 는 object")])
    }
    var errors: [ValidationError] = []
    func err(_ path: String, _ message: String) { errors.append(ValidationError(path: path, message: message)) }

    if root["version"] != .string(manifestVersion) { err("version", "\"\(manifestVersion)\" 이어야 함") }

    for section in ["actions", "state", "views"] {
        guard case .object(let entries)? = root[section] else {
            err(section, "object 이어야 함")
            continue
        }
        for name in entries.keys.sorted() {
            let p = "\(section).\(name)"
            if !isValidName(name) { err(p, "이름 규칙 위반: ^[a-z][a-z0-9_]*$ · \(nameMaxLength)자 이하") }
            guard case .object(let def)? = entries[name] else {
                err(p, "object 이어야 함")
                continue
            }
            let description = def["description"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if description.isEmpty { err("\(p).description", "비어 있지 않은 문자열이어야 함") }
            if section == "actions" {
                if let input = def["input"], input["type"] != .string("object") {
                    err("\(p).input", "JSON Schema 최상위 type 은 \"object\" 만 허용")
                }
                if let confirm = def["confirm"], confirm.boolValue == nil { err("\(p).confirm", "boolean 이어야 함") }
                if let r = def["returns"], ReturnType(rawValue: r.stringValue ?? "") == nil {
                    err("\(p).returns", "허용값: \(ReturnType.allCases.map(\.rawValue).joined(separator: ", "))")
                }
            }
            if section == "state", let schema = def["schema"], schema.objectValue == nil {
                err("\(p).schema", "JSON Schema object 이어야 함")
            }
        }
    }
    return errors.isEmpty ? .ok : .invalid(errors)
}
