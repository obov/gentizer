# core — L2 manifest 와 A2UI v1.0 매핑

앱이 표시한 액션 · 상태 · 화면을 플랫폼 독립 manifest 하나로 모으고, A2UI v1.0 catalog 로 변환한다.
패키지 `@gentizer/core` (`packages/core`). 런타임 의존성 없음.

## manifest

```text
version   "gentizer/0.1"
actions   이름 → { description, input (JSON Schema object), confirm?, returns? }
state     이름 → { description, schema? (JSON Schema) }
views     이름 → { description }
```

- 이름 규칙: 소문자 영숫자 · `.` · `_` · `-`, 점으로 구분된 segment, 첫 글자 영문 (예: `cart.add`, `filter.set`)
- `input` 생략 시 인자 없는 object (`{ type: "object", properties: {} }`)
- `input` 최상위 `type` 은 `"object"` 만 허용
- `returns` 생략 시 `"void"`. 허용값: `string` · `number` · `boolean` · `array` · `object` · `any` · `void`
- 같은 이름 중복 등록은 오류 (액션 · 상태 · 화면 각각 안에서). `createManifestBuilder()` 가 등록 시점에 `DuplicateNameError`

## 검증

`validateManifest(m)` → `{ ok: true } | { ok: false, errors: [{ path, message }] }`.
위 규칙 위반을 모두 수집하고, 첫 오류에서 멈추지 않는다.

## A2UI v1.0 변환

`toA2uiCatalog(m, { catalogId })` → A2UI v1.0 catalog 정의 (`protocolVersion: "1.0"` · `catalogId` · `functions` · `metadata`?). 잘못된 manifest 는 `InvalidManifestError`

| manifest | A2UI v1.0 function 정의 |
|---|---|
| action 이름 | `properties["@call"].const` |
| `description` | `description` |
| `input` | `properties.args`, `required: ["@call"]` (input 의 required 가 있으면 `"args"` 추가) |
| `returns` | `returnType` |
| 항상 | `allowedCallers: "agentOnly"` (D2: 표시한 것만 에이전트가 호출, 렌더러 식 바인딩에서 호출 불가) |
| `confirm: true` | function 정의에는 표시 없음. catalog `metadata.extensions.gentizer.confirm` 배열에 이름 추가 |

- `requiresUserActivation` 미사용: v1.0 은 `requiresUserActivation: true` 를 `allowedCallers: "rendererOnly"` 에만 허용 (에이전트 호출 불가)
- function 정의는 `unevaluatedProperties: false` 라 확장 키 불가 → 승인 대상 목록은 catalog 단위 extension
- 승인 전 실행 차단은 런타임 (아래 '런타임'), 승인 카드 표시는 바인딩 책임
- confirm 액션이 없으면 `metadata` 생략

state · views 는 catalog 에 들어가지 않는다. 미구현: DataModel 동기화 (state) · 화면 맥락 확장 (views).

## 런타임

`createAgentRuntime({ confirm? })` → 표시와 실행 함수를 함께 보관하는 플랫폼 독립 레지스트리. 바인딩 (L3) 이 마운트 · 언마운트에 맞춰 등록 · 해제한다.

```text
action(name, def, run)   등록. 해제 함수 반환. 등록 중 같은 이름은 DuplicateNameError, 해제 뒤 재등록 허용
state(name, def, read)   등록. read() 가 현재 값
view(name, def)          등록
manifest()               현재 등록된 표시의 Manifest (등록 순서)
readState(name)          read() 결과. 미등록이면 undefined
subscribe(listener)      등록 · 해제마다 호출. 구독 해제 함수 반환
invoke(name, args?)      → { ok: true, value } | { ok: false, error: { code, message } }. reject 없음
```

invoke 순서와 오류 코드:

| 순서 | 조건 | code |
|---|---|---|
| 1 | 등록되지 않은 액션 (D2) | `NOT_FOUND` |
| 2 | args 가 object 아님 · `input.required` 키 누락 | `INVALID_ARGS` |
| 3 | `confirm: true` 이고 `confirm` 콜백이 없거나 false 반환 | `DENIED` |
| 4 | run 이 throw · reject | `EXECUTION_ERROR` |

- `args` 생략 시 `{}`. 값 검증은 object 여부 · required 키만 (JSON Schema 전체 검증 아님)
- `confirm` 콜백 인자 `{ name, description, args }`, 반환 `boolean | Promise<boolean>`
- `value` 는 run 반환값 (await), `undefined` 는 `null`

## A2UI 기반 확인 결과 (2026-11-04)

- `@a2ui/react` 0.15: 컴포넌트 API 는 `@a2ui/web_core/v0_9` 기반. v1.0 서브 export 없음
- `@a2ui/web_core` 0.15: `MessageProcessor` 가 v0.9 · v1.0 메시지 모두 처리, `RpcHandler.handleCallRendererFunction` 제공, `allowedCallers` · `requiresUserActivation` 검사
- → React 바인딩은 액션 실행을 `web_core` `RpcHandler` 로, surface 렌더링만 `@a2ui/react` 로
- `A2UISwiftUI` (a2ui main `43696ef`): `A2UICore` 에 v1.0 `RPCHandler` · `callRendererFunction` 테스트 존재. Swift 태그 없음 (D7 유지)
