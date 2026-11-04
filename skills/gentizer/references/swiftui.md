# SwiftUI

## runtime · 승인

```swift
import Gentizer
import GentizerSwiftUI

@MainActor final class AgentSetup: ObservableObject {
    let confirmation = AgentConfirmation()
    lazy var runtime = AgentRuntime(confirm: { [confirmation] in await confirmation.confirm($0) })
}

// 앱 루트
ContentView()
    .agentRuntime(setup.runtime)
    .agentConfirmation(setup.confirmation)
```

## 뷰 표시

```swift
List(store.visible) { p in Row(p) }
    .agentAction("cart_add", ActionDef(description: "상품을 장바구니에 담기. 반환: 장바구니 개수",
                                       input: ["type": "object", "properties": ["id": ["type": "number"]], "required": ["id"]],
                                       returns: .number)) { args in
        guard case .number(let id)? = args["id"] else { throw ShopError.invalid }
        return .number(Double(try store.add(Int(id))))
    }
    .agentState("cart", StateDef(description: "장바구니 상품 목록"), value: store.cart)
    .agentView("product_list", ViewDef(description: "상품 목록"))

Button("비우기") { store.clear() }
    .agentAction("cart_clear", ActionDef(description: "장바구니 비우기", confirm: true)) { _ in
        store.clear()
        return .null
    }

Button("저장") { try? runtime.trigger("cart_saved", payload: ["count": .number(Double(store.cart.count))]) }
```

- 화면에 있는 동안만 등록 (onAppear · onDisappear). value 는 Encodable
- 검증: `validateManifest(runtime.manifest().json) == .ok`

## AG-UI

```swift
import GentizerAGUI

let agent = AGUIHTTPAgent(url: URL(string: "https://agent.example/agent")!)
agent.addMessages([AGUIMessage(id: UUID().uuidString, role: "user", content: text)])
_ = try await runWithFrontendTools(agent, runtime)
let off = connectTriggers(agent, runtime)
```

## A2UI surface · 앱 컴포넌트

```swift
import GentizerA2UISwiftUI

let card = A2UIAppComponent("ProductCard", description: "상품 카드",
                            properties: ["name": A2UIProp.string, "price": A2UIProp.number, "action": A2UIProp.action],
                            required: ["name"]) { props in
    ProductCard(name: props.string("name") ?? "", price: props.double("price"), onAdd: props.action("action"))
}
let host = try A2UISurfaceHost(runtime, catalogId: catalogURL, components: [card]) { message in sendToAgent(message) }
sendToAgent(try host.catalog())
if let components = host.componentCatalog() { sendToAgent(components) }
await host.process(message: incoming)

ForEach(host.surfaceIDs, id: \.self) { A2UISurfaceView(host: host, surfaceID: $0) }
```

- 앱 컴포넌트 속성은 `A2UIProp` 상수 (바인딩 · action · 자식은 이것만 동작)
- `host.dispose()` 로 runtime 구독 해제
