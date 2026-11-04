# a2ui — A2UI v1.0 RPC 브리지 (웹)

에이전트가 보낸 A2UI v1.0 `callRendererFunction` 메시지를 core 런타임 (`specs/core.md` '런타임') 의 `invoke` 로 실행한다.
패키지 `@gentizer/a2ui` (`packages/a2ui`). 의존성 `@gentizer/core` · `@a2ui/web_core` 0.15.0 고정 · `zod` 3.
React · Vue 등 웹 바인딩이 공유한다.

## API

```text
createA2uiBridge(runtime, { catalogId })
  catalog()          현재 등록된 액션의 A2UI v1.0 catalog (toA2uiCatalog). 에이전트에 보낼 정의
  handle(message)    callRendererFunction 메시지 → rendererFunctionResponse 메시지. reject 없음
  dispose()          runtime 구독 해제
```

- 실행 경로: `Catalog.fromJson(catalog())` 의 function 에 `execute = args → runtime.invoke(name, args)` 를 붙여 `@a2ui/web_core` `RpcHandler` 로 처리. 인자 JSON Schema 검증 · `allowedCallers` 검사는 `RpcHandler`
- 메시지의 `callFunction.catalogId` 생략 시 브리지 `catalogId` 로 채움. 다른 catalogId 는 `INVALID_FUNCTION_CALL`
- runtime 등록 · 해제 후 다음 `handle` 은 새 등록 상태로 실행 (해제된 액션 → `INVALID_FUNCTION_CALL`)
- `invoke` 실패는 `EXECUTION_ERROR`, message 앞에 runtime 오류 코드 (`DENIED: …`)
- 성공 `value` 는 `invoke` 의 value

## 웹 surface host

`createA2uiSurfaceHost(runtime, options)` → 에이전트 ↔ 렌더러 메시지 양방향 진입점. 화면 그리기는 바인딩 (`specs/react.md` 'surface').
`@a2ui/web_core` `MessageProcessor` (v1.0 basic catalog + `options.catalogs`) 와 위 브리지를 묶는다.

```text
options     catalogId · send(message) (렌더러 → 에이전트 메시지 하나) · catalogs? (추가 component catalog)
            stateSync? (기본 true) · triggerSurfaceId? (기본 "gentizer")
catalog()                           bridge.catalog()
process(message) → Promise<void>    에이전트 → 렌더러 메시지 하나. reject 없음
processor                           MessageProcessor (렌더러가 surface 를 얻는 곳)
surfaceIds() · subscribe(listener)  활성 surface id (정렬) · 생성 · 삭제 알림. subscribe 는 해제 함수 반환
callAgentFunction(surfaceId, call, { timeoutMs? }) → Promise<value>   P2. agentFunctionResponse 의 value 로 resolve, error 면 reject
dataModel()                         { version: "1.0", surfaces } (sendDataModel 인 surface 의 data model)
syncState()                         상태 · 화면을 모든 활성 surface data model 에 다시 쓴다
dispose()                           구독 해제 · 대기 중 callAgentFunction reject
```

`process` 분기:

```text
callRendererFunction        bridge.handle → send(rendererFunctionResponse)
createSurface · updateComponents · updateDataModel · deleteSurface · agentFunctionResponse   MessageProcessor
JSON 이 아니거나 처리 실패   send({ version: "1.0", error: { code, message, surfaceId? · path? · functionCallId? } })
```

렌더러 → 에이전트 (`send`):

```text
rendererFunctionResponse    위 process 분기
action                      surface 컴포넌트의 action (사용자 클릭 등). MessageProcessor action payload 그대로
callAgentFunction           host.callAgentFunction · surface 안의 에이전트 함수 호출
error                       process 분기의 처리 실패
trigger                     runtime trigger 마다 action 하나
                            { name, surfaceId: triggerSurfaceId, sourceComponentId: "gentizer", timestamp (ISO 8601), context: payload }
```

상태 · 화면 → DataModel (앱 → 에이전트 단방향):

