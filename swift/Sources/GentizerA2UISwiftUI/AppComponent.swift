import A2UICore
import A2UIJSON
import A2UISwiftUI
import BasicCatalogSwiftUI
import Foundation
import JSONSchema
import OrderedJSON
import SwiftUI

/// 앱의 기존 SwiftUI 뷰를 A2UI 컴포넌트로 감싼다 (specs/a2ui.md '앱 컴포넌트 catalog')
public struct A2UIAppComponent: @unchecked Sendable {
    public let name: String
    public let description: String
    /// A2UI 컴포넌트 스키마 (component const · required 포함)
    public let schema: GentizerJSONValue
    let build: @MainActor (A2UIComponentProps) -> AnyView

    public init<Content: View>(_ name: String, description: String, properties: GentizerJSONValue? = nil,
                               required: [String] = [],
                               @ViewBuilder view: @escaping @MainActor (A2UIComponentProps) -> Content) {
        self.name = name
        self.description = description
        var props = properties?.objectValue ?? [:]
        props["component"] = ["const": .string(name)]
        schema = [
            "type": "object",
            "description": .string(description),
            "properties": .object(props),
            "required": .array((["component"] + required).map(GentizerJSONValue.string)),
        ]
        build = { AnyView(view($0)) }
    }

    func implementation() throws -> ComponentImplementation {
        let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(schema))
        let build = self.build
        // A2UI 공통 타입 ($ref DynamicString · Action 등) 을 해석하는 context
        let compiled = try Schema(rawSchema: raw, context: A2UISchemaRegistry.makeContext())
        return ComponentImplementation(name: name, schema: compiled) { node in
            build(A2UIComponentProps(node: node))
        }
    }
}

/// 앱 컴포넌트 속성 스키마. A2UI 는 $ref 이름으로 바인딩 · action · 자식을 구분한다
public enum A2UIProp {
    /// 문자열 또는 data model 바인딩 ({ path })
    public static let string: GentizerJSONValue = ["$ref": "https://a2ui.org/specification/v1_0/common_types.json#/$defs/DynamicString"]
    public static let number: GentizerJSONValue = ["$ref": "https://a2ui.org/specification/v1_0/common_types.json#/$defs/DynamicNumber"]
    public static let bool: GentizerJSONValue = ["$ref": "https://a2ui.org/specification/v1_0/common_types.json#/$defs/DynamicBoolean"]
    /// 사용자 조작 → 에이전트 action ({ event: { name, context } })
    public static let action: GentizerJSONValue = ["$ref": "https://a2ui.org/specification/v1_0/common_types.json#/$defs/Action"]
    /// 자식 컴포넌트 id
    public static let child: GentizerJSONValue = ["$ref": "https://a2ui.org/specification/v1_0/common_types.json#/$defs/ComponentId"]
}

/// 바인딩 해석이 끝난 컴포넌트 속성
@MainActor
public struct A2UIComponentProps {
    let node: Node

    public var id: String { node.id }
    public func string(_ key: String) -> String? { node.string(for: key) }
    public func double(_ key: String) -> Double? { node.double(for: key) }
    public func bool(_ key: String) -> Bool? { node.bool(for: key) }

    /// 자식 컴포넌트 (ComponentId 속성) 를 그린 뷰
    public func child(_ key: String) -> AnyView? {
        node.child(for: key).map { AnyView(ComponentNodeView(node: $0)) }
    }

    /// action 속성 실행 함수. 실행하면 렌더러 → 에이전트 action 메시지가 나간다
    public func action(_ key: String) -> (() -> Void)? {
        guard let action = node.action(for: key) else { return nil }
        return { action() }
    }
}

/// 앱 컴포넌트 + basic catalog 컴포넌트 (같은 이름은 앱 우선) 를 가진 v1.0 catalog
@MainActor
func makeAppCatalog(id: String, components: [A2UIAppComponent]) throws -> Catalog<ComponentImplementation> {
    let app = try components.map { try $0.implementation() }
    let names = Set(app.map(\.name))
    let basic = BasicCatalogImplementation.makeCatalog(version: .v10)
    return Catalog(
        id: id,
        protocolVersion: .v10,
        components: app + basic.components.values.filter { !names.contains($0.name) },
        functions: Array(basic.functions.values),
        themeSchema: nil
    )
}
