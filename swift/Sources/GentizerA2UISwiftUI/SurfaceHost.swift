import A2UICore
import BasicCatalog
import Combine
import Foundation
import GentizerA2UI
import class Gentizer.AgentRuntime

/// 에이전트 → 렌더러 메시지 진입점 (specs/a2ui.md 'Swift surface 렌더링')
/// callRendererFunction → A2UIBridge, surface 메시지 → A2UI Swift MessageProcessor
@MainActor
public final class A2UISurfaceHost: ObservableObject {
    public private(set) var bridge: A2UIBridge!
    let processor: MessageProcessor
    private let parser = MessageParser()
    private var forward: AnyCancellable?

    public init(_ runtime: AgentRuntime, catalogId: String) {
        processor = MessageProcessor(catalogs: BasicCatalog.allCatalogs)
        bridge = A2UIBridge(runtime, catalogId: catalogId) { [weak self] id in
            self?.processor.surfaceGroupModel[id] != nil
        }
        forward = processor.surfaceGroupModel.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// 현재 등록된 액션의 A2UI v1.0 catalog
    public func catalog() throws -> GentizerJSONValue { try bridge.catalog() }

    /// 활성 surface id (정렬)
    public var surfaceIDs: [String] { processor.surfaceGroupModel.surfacesMap.keys.sorted() }

    /// callRendererFunction 이면 응답 JSON, 그 외 nil. 처리 오류는 A2UI Swift 규칙대로 (전송 미구현)
    public func process(message: GentizerJSONValue) async -> GentizerJSONValue? {
        if case .object(let o) = message, o["callRendererFunction"] != nil,
           let call = try? message.decode(as: A2UICallRendererFunctionMessage.self) {
            let response = await bridge.handle(call)
            return try? GentizerJSONValue(encoding: response)
        }
        guard let data = try? JSONEncoder().encode(message),
              let parsed = try? parser.decode(jsonData: data) else { return nil }
        processor.process(message: parsed)
        return nil
    }

    func surface(_ id: String) -> SurfaceViewModel? { processor.surfaceGroupModel[id] }
}
