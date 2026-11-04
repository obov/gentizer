# swiftui — SwiftUI 바인딩

SwiftUI 뷰가 화면에 있는 동안 액션 · 상태 · 화면을 Swift core 런타임 (`specs/swift.md` 'core API') 에 등록한다.
target · product `GentizerSwiftUI` (`swift/Sources/GentizerSwiftUI`), 의존성 `Gentizer` · SwiftUI. 플랫폼은 `Gentizer` 와 같음 (iOS 17 · macOS 14).

## API

```text
.agentRuntime(runtime)                   하위 뷰가 쓸 AgentRuntime 을 environment 로 제공
@Environment(\.agentRuntime)             AgentRuntime? (제공 없으면 nil)
.agentAction(name, def) { args in … }    화면에 있는 동안 액션 등록. 실행은 최신 body 의 클로저
.agentState(name, def, value:)           화면에 있는 동안 상태 등록. value: Encodable, readState 는 최신 body 의 값
.agentView(name, def)                    화면에 있는 동안 화면 영역 등록
AgentManifestModel(runtime)              ObservableObject. manifest 를 @Published 로, 등록 · 해제마다 갱신
```

- 등록 시점: `onAppear`. 해제: `onDisappear`
- `name` 또는 `def` 가 바뀌면 이전 등록 해제 후 재등록. 실행 클로저 · value 만 바뀌면 재등록 없음
- runtime 이 없는 (environment 미제공) 뷰는 등록하지 않는다
- 같은 구역 같은 이름이 이미 있으면 등록하지 않고 `os.Logger` fault 로 남긴다 (body 에서 throw 불가)
- value 를 JSON 으로 바꾸지 못하면 readState = nil

## 승인 (confirm UI)

`confirm: true` 액션 실행 전 사용자 승인 카드 (README '앱 개발자가 추가하는 코드' data-agent-confirm 과 같은 역할).

```text
AgentConfirmation()                      @MainActor ObservableObject
  request: ConfirmRequest?               @Published. 지금 묻는 요청 (없으면 nil)
  confirm(_:) async -> Bool              AgentRuntime(confirm: confirmation.confirm) 로 연결
  approve() · deny()                     지금 요청에 답. 다음 대기 요청이 있으면 request 로
.agentConfirmation(confirmation)         request 가 있는 동안 alert. 제목 "에이전트 실행 승인", 메시지 = description + args JSON,
                                         버튼 "승인" (approve) · "거절" (deny, cancel 역할)
```

- 동시에 들어온 요청은 큐에 쌓아 한 번에 하나씩 묻는다 (들어온 순서)
- confirm 을 기다리는 Task 가 취소되면 그 요청은 거절로 끝나고 큐에서 빠진다
- alert 를 다른 방법으로 닫으면 (시스템 dismiss) 거절
