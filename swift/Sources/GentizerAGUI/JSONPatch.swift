import Gentizer

/// RFC 6902 JSON Patch. 전체 성공 시에만 결과를 돌려준다 (실패 = nil, 원본 무변화)
func applyJSONPatch(_ doc: JSONValue, _ patch: JSONValue) -> JSONValue? {
    guard let ops = patch.arrayValue else { return nil }
    var out = doc
    for op in ops {
        guard let kind = op["op"]?.stringValue, let path = op["path"]?.stringValue.flatMap(pointer) else { return nil }
        switch kind {
        case "add":
            guard let value = op["value"], let r = add(out, path, value) else { return nil }
            out = r
        case "remove":
            guard let r = remove(out, path) else { return nil }
            out = r
        case "replace" where path.isEmpty:
            guard let value = op["value"] else { return nil }
            out = value
        case "replace":
            guard let value = op["value"], get(out, path) != nil, let removed = remove(out, path),
                  let r = add(removed, path, value) else { return nil }
            out = r
        case "move":
            guard let from = op["from"]?.stringValue.flatMap(pointer), let value = get(out, from),
                  !(path.count > from.count && Array(path.prefix(from.count)) == from),
                  let removed = remove(out, from), let r = add(removed, path, value) else { return nil }
            out = r
        case "copy":
            guard let from = op["from"]?.stringValue.flatMap(pointer), let value = get(out, from),
                  let r = add(out, path, value) else { return nil }
            out = r
        case "test":
            guard let value = op["value"], get(out, path) == value else { return nil }
        default:
            return nil
        }
    }
    return out
}

/// "" = 루트 (빈 배열). "/a/b" → ["a", "b"]. ~1 = /, ~0 = ~
private func pointer(_ s: String) -> [String]? {
    if s.isEmpty { return [] }
    guard s.hasPrefix("/") else { return nil }
    return s.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map {
        $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
    }
}

private func index(_ token: String, count: Int, allowEnd: Bool) -> Int? {
    if allowEnd, token == "-" { return count }
    guard let i = Int(token), String(i) == token, i >= 0 else { return nil }
    return i <= (allowEnd ? count : count - 1) ? i : nil
}

private func get(_ doc: JSONValue, _ path: [String]) -> JSONValue? {
    var cur = doc
    for token in path {
        switch cur {
        case .object(let o):
            guard let next = o[token] else { return nil }
            cur = next
        case .array(let a):
            guard let i = index(token, count: a.count, allowEnd: false) else { return nil }
            cur = a[i]
        default:
            return nil
        }
    }
    return cur
}

/// path 의 부모를 찾아 마지막 토큰에 f 적용
private func update(_ doc: JSONValue, _ path: [String], _ f: (JSONValue, String) -> JSONValue?) -> JSONValue? {
    guard let head = path.first else { return nil }
    if path.count == 1 { return f(doc, head) }
    let rest = Array(path.dropFirst())
    switch doc {
    case .object(var o):
        guard let child = o[head], let r = update(child, rest, f) else { return nil }
        o[head] = r
        return .object(o)
    case .array(var a):
        guard let i = index(head, count: a.count, allowEnd: false), let r = update(a[i], rest, f) else { return nil }
        a[i] = r
        return .array(a)
    default:
        return nil
    }
}

private func add(_ doc: JSONValue, _ path: [String], _ value: JSONValue) -> JSONValue? {
    if path.isEmpty { return value }
    return update(doc, path) { parent, token in
        switch parent {
        case .object(var o):
            o[token] = value
            return .object(o)
        case .array(var a):
            guard let i = index(token, count: a.count, allowEnd: true) else { return nil }
            a.insert(value, at: i)
            return .array(a)
        default:
            return nil
        }
    }
}

private func remove(_ doc: JSONValue, _ path: [String]) -> JSONValue? {
    if path.isEmpty { return nil }
    return update(doc, path) { parent, token in
        switch parent {
        case .object(var o):
            guard o.removeValue(forKey: token) != nil else { return nil }
            return .object(o)
        case .array(var a):
            guard let i = index(token, count: a.count, allowEnd: false) else { return nil }
            a.remove(at: i)
            return .array(a)
        default:
            return nil
        }
    }
}
