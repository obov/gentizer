import Combine
import Gentizer
import SwiftUI

private struct AgentRuntimeKey: EnvironmentKey {
    static let defaultValue: AgentRuntime? = nil
}

extension EnvironmentValues {
    /// 하위 뷰가 쓸 런타임. .agentRuntime(_:) 로 제공
    public var agentRuntime: AgentRuntime? {
        get { self[AgentRuntimeKey.self] }
        set { self[AgentRuntimeKey.self] = newValue }
    }
}

private struct RegistrationKey: Equatable {
    let runtime: ObjectIdentifier?
    let name: String
    let kind: AgentRegistration.Kind
}

private struct AgentRegistrationModifier: ViewModifier {
    @Environment(\.agentRuntime) private var runtime
    @State private var registration = AgentRegistration()
    let name: String
    let kind: AgentRegistration.Kind
    let run: ActionRun?
    let read: (@MainActor () -> JSONValue?)?

    func body(content: Content) -> some View {
        // 최신 body 의 클로저 · 값을 등록 객체에 반영 (재등록 없음)
        if let run { registration.run = run }
        if let read { registration.read = read }
        let key = RegistrationKey(runtime: runtime.map(ObjectIdentifier.init), name: name, kind: kind)
        return content
            .onAppear { registration.update(runtime: runtime, name: name, kind: kind) }
            .onDisappear { registration.unregister() }
            .onChange(of: key) { _ in
                registration.update(runtime: runtime, name: name, kind: kind)
            }
    }
}

extension View {
    /// 하위 뷰에 런타임 제공
    public func agentRuntime(_ runtime: AgentRuntime) -> some View {
        environment(\.agentRuntime, runtime)
    }

    /// 이 뷰가 화면에 있는 동안 액션 등록. 실행은 최신 body 의 클로저
    public func agentAction(_ name: String, _ def: ActionDef, run: @escaping ActionRun) -> some View {
        modifier(AgentRegistrationModifier(name: name, kind: .action(def), run: run, read: nil))
    }

    /// 이 뷰가 화면에 있는 동안 상태 등록. readState 는 최신 body 의 value (JSON 변환 실패 = nil)
    public func agentState<Value: Encodable>(_ name: String, _ def: StateDef, value: Value) -> some View {
        modifier(AgentRegistrationModifier(name: name, kind: .state(def), run: nil, read: { try? JSONValue(encoding: value) }))
    }

    /// 이 뷰가 화면에 있는 동안 화면 영역 등록
    public func agentView(_ name: String, _ def: ViewDef) -> some View {
        modifier(AgentRegistrationModifier(name: name, kind: .view(def), run: nil, read: nil))
    }
}

/// 런타임 manifest 를 publish. 등록 · 해제마다 갱신
@MainActor
public final class AgentManifestModel: ObservableObject {
    @Published public private(set) var manifest: Manifest
    private var unsubscribe: (@MainActor () -> Void)?

    public init(runtime: AgentRuntime) {
        manifest = runtime.manifest()
        unsubscribe = runtime.subscribe { [weak self, weak runtime] in
            guard let self, let runtime else { return }
            self.manifest = runtime.manifest()
        }
    }

    /// 구독 해제. 이후 갱신 없음 (해제하지 않아도 모델이 사라지면 콜백은 아무것도 하지 않는다)
    public func stop() {
        unsubscribe?()
        unsubscribe = nil
    }
}
