import Gentizer
import os

private let logger = Logger(subsystem: "gentizer", category: "swiftui")

/// 뷰 하나의 등록 상태. 수정자가 body 마다 update, 사라질 때 unregister 를 부른다
@MainActor
public final class AgentRegistration {
    public enum Kind: Equatable {
        case action(ActionDef)
        case state(StateDef)
        case view(ViewDef)
    }

    private struct Key: Equatable {
        let runtime: ObjectIdentifier
        let name: String
        let kind: Kind
    }

    private var key: Key?
    private var off: (@MainActor () -> Void)?

    /// 최신 body 의 실행 함수 · 값 읽기. 등록된 클로저가 이 속성을 거쳐 부른다
    public var run: ActionRun = { _ in .null }
    public var read: @MainActor () -> JSONValue? = { nil }

    public init() {}

    public var isRegistered: Bool { off != nil }

    /// runtime · name · kind 가 같으면 아무것도 하지 않음 (멱등). 다르면 이전 등록 해제 후 재등록
    public func update(runtime: AgentRuntime?, name: String, kind: Kind) {
        guard let runtime else {
            unregister()
            return
        }
        let next = Key(runtime: ObjectIdentifier(runtime), name: name, kind: kind)
        if next == key, off != nil { return }
        unregister()
        do {
            switch kind {
            case .action(let def):
                off = try runtime.action(name, def) { [weak self] args in
                    guard let self else { return .null }
                    return try await self.run(args)
                }
            case .state(let def):
                off = try runtime.state(name, def) { [weak self] in self?.read() }
            case .view(let def):
                off = try runtime.view(name, def)
            }
            key = next
        } catch {
            logger.fault("gentizer 등록 무시: \(String(describing: error), privacy: .public)")
        }
    }

    public func unregister() {
        off?()
        off = nil
        key = nil
    }
}
