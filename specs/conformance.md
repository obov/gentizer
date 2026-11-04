# conformance — 언어 공통 동작 케이스

모든 언어 구현 (TS · Swift · 이후 Dart · Kotlin) 이 같은 입력에 같은 결과를 내는지 확인하는 언어 중립 케이스.
위치 `conformance/` (저장소 루트). 기준 구현은 TS: 케이스는 TS 실행기로 먼저 통과시킨다.

## 저장소 배치

```text
/package.json                    npm workspaces 루트
/packages/<pkg>/                 npm 패키지. 단위 테스트는 test/
/swift/                          Swift 패키지 (Package.swift 포함). 배포 저장소 gentizer-swift 로 export (specs/swift.md)
/dart/  /kotlin/                 언어별 구현. 단위 테스트는 각 언어 관례 위치
/conformance/<suite>/*.json      공통 케이스
/examples/mock/                  mock 에이전트 (모든 예시 공유)
/examples/<platform>/            같은 미니 상점 UI
```

- 단위 테스트: 언어 고유 동작만 (React hooks 생명주기, web_core 파싱 등)
- 공통 동작 테스트는 conformance 케이스로만 둔다 (언어별 중복 금지)
- 폴더 구조 검사: `.gnam/layout.json` (gnam layout)

## 케이스 파일

파일 하나 = `{ "suite": "<suite>", "cases": [ { "name": "...", ... } ] }`. 케이스 id = `<suite>/<파일명>#<name>`.
형식은 `conformance/schema.json` (JSON Schema). JSON 만 사용 (YAML 불가: 언어 기본 내장 파서만으로 읽기).

비교 규칙 (모든 suite):

- object 키 순서 무시. 배열 순서는 비교 (명시한 예외 제외)
- 오류는 code · 경로만 비교, message 는 비교하지 않음 (언어 · 로캘 자유)
- JSON 문자열로 나오는 값 (tool 메시지 content) 은 파싱 후 비교

## suite

| suite | 입력 | 기대 |
|---|---|---|
| `validate` | `manifest` (임의 JSON) | `ok: true` 또는 `errorPaths` (순서 무시) |
| `catalog` | `manifest` · `catalogId` | `catalog` (A2UI v1.0 catalog 전체) 또는 `error: "INVALID_MANIFEST"` |
| `runtime` | `confirm` · `steps` | step 마다 기대값 |
| `ag-ui` | `actions` · `states` · 동작 | `tools` · `context` · `toolMessages` |
| `a2ui` | `actions` · `catalogId` · `message` | `value` 또는 `errorCode` |

### 액션 · 상태 선언 (runtime · ag-ui · a2ui 공통)

실행 코드 대신 데이터로 선언하고, 언어별 실행기가 실제 함수로 바꿔 등록한다.

```text
action  { "name", "def": ActionDef, "behavior": { "returns": <JSON> } | { "throws": "<message>" } | { "echoArgs": true } }
state   { "name", "def": StateDef, "value": <JSON> }   value 생략 = 값 없음 (TS undefined · Swift nil)
confirm "approve" | "deny" | "throw" | "absent"        runtime 생성 옵션. absent = 콜백 없음
```

- `echoArgs`: 받은 args 를 그대로 반환

### runtime steps

```text
{ "op": "register", "kind": "action|state|view", "name", "def", "behavior"?, "value"?, "handle"?: "<id>", "expectError"?: "DUPLICATE_NAME" }
{ "op": "unregister", "handle": "<id>" }                     같은 handle 두 번 호출 허용
{ "op": "invoke", "name", "args"?, "expect": { "ok": true, "value" } | { "ok": false, "code" }, "expectConfirm"?: { "name", "description", "args" } | null }
{ "op": "manifest", "expect": Manifest, "expectOrder"?: { "actions"?: [..], "state"?: [..], "views"?: [..] } }
{ "op": "readState", "name", "expect": <JSON> | null }
```

- `args` 생략 = 인자 없이 호출. `"args": <JSON>` 은 그 값 그대로 (배열 · 문자열 포함)
- `expectConfirm: null` = confirm 콜백 미호출
- 등록 순서는 `expectOrder` 로만 비교 (Manifest 비교는 키 순서 무시)

### ag-ui

```text
{ "actions", "states"?, "op": "tools", "expect": [Tool] }                        배열 순서 = 등록 순서
{ "actions", "states"?, "op": "context", "expect": [Context] }                   value 는 파싱 후 비교
{ "actions", "confirm"?, "op": "runFrontendTools", "messages": [Message], "expect": [{ "toolCallId", "content": <JSON>, "errorCode"? }] }
```

- `errorCode` 있으면 tool 메시지 `error` 가 `"<code>: "` 로 시작, 없으면 `error` 없음
- 실패 content 는 `{ "error": { "code" } }` 로 비교 (`error.message` 제외)
- tool 메시지 `id` 는 `"gentizer-<toolCallId>"` (실행기가 고정 검사)

### a2ui

```text
{ "actions", "confirm"?, "catalogId", "message": CallRendererFunctionMessage,
  "expect": { "value": <JSON> } | { "errorCode": "INVALID_FUNCTION_CALL|EXECUTION_ERROR", "messagePrefix"? } }
```

## 실행기

- 언어마다 하나씩, 각 언어 테스트 명령 (`npm run check` · `swift test`) 에 포함
- `skip` 목록: 케이스 id 와 이유. 미구현 suite 는 suite 단위 skip 허용
- 케이스 파일이 없거나 형식 위반 (schema.json) 이면 실패
- Swift 실행기 위치: `swift/Tests/GentizerConformanceTests/` (현재 전체 suite skip)
- TS 실행기 위치: `packages/core/test/conformance.test.ts` (validate · catalog · runtime), `packages/ag-ui/test/conformance.test.ts`, `packages/a2ui/test/conformance.test.ts`
