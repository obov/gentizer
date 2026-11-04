import A2UICore
import BasicCatalog
import Combine
import Foundation
import OrderedJSON
import GentizerA2UI
import class Gentizer.AgentRuntime
import struct Gentizer.TriggerEvent

/// 이 파일에서 JSONValue = A2UI Swift 쪽 (OrderedJSON). Gentizer 쪽은 GentizerJSONValue
typealias A2UIJSONValue = JSONValue

/// 렌더러 → 에이전트 메시지 하나 (A2UI v1.0 JSON)
public typealias A2UISend = @MainActor (GentizerJSONValue) -> Void

/// 에이전트 ↔ 렌더러 메시지 진입점 (specs/a2ui.md 'Swift surface 렌더링')
/// callRendererFunction → A2UIBridge, 그 외 → A2UI Swift MessageProcessor. 렌더러 → 에이전트 메시지는 send
@MainActor
public final class A2UISurfaceHost: ObservableObject {
    public private(set) var bridge: A2UIBridge!
    let processor: MessageProcessor
    private let runtime: AgentRuntime
    private let send: A2UISend
    private let stateSync: Bool
    private let triggerSurfaceId: String
    private var forward: AnyCancellable?
    private var offRuntime: (@MainActor () -> Void)?
    private var offTrigger: (@MainActor () -> Void)?
    /// surface 별로 지난번에 쓴 상태 이름. 해제된 이름을 지우는 데 쓴다
    private var written: [String: Set<String>] = [:]

    public init(_ runtime: AgentRuntime, catalogId: String, stateSync: Bool = true,
                triggerSurfaceId: String = "gentizer", send: @escaping A2UISend = { _ in }) {
        self.runtime = runtime
        self.send = send
        self.stateSync = stateSync
        self.triggerSurfaceId = triggerSurfaceId
        processor = MessageProcessor(catalogs: BasicCatalog.allCatalogs)
        bridge = A2UIBridge(runtime, catalogId: catalogId) { [weak self] id in
            self?.processor.surfaceGroupModel[id] != nil
        }
        forward = processor.surfaceGroupModel.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        processor.outboundListener = { [weak self] message in
            guard let json = convert(message, to: GentizerJSONValue.self) else { return }
            Task { @MainActor in self?.send(json) }
        }
        offRuntime = runtime.subscribe { [weak self] in self?.syncState() }
        offTrigger = runtime.onTrigger { [weak self] event in self?.sendTrigger(event) }
    }

    /// runtime 구독 (등록 변경 · trigger) 해제. 해제 전에 host 가 사라지면 구독은 아무 일도 하지 않고 남는다
    public func dispose() {
        offRuntime?()
        offTrigger?()
        offRuntime = nil
        offTrigger = nil
    }

    /// 현재 등록된 액션의 A2UI v1.0 catalog
    public func catalog() throws -> GentizerJSONValue { try bridge.catalog() }

    /// 활성 surface id (정렬)
    public var surfaceIDs: [String] { processor.surfaceGroupModel.surfacesMap.keys.sorted() }

    /// 에이전트 → 렌더러 메시지 하나. callRendererFunction 응답 · 처리 오류는 send
    public func process(message: GentizerJSONValue) async {
        if case .object(let o) = message, o["callRendererFunction"] != nil,
           let call = try? message.decode(as: A2UICallRendererFunctionMessage.self) {
            let response = await bridge.handle(call)
            if let json = try? GentizerJSONValue(encoding: response) { send(json) }
            return
        }
        if let payload = convert(message, to: A2UIJSONValue.self) {
            // 오류는 outboundListener 로 나간다
            processor.process(payload: payload)
        }
        syncState()
    }

    /// P2. agentFunctionResponse 의 value 로 끝나고, error · 시간 초과면 throw
    public func callAgentFunction(surfaceID: String, name: String, args: [String: GentizerJSONValue]? = nil,
                                  timeoutSeconds: TimeInterval = 30) async throws -> GentizerJSONValue {
        let converted = args.flatMap { convert($0, to: [String: A2UIJSONValue].self) }
        let value = try await processor.callAgentFunction(surfaceID: surfaceID, functionName: name, args: converted,
                                                         version: .v10, timeoutSeconds: timeoutSeconds)
        return convert(value, to: GentizerJSONValue.self) ?? .null
    }

    /// { version: "1.0", surfaces } (sendDataModel 인 surface 의 data model)
    public func dataModel() -> GentizerJSONValue {
        let raw = (try? processor.getRendererDataModel(version: .v10)).flatMap { convert($0, to: GentizerJSONValue.self) }
        return ["version": "1.0", "surfaces": raw?["surfaces"] ?? [:]]
    }

    /// 상태 · 화면을 모든 활성 surface 의 /gentizer 에 다시 쓴다
    public func syncState() {
        guard stateSync else { return }
        let manifest = runtime.manifest()
        let names = Set(manifest.state.names)
        let views = GentizerJSONValue.object(Dictionary(manifest.views.map { ($0.name, GentizerJSONValue.string($0.def.description)) },
                                                        uniquingKeysWith: { first, _ in first }))
        let alive = Set(processor.surfaceGroupModel.surfacesMap.keys)
        written = written.filter { alive.contains($0.key) }
        for (id, surface) in processor.surfaceGroupModel.surfacesMap {
            for old in written[id] ?? [] where !names.contains(old) {
                surface.dataModel.set("/gentizer/state/\(escape(old))", value: nil)
            }
            for name in names {
                let value = convert(runtime.readState(name) ?? .null, to: A2UIJSONValue.self) ?? .null
                surface.dataModel.set("/gentizer/state/\(escape(name))", value: value)
            }
            written[id] = names
            surface.dataModel.set("/gentizer/views", value: convert(views, to: A2UIJSONValue.self))
        }
    }

    private func sendTrigger(_ event: TriggerEvent) {
        let timestamp = ISO8601DateFormatter.withFraction.string(from: Date())
        send(["version": "1.0", "action": [
            "name": .string(event.name),
            "surfaceId": .string(triggerSurfaceId),
            "sourceComponentId": "gentizer",
            "timestamp": .string(timestamp),
            "context": .object(event.payload),
        ]])
    }

    func surface(_ id: String) -> SurfaceViewModel? { processor.surfaceGroupModel[id] }
}

/// 같은 JSON 을 다른 Codable 타입으로 (Gentizer JSONValue ↔ A2UI JSONValue · 메시지)
private func convert<T: Decodable>(_ value: some Encodable, to: T.Type) -> T? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}

/// JSON Pointer 토큰 이스케이프
private func escape(_ s: String) -> String {
    s.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
}

extension ISO8601DateFormatter {
    fileprivate static var withFraction: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }
}
