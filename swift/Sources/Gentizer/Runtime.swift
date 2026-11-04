public struct DuplicateNameError: Error, Equatable, CustomStringConvertible {
    public let section: String
    public let name: String
    public var description: String { "\(section).\(name) 중복 등록" }
}

public enum InvokeErrorCode: String, Sendable, Equatable {
    case notFound = "NOT_FOUND"
    case invalidArgs = "INVALID_ARGS"
    case denied = "DENIED"
    case executionError = "EXECUTION_ERROR"
}

public struct InvokeError: Error, Equatable, Sendable {
    public let code: InvokeErrorCode
    public let message: String

    public init(code: InvokeErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

public typealias InvokeResult = Result<JSONValue, InvokeError>

public struct ConfirmRequest: Equatable, Sendable {
    public let name: String
    public let description: String
    public let args: [String: JSONValue]

    public init(name: String, description: String, args: [String: JSONValue]) {
        self.name = name
        self.description = description
        self.args = args
    }
}

/// P2 이벤트형: 앱 → 에이전트 알림
public struct TriggerEvent: Equatable, Sendable {
    public let name: String
    public let payload: [String: JSONValue]

    public init(name: String, payload: [String: JSONValue]) {
        self.name = name
        self.payload = payload
    }
}

public struct InvalidTriggerError: Error, Equatable, CustomStringConvertible {
    public let code = "INVALID_TRIGGER"
    public let message: String
    public var description: String { message }
}

/// trigger 수신기. throw 해도 다른 수신기 호출은 계속
public typealias TriggerListener = @MainActor (TriggerEvent) throws -> Void

/// 액션 실행 함수. 반환값이 invoke 결과 value
public typealias ActionRun = @MainActor ([String: JSONValue]) async throws -> JSONValue
/// confirm: true 액션 실행 전 호출. false · throw = DENIED
public typealias ConfirmHandler = @MainActor (ConfirmRequest) async throws -> Bool

/// 표시와 실행 함수를 함께 보관하는 레지스트리. 바인딩이 화면 생명주기에 맞춰 등록 · 해제
@MainActor
public final class AgentRuntime {
    private struct Slot<Extra> {
        let token: Int
        let extra: Extra
    }

    private var manifestStore = Manifest()
    private var runs: [String: Slot<ActionRun>] = [:]
    private var reads: [String: Slot<@MainActor () -> JSONValue?>] = [:]
    private var viewTokens: [String: Slot<Void>] = [:]
    private var listeners: [Int: @MainActor () -> Void] = [:]
    private var triggerListeners: [Int: TriggerListener] = [:]
    private var nextToken = 0
    private let confirm: ConfirmHandler?

    public init(confirm: ConfirmHandler? = nil) {
        self.confirm = confirm
    }

    private func token() -> Int {
        nextToken += 1
        return nextToken
    }

    private func notify() {
        for key in listeners.keys.sorted() { listeners[key]?() }
    }

    /// 해제 함수는 자기 등록만 지운다: 이미 해제됐거나 같은 이름이 재등록된 경우 무시
    @discardableResult
    public func action(_ name: String, _ def: ActionDef, run: @escaping ActionRun) throws(DuplicateNameError) -> @MainActor () -> Void {
        guard manifestStore.actions.append(name, def) else { throw DuplicateNameError(section: "actions", name: name) }
        let t = token()
        runs[name] = Slot(token: t, extra: run)
        notify()
        return { [weak self] in
            guard let self, self.runs[name]?.token == t else { return }
            self.runs[name] = nil
            self.manifestStore.actions.remove(name)
            self.notify()
        }
    }

    @discardableResult
    public func state(_ name: String, _ def: StateDef, read: @escaping @MainActor () -> JSONValue?) throws(DuplicateNameError) -> @MainActor () -> Void {
        guard manifestStore.state.append(name, def) else { throw DuplicateNameError(section: "state", name: name) }
        let t = token()
        reads[name] = Slot(token: t, extra: read)
        notify()
        return { [weak self] in
            guard let self, self.reads[name]?.token == t else { return }
            self.reads[name] = nil
            self.manifestStore.state.remove(name)
            self.notify()
        }
    }

    @discardableResult
    public func view(_ name: String, _ def: ViewDef) throws(DuplicateNameError) -> @MainActor () -> Void {
        guard manifestStore.views.append(name, def) else { throw DuplicateNameError(section: "views", name: name) }
        let t = token()
        viewTokens[name] = Slot(token: t, extra: ())
        notify()
        return { [weak self] in
            guard let self, self.viewTokens[name]?.token == t else { return }
            self.viewTokens[name] = nil
            self.manifestStore.views.remove(name)
            self.notify()
        }
    }

    /// 현재 등록 상태. 구역은 등록 순서
    public func manifest() -> Manifest { manifestStore }

    /// 호출 시점 값. 미등록 · 값 없음 = nil
    public func readState(_ name: String) -> JSONValue? { reads[name]?.extra() }

    /// 등록 · 해제마다 호출. 반환 함수로 구독 해제
    public func subscribe(_ listener: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let t = token()
        listeners[t] = listener
        return { [weak self] in self?.listeners[t] = nil }
    }

    /// 수신기마다 { name, payload } 를 등록 순서로 전달. 이름 위반 · payload 가 object 아님 = InvalidTriggerError
    public func trigger(_ name: String, payload: JSONValue = .object([:])) throws(InvalidTriggerError) {
        guard isValidName(name) else { throw InvalidTriggerError(message: "trigger 이름 규칙 위반: \(name)") }
        guard case .object(let fields) = payload else { throw InvalidTriggerError(message: "trigger payload 는 object") }
        let event = TriggerEvent(name: name, payload: fields)
        for key in triggerListeners.keys.sorted() {
            try? triggerListeners[key]?(event)
        }
    }

    /// trigger 수신기 등록. 반환 함수로 해제
    public func onTrigger(_ listener: @escaping TriggerListener) -> @MainActor () -> Void {
        let t = token()
        triggerListeners[t] = listener
        return { [weak self] in self?.triggerListeners[t] = nil }
    }

    /// 검사 순서 NOT_FOUND → INVALID_ARGS → DENIED → EXECUTION_ERROR
    public func invoke(_ name: String, args rawArgs: JSONValue = .object([:])) async -> InvokeResult {
        func fail(_ code: InvokeErrorCode, _ message: String) -> InvokeResult { .failure(InvokeError(code: code, message: message)) }
        guard let run = runs[name]?.extra, let def = manifestStore.actions[name] else {
            return fail(.notFound, "등록되지 않은 액션: \(name)")
        }
        guard case .object(let args) = rawArgs else { return fail(.invalidArgs, "args 는 object") }
        let missing = (def.input?["required"]?.arrayValue ?? []).compactMap(\.stringValue).filter { args[$0] == nil }
        if !missing.isEmpty { return fail(.invalidArgs, "필수 인자 누락: \(missing.joined(separator: ", "))") }
        if def.confirm == true {
            let approved = (try? await confirm?(ConfirmRequest(name: name, description: def.description, args: args))) ?? false
            if !approved { return fail(.denied, "사용자 승인 없음: \(name)") }
        }
        do {
            return .success(try await run(args))
        } catch {
            return fail(.executionError, "\(error)")
        }
    }
}
