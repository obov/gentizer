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

미구현: `callAgentFunction` (P2 이벤트형) · DataModel 동기화 · 전송 (L1).

## Swift 의존성

A2UI Swift (`A2UISwiftUI` · `A2UISwiftCore`) 는 fork `https://github.com/obov/a2ui` 의 순수 semver 태그로 의존한다.

```text
이유      upstream a2ui-project/a2ui 태그는 접두 형식 (python/a2ui-core/v0.5.0) 이라 SwiftPM 버전으로 못 씀.
          branch 의존은 버전으로 설치되는 gentizer-swift 에 넣을 수 없음 (SwiftPM 규칙)
태그      0.1.0 = upstream main 43696ef (2026-11-04). upstream 갱신 시 fork 동기화 후 다음 버전 태그
변경      fork 에 코드 수정 없음 (태그만). Apache-2.0 LICENSE 유지
플랫폼    A2UI Swift 하한 iOS 17 · macOS 14 (gentizer Swift core 는 iOS 16 · macOS 13)
```

- 하한 iOS 17 · macOS 14 가 필요한 것은 surface 렌더링 (`A2UISwiftUI`). RPC 브리지는 A2UI Swift 에 의존하지 않는다 (아래 'Swift')
- 미결: surface 렌더링 위치 (Gentizer 하한 상향 · 별도 패키지). 렌더링 작업 착수 때 결정
- upstream 이 SwiftPM 용 semver 태그를 붙이면 fork 대신 upstream 으로 전환

## Swift

target · product `GentizerA2UI` (`swift/Sources/GentizerA2UI`), 의존성 `Gentizer` 만. 하한은 패키지와 같은 iOS 16 · macOS 13.
A2UI Swift `RPCHandler` 를 쓰지 않는다: 함수 실행이 동기라 async `runtime.invoke` (confirm 대기) 를 못 부르고, 실행 오류 message 를 고정 문구로 바꿔 `DENIED: …` 접두를 잃는다.

```text
A2UICallRendererFunctionMessage · A2UIRendererFunctionResponseMessage   A2UI v1.0 JSON 과 같은 키 (Codable)
A2UIBridge(runtime, catalogId:)      @MainActor
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
- `surfaceId` 있는 메시지는 surface 가 없으므로 INVALID_FUNCTION_CALL "Surface not found: <id>" (TS 와 같음)
- 인자 검증은 runtime 규칙 (object · required) 까지. 그 외 JSON Schema 검증 (타입 · enum 등) 미구현
- conformance `a2ui` suite 를 Swift 실행기에서도 통과
