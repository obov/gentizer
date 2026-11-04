/// manifest 형식 버전
public let manifestVersion = "gentizer/0.1"

/// 소문자 영문 시작, 소문자 영숫자 · _. A2UI v1.0 function 이름 (UAX #31) 과 LLM tool 이름의 공통 부분집합
public let nameMaxLength = 64

public func isValidName(_ name: String) -> Bool {
    guard let first = name.unicodeScalars.first, name.unicodeScalars.count <= nameMaxLength,
          ("a"..."z").contains(first) else { return false }
    return name.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
}

public enum ReturnType: String, Sendable, CaseIterable, Codable {
    case string, number, boolean, array, object, any, void
}

public struct ActionDef: Equatable, Sendable {
    public var description: String
    /// JSON Schema. 최상위 type 은 "object"
    public var input: JSONValue?
    public var confirm: Bool?
    public var returns: ReturnType?

    public init(description: String, input: JSONValue? = nil, confirm: Bool? = nil, returns: ReturnType? = nil) {
        self.description = description
        self.input = input
        self.confirm = confirm
        self.returns = returns
    }
}

public struct StateDef: Equatable, Sendable {
    public var description: String
    public var schema: JSONValue?

    public init(description: String, schema: JSONValue? = nil) {
        self.description = description
        self.schema = schema
    }
}

public struct ViewDef: Equatable, Sendable {
    public var description: String

    public init(description: String) {
        self.description = description
    }
}

/// 등록 순서를 유지하는 이름 → 정의 목록
public struct Entries<Def: Equatable & Sendable>: Equatable, Sendable, Sequence {
    public private(set) var names: [String] = []
    private var defs: [String: Def] = [:]

    public init() {}

    public subscript(name: String) -> Def? { defs[name] }
    public var count: Int { names.count }

    /// 같은 이름이 있으면 false
    @discardableResult
    mutating func append(_ name: String, _ def: Def) -> Bool {
        guard defs[name] == nil else { return false }
        names.append(name)
        defs[name] = def
        return true
    }

    mutating func remove(_ name: String) {
        guard defs.removeValue(forKey: name) != nil else { return }
        names.removeAll { $0 == name }
    }

    public func makeIterator() -> AnyIterator<(name: String, def: Def)> {
        var i = names.makeIterator()
        return AnyIterator { i.next().map { ($0, defs[$0]!) } }
    }
}

public struct Manifest: Equatable, Sendable {
    public var version = manifestVersion
    public var actions = Entries<ActionDef>()
    public var state = Entries<StateDef>()
    public var views = Entries<ViewDef>()

    public init() {}
}