```text
경로        /gentizer/state/<name> = readState(name) · /gentizer/views = { <name>: <description> }
            값 없음 · null 은 키 없음 (v1.0 data model 은 null 을 저장하지 않는다)
시점        surface 생성 직후 · runtime 등록 · 해제 알림 · process 처리 뒤 · syncState()
해제        등록 해제된 상태 키는 지운다
쓰기 방향   data model 의 /gentizer 를 surface (TextField 등) 가 바꿔도 앱 상태는 바뀌지 않는다. 앱 변경은 액션으로만 (D2)
stateSync   false 면 /gentizer 를 쓰지 않는다
```

- 전송 (L1) 은 앱이 고른다: `send` 로 내보내고 받은 메시지를 `process` 로 넣는다. A2UI 는 전송을 정하지 않는다 (A2A · SSE · WebSocket)
- React 값 변경은 runtime 알림이 없으므로 바인딩이 렌더마다 `syncState()` 를 부른다 (`specs/react.md`)

## Swift 의존성

A2UI Swift (`A2UISwiftUI` · `A2UISwiftCore`) 는 fork `https://github.com/obov/a2ui` 의 순수 semver 태그로 의존한다.

```text
이유      upstream a2ui-project/a2ui 태그는 접두 형식 (python/a2ui-core/v0.5.0) 이라 SwiftPM 버전으로 못 씀.
          branch 의존은 버전으로 설치되는 gentizer-swift 에 넣을 수 없음 (SwiftPM 규칙)
태그      0.1.0 = upstream main 43696ef (2026-11-04). upstream 갱신 시 fork 동기화 후 다음 버전 태그
변경      fork 에 코드 수정 없음 (태그만). Apache-2.0 LICENSE 유지
플랫폼    A2UI Swift 하한 iOS 17 · macOS 14 = gentizer Swift 패키지 하한
```

- surface 렌더링 위치: 패키지 하한을 iOS 17 · macOS 14 로 올리고 같은 패키지의 target 으로 둔다 (별도 패키지 아님). RPC 브리지는 A2UI Swift 에 의존하지 않는다 (아래 'Swift')
- upstream 이 SwiftPM 용 semver 태그를 붙이면 fork 대신 upstream 으로 전환

## Swift

target · product `GentizerA2UI` (`swift/Sources/GentizerA2UI`), 의존성 `Gentizer` 만. 하한은 패키지와 같은 iOS 17 · macOS 14.
A2UI Swift `RPCHandler` 를 쓰지 않는다: 함수 실행이 동기라 async `runtime.invoke` (confirm 대기) 를 못 부르고, 실행 오류 message 를 고정 문구로 바꿔 `DENIED: …` 접두를 잃는다.

```text
A2UICallRendererFunctionMessage · A2UIRendererFunctionResponseMessage   A2UI v1.0 JSON 과 같은 키 (Codable)
A2UIBridge(runtime, catalogId:, surfaceExists:)   @MainActor. surfaceExists 기본 nil (surface 없음)
  catalog() throws -> JSONValue      toA2uiCatalog(runtime.manifest(), catalogId:)
  handle(message) async -> response  throw 없음
```

`handle` 순서 (TS `RpcHandler` 와 같은 오류 코드):

```text
1  catalogId 생략 → 브리지 catalogId. 다른 catalogId → INVALID_FUNCTION_CALL "Catalog not found: <id>"
2  version 이 1.0 아님 → INVALID_FUNCTION_CALL
3  @call 이 현재 manifest 에 없음 → INVALID_FUNCTION_CALL "Function not found: <name>"
4  runtime.invoke(name, args ?? {})
   INVALID_ARGS → INVALID_FUNCTION_CALL "Invalid function arguments for '<name>': <message>"
   그 외 실패  → EXECUTION_ERROR "<code>: <message>"
   성공        → value
```

- 응답 `version` 은 메시지 `version`, `functionCallId` 는 메시지 값
- `surfaceId` 있는 메시지는 `surfaceExists(id)` 가 false (또는 nil) 이면 INVALID_FUNCTION_CALL "Surface not found: <id>" (TS 와 같음). true 면 surface 없는 메시지와 같은 경로
- 인자 검증은 runtime 규칙 (object · required) 까지. 그 외 JSON Schema 검증 (타입 · enum 등) 미구현
- conformance `a2ui` suite 를 Swift 실행기에서도 통과

