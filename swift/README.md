# gentizer-swift

기존 SwiftUI 앱에서 에이전트가 조작해도 되는 부분만 표시하면, 그 표시가 에이전트 도구 · 상태 · 화면 맥락이 되는 라이브러리.
개발 저장소 `obov/gentizer` 의 `swift/` 를 내보낸 배포 저장소. 이슈 · PR 은 개발 저장소로.

```swift
.package(url: "https://github.com/obov/gentizer-swift.git", from: "0.1.0")
```

플랫폼 iOS 17 · macOS 14 이상, swift-tools-version 6.0.

| product | 역할 |
|---|---|
| `Gentizer` | manifest · 검증 · A2UI v1.0 catalog 변환 · `AgentRuntime` (액션 실행 · 상태 · trigger) |
| `GentizerSwiftUI` | `.agentAction` · `.agentState` · `.agentView` 수정자, 승인 alert `.agentConfirmation` |
| `GentizerAGUI` | AG-UI 전송 (`AGUIHTTPAgent` · `runWithFrontendTools` · `connectTriggers`) |
| `GentizerA2UI` | A2UI v1.0 `callRendererFunction` → 액션 실행 브리지 |
| `GentizerA2UISwiftUI` | 에이전트가 만든 A2UI surface 렌더링 · 앱 컴포넌트 catalog |

```swift
import Gentizer
import GentizerAGUI
import GentizerSwiftUI
import SwiftUI

@MainActor let confirmation = AgentConfirmation()
@MainActor let runtime = AgentRuntime(confirm: { await confirmation.confirm($0) })

struct CartView: View {
    @State var items: [String] = []

    var body: some View {
        List(items, id: \.self) { Text($0) }
            .agentAction("cart_clear", ActionDef(description: "장바구니 비우기", confirm: true)) { _ in
                items = []
                return .null
            }
            .agentState("cart", StateDef(description: "장바구니 상품"), value: items)
            .agentRuntime(runtime)
            .agentConfirmation(confirmation)
    }
}

// AG-UI 에이전트에 연결: 등록한 액션이 frontend tool, 상태가 context
let agent = AGUIHTTPAgent(url: URL(string: "https://agent.example/agent")!)
_ = try await runWithFrontendTools(agent, runtime)
```

- 표시하지 않은 것은 에이전트가 조작할 수 없다. `confirm: true` 액션은 사용자 승인 후에만 실행
- 언어 공통 동작은 `Tests/Conformance` 케이스로 TS 구현과 같은 결과를 검사
- 라이선스 Apache-2.0 (`LICENSE`)
