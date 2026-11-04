# examples/swift — macOS SwiftUI 미니 상점 + mock 에이전트 2개

웹 예시 (`examples/web`) 와 같은 상점에 gentizer Swift 표시를 붙였다. LLM 없음: mock 이 키워드로 판단 (`examples/mock`).

```sh
npm start -w @gentizer/example-mock          # 저장소 루트, mock 두 개 (:8782 · :8781)
npm run dev -w @gentizer/example-swift       # = swift run --package-path examples/swift/ShopExample
```

오른쪽 채팅에서 에이전트 선택 후 입력: `신발만 보여줘` · `2번 담아줘` · `장바구니 비워줘` (승인 창) · `추천` (A2UI, ProductCard surface)
`저장` 버튼 = P2 trigger (AG-UI 에이전트가 "앱 이벤트 수신" 으로 답함)

| gentizer 사용 | 위치 |
|---|---|
| `.agentAction` · `.agentState` · `.agentView` | `ShopView` (filter_set · cart_add · cart_clear confirm · filter · cart) |
| `AgentConfirmation` · `.agentConfirmation` | `Agents` · `ShopApp` |
| `AGUIHTTPAgent` · `runWithFrontendTools` · `connectTriggers` | `Agents.sendAGUI` · `Agents.init` |
| `A2UISurfaceHost` · `A2UIAppComponent` · `A2UISurfaceView` | `Agents.init` · `Agents.connectA2UI` · `ChatView` |

- Package.swift 는 `ShopExample/` 아래: 예시 폴더 이름 `swift` 가 저장소 `swift/` 패키지 identity 와 겹치지 않게
- 포트 변경: `AGENT_PORT` · `A2UI_PORT`
- 실행 확인만: `npm run smoke -w @gentizer/example-swift` (5초 뒤 상태 출력 후 종료)
