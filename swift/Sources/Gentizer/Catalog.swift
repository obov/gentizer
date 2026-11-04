public struct InvalidManifestError: Error, Equatable, CustomStringConvertible {
    public let errors: [ValidationError]

    public var description: String {
        "manifest 검증 실패: " + errors.map { "\($0.path.isEmpty ? "(root)" : $0.path) \($0.message)" }.joined(separator: "; ")
    }
}

extension ActionDef {
    var json: JSONValue {
        var o: [String: JSONValue] = ["description": .string(description)]
        if let input { o["input"] = input }
        if let confirm { o["confirm"] = .bool(confirm) }
        if let returns { o["returns"] = .string(returns.rawValue) }
        return .object(o)
    }

    /// 검증을 통과한 정의 JSON 에서만 호출
    init(validated o: JSONValue) {
        self.init(
            description: o["description"]?.stringValue ?? "",
            input: o["input"],
            confirm: o["confirm"]?.boolValue,
            returns: o["returns"]?.stringValue.flatMap(ReturnType.init(rawValue:)))
    }
}

extension StateDef {
    var json: JSONValue {
        var o: [String: JSONValue] = ["description": .string(description)]
        if let schema { o["schema"] = schema }
        return .object(o)
    }

    init(validated o: JSONValue) {
        self.init(description: o["description"]?.stringValue ?? "", schema: o["schema"])
    }
}

extension ViewDef {
    var json: JSONValue { ["description": .string(description)] }

    init(validated o: JSONValue) {
        self.init(description: o["description"]?.stringValue ?? "")
    }
}

extension Manifest {
    /// JSON → Manifest. 검증 실패는 InvalidManifestError. JSON object 는 순서가 없어 구역은 이름순
    public init(json: JSONValue) throws(InvalidManifestError) {
        if case .invalid(let errors) = validateManifest(json) { throw InvalidManifestError(errors: errors) }
        self.init()
        func each(_ section: String, _ body: (String, JSONValue) -> Void) {
            let o = json[section]?.objectValue ?? [:]
            for name in o.keys.sorted() { body(name, o[name]!) }
        }
        each("actions") { actions.append($0, ActionDef(validated: $1)) }
        each("state") { state.append($0, StateDef(validated: $1)) }
        each("views") { views.append($0, ViewDef(validated: $1)) }
    }

    /// JSON 표현 (TS Manifest 와 같은 형태)
    public var json: JSONValue {
        func section<D>(_ e: Entries<D>, _ f: (D) -> JSONValue) -> JSONValue {
            .object(Dictionary(uniqueKeysWithValues: e.map { ($0.name, f($0.def)) }))
        }
        return [
            "version": .string(version),
            "actions": section(actions, \.json),
            "state": section(state, \.json),
            "views": section(views, \.json),
        ]
    }
}

private let emptyInput: JSONValue = ["type": "object", "properties": [:]]

/// manifest 의 actions 를 A2UI v1.0 catalog function 정의로 변환. state · views 는 포함하지 않는다
public func toA2uiCatalog(_ m: Manifest, catalogId: String) throws(InvalidManifestError) -> JSONValue {
    if case .invalid(let errors) = validateManifest(m.json) { throw InvalidManifestError(errors: errors) }
    var functions: [String: JSONValue] = [:]
    var confirm: [JSONValue] = []
    for (name, action) in m.actions {
        let args = action.input ?? emptyInput
        let argsRequired = !(args["required"]?.arrayValue ?? []).isEmpty
        functions[name] = [
            "type": "object",
            "description": .string(action.description),
            "returnType": .string((action.returns ?? .void).rawValue),
            "allowedCallers": "agentOnly",
            "properties": ["@call": ["const": .string(name)], "args": args],
            "required": argsRequired ? ["@call", "args"] : ["@call"],
        ]
        if action.confirm == true { confirm.append(.string(name)) }
    }
    var catalog: [String: JSONValue] = [
        "protocolVersion": "1.0",
        "catalogId": .string(catalogId),
        "functions": .object(functions),
    ]
    if !confirm.isEmpty { catalog["metadata"] = ["extensions": ["gentizer": ["confirm": .array(confirm)]]] }
    return .object(catalog)
}
