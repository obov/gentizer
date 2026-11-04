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