## Swift surface 렌더링

target · product `GentizerA2UISwiftUI` (`swift/Sources/GentizerA2UISwiftUI`), 의존성 `GentizerA2UI` · A2UI Swift (`A2UISwiftCore` · `A2UISwiftUI` · `BasicCatalogSwiftUI`).
에이전트 → 렌더러 메시지 중 surface 메시지는 A2UI Swift `MessageProcessor` 로, `callRendererFunction` 은 `A2UIBridge` 로 보낸다.

```text
A2UISurfaceHost(runtime, catalogId:)   @MainActor ObservableObject. A2UIBridge 를 surfaceExists = 활성 surface 로 만든다
  catalog() throws -> JSONValue        bridge.catalog()
  process(message: JSONValue) async -> JSONValue?
                                       callRendererFunction → bridge.handle 응답 JSON
                                       그 외 (createSurface · updateComponents · updateDataModel · deleteSurface) → MessageProcessor, nil
  surfaceIDs: [String]                 활성 surface (id 정렬)
A2UISurfaceView(host:, surfaceID:)     SwiftUI. 활성 surface 면 A2UI Swift Surface (basic catalog v1.0), 없으면 EmptyView
```

앱 컴포넌트 catalog (Smart Wrapper): 앱의 기존 SwiftUI 뷰를 A2UI 컴포넌트로 감싸 에이전트 surface 에서 쓰게 한다.

```text
A2UIAppComponent(name, description:, properties: JSONValue = [:], required: [String] = []) { props in View }
    properties   JSON Schema properties (컴포넌트 속성). 스키마 = { type: object, description,
                 properties: { component: { const: name }, ...properties }, required: ["component", ...required] }
A2UIProp             속성 스키마 상수 string · number · bool (값 또는 data model 바인딩) · action · child
                     = A2UI v1.0 common_types $ref (https://a2ui.org/specification/v1_0/common_types.json#/$defs/…)
                     A2UI 는 $ref 이름으로 바인딩 · action · 자식을 구분한다 (평 JSON Schema 는 리터럴 값만)
A2UIComponentProps   id · string(_:) · double(_:) · bool(_:) (바인딩 해석 후 값) · child(_:) -> AnyView? · action(_:) -> (() -> Void)?
A2UISurfaceHost(..., components: [A2UIAppComponent] = [], componentCatalogId: String? = nil)
    componentCatalogId   기본 "<catalogId>#components". components 가 비면 app catalog 없음
    app catalog          v1.0, 앱 컴포넌트 + basic catalog 컴포넌트 (같은 이름은 앱 우선). basic catalog id 도 그대로 사용 가능
  componentCatalog() -> JSONValue?   에이전트에 보낼 정의 { catalogId, protocolVersion: "1.0", components: { <name>: 스키마 } } (앱 컴포넌트만). 없으면 nil
A2UISurfaceView      host 의 catalog (app · basic) 로 그린다
```

- 이름 규칙: A2UI 컴포넌트 이름 (`Surface` 금지). basic catalog 와 같은 이름이면 앱 것이 이긴다
- 웹은 `createA2uiSurfaceHost` 의 `catalogs` 에 web_core `Catalog` (React 는 `@a2ui/react` `createComponentImplementation`) 를 직접 넣는다

Swift 렌더러 → 에이전트 · 상태 동기화는 웹 surface host 와 같은 규칙:

```text
A2UISurfaceHost(runtime, catalogId:, stateSync: true, triggerSurfaceId: "gentizer", send:)
  send: @MainActor (JSONValue) -> Void         렌더러 → 에이전트 메시지 하나 (A2UI v1.0 JSON)
  process(message:) async                      callRendererFunction 응답도 send 로 (반환값 없음)
  callAgentFunction(surfaceID:, name:, args:, timeoutSeconds:) async throws -> JSONValue
  dataModel() -> JSONValue · syncState() · dispose()
```

- action · error · callAgentFunction 은 A2UI Swift `MessageProcessor.outboundListener` 를 JSON 으로 바꿔 send
- trigger action · `/gentizer/state` · `/gentizer/views` 경로 · 시점은 웹과 같다
