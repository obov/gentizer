# gentizer — 기존 앱 UI를 에이전트가 제어하게 만드는 A2UI 바인딩 (기획)

상태: L2 core 구현. 바인딩 · 전송 없음. 2026-11-04 대화(agent-loader 세션 a7a2ce46)에서 정리한 내용.

## 목표

```text
앱 개발자가 기존 개발 방식을 크게 바꾸지 않고, 에이전트가 조작해도 되는 부분만 표시하면
그 표시가 에이전트 도구 · 상태 · 화면 맥락이 되는 오픈소스 라이브러리
```

- 특정 백엔드(agent-loader 포함)에 묶이지 않음. agent-loader는 전송 어댑터 중 하나
- 새 프로젝트마다 A2UI · AG-UI 같은 프로토콜을 따로 공부하지 않아도 됨
- "가능 여부"가 아니라 설치해서 바로 쓰는 수준
- 플랫폼: React · Next.js · Swift 우선, 이후 Vue · Kotlin · React Native · Flutter
- 라이선스: Apache-2.0 (A2UI와 동일)

## 제어 방식 2가지

```text
P1 채팅형      사용자가 채팅 → 에이전트가 앱 액션 호출 · 상태 변경
P2 이벤트형    채팅 없이 버튼 · 저장 같은 사용자 이벤트 → 에이전트 개입 → 화면 갱신
```

## 구조

```text
L4 skill       개발자의 코딩 에이전트(Claude Code · Codex)가 프로젝트를 훑고 표시를 추가
L3 binding     React · Next · Swift → Vue · Kotlin · RN · Flutter
               예: useAgentAction() · .agentAction() · @AgentState
L2 core        manifest: actions · state · views · catalog
               = A2UI v1.0 (renderer function · DataModel · surface)
L1 transport   AG-UI · MCP · WebSocket (agent-loader = 어댑터 1개)
```

### 앱 개발자가 추가하는 코드 (웹 예시, 초안)

```html
<button data-agent-action="cart.add" data-agent-desc="장바구니 담기" onclick="addToCart()">담기</button>
<input data-agent-field="search" placeholder="검색">
<section data-agent-view="cart">…</section>
```

```js
agent.expose("filter.set", {
  description: "목록 필터 변경",
  input: { type: "object", properties: { category: { type: "string" } } },
  run: (i) => setFilter(i.category),
})
agent.state("cart", () => store.cart)                                        // 에이전트가 읽을 상태
saveBtn.addEventListener("click", () => agent.trigger("form.saved", { id }))  // P2: 채팅 없이 개입
```

- 실제 DOM 이벤트(click · input)를 발생시켜 실행. React · Vue는 그 이벤트에 그대로 반응. React 제어 input 값 설정은 라이브러리가 처리
- `data-agent-confirm` 표시 동작은 실행 전 사용자 승인 카드

### 앱 표시 → A2UI v1.0 대응

| 앱에서 표시하는 것 | A2UI 기능 |
|---|---|
| 액션 (버튼 · 페이지 이동 · 폼 제출) | `callRendererFunction` (v1.0 신규, `allowedCallers` 권한 검사 · 사용자 조작 요구 옵션) |
| 앱 상태 | DataModel `{path}` 바인딩 · `updateDataModel` |
| 기존 컴포넌트 | 커스텀 catalog 등록 (Smart Wrapper 패턴) |
| 사용자 이벤트로 에이전트 호출 (P2) | `action` · `callAgentFunction` |
| 현재 화면 맥락 전달 | 스펙에 없음. 직접 확장 |
| 앱 상태 ↔ DataModel 자동 동기화 | 스펙에 없음 (a2ui #1852 open). 직접 구현 |

## 결정

| 코드 | 결정 | 내용 |
|---|---|---|
| D1 | 표시 방식 | HTML 속성(간단한 버튼 · 입력) + 코드 API(데이터가 필요한 동작) 둘 다 |
| D2 | 표시 안 한 요소 조작 | 금지. 표시한 것만 조작 가능 (앱이 권한 경계를 정함) |
| D3 | 생성형 UI | A2UI surface 사용으로 범위 포함 |
| D5 | 저장소 · 라이선스 | `~/Dev/gentizer` 독립 저장소, Apache-2.0 |
| D6 | 기준 A2UI 버전 | v1.0 RC (`callRendererFunction` 필요). v0.9 플랫폼은 상태 바인딩까지만 |
| D7 | Swift 기반 | 공식 `A2UISwiftUI` (branch 지정). 배포 태그 생기면 전환 |
| D8 | 첫 전송 어댑터 | AG-UI · agent-loader WebSocket |

D4(provider 순서: claude 먼저 · codex 2차)는 agent-loader 어댑터에만 해당.

## 플랫폼별 기반

| 플랫폼 | 기반 | 문제 · 대응 |
|---|---|---|
| React | `@a2ui/react` 0.15 | 0.x라 호환 깨짐 잦음 → 버전 고정 |
| Next.js | 같은 패키지 | SSR 버그(#3158 · #2080) open → `ssr:false` 래퍼 내장 |
| Swift | 공식 `A2UISwiftUI` | 배포 태그 없음 → SwiftPM branch 지정. 커뮤니티 BBC6BAE9/a2ui-swift는 v0.9.1까지 |
| Vue (2차) | 커뮤니티 `a2ui-vue` | |
| Kotlin (2차) | `androidx.a2ui` alpha | v0.9.1만 지원 → 앱 액션 호출 경로 없음 (R7) |
| RN (2차) | 커뮤니티 구현 1개 | 1인 유지 |
| Flutter (2차) | `a2ui_flutter` | wip |

> [!NOTE]
> 확인 결과 (2026-11-04): `@a2ui/react` 0.15 는 v0.9 컴포넌트 API, v1.0 RPC (`callRendererFunction`) 는 `@a2ui/web_core` 0.15 `RpcHandler` 에 있음.
> `A2UISwiftUI` 도 v1.0 `RPCHandler` 보유. 상세 `specs/core.md`

## 비슷한 프로젝트와 차이

같은 목표(기존 UI에 표시만 하면 도구가 되고, 백엔드 독립, 다중 플랫폼)의 오픈소스 없음.

| 프로젝트 | 차이 |
|---|---|
| CopilotKit (`useFrontendTool` · `useAgentContext`) | 웹 · RN만, AG-UI 런타임 필요. Swift · Kotlin · Flutter 없음 |
| WebMCP 계열 (`use-webmcp-tool` · `@mcp-b/react-webmcp`) | 웹 전용, 표준 실험 단계, MCP-B 폴리필 필요 |
| Tambo interactable | 가장 비슷한 패턴, 클라우드 종료(2026-10-31) |
| AG-UI Swift · Kotlin · Dart SDK | 프로토콜 클라이언트뿐, UI 연결 계층 없음 |
| Android AppFunctions · Apple Foundation Models `Tool` | 함수 단위 노출, Apple 쪽은 비공개 |

빈칸 (gentizer가 채울 부분):

- F1. SwiftUI · Compose · Flutter에서 기존 UI를 선언형으로 표시하는 계층
- F2. 7개 플랫폼을 하나의 스키마로 묶는 SDK
- F3. 웹에서 WebMCP · AG-UI 동시 노출 어댑터

도구 정의 형식: JSON Schema (WebMCP · MCP · AG-UI 공통).

## 위험

| 코드 | 위험 |
|---|---|
| R2 | 페이지 내용을 통한 prompt injection. `data-agent-view` 영역의 악성 지시문 → D2 · 승인 카드로 피해 범위 제한 |
| R6 | 핵심인 `callRendererFunction`이 v1.0 전용, v1.0 스펙은 RC |
| R7 | Android 공식 렌더러 v0.9.1만 지원 → Kotlin 앱 액션 호출 경로 막힘 |
| R8 | A2UI 렌더러 전반 0.x · preview → API 변경 시 바인딩 수정 필요 |

## 다음 단계

```text
1. (완료) @a2ui/react 0.15 · A2UISwiftUI 의 v1.0 지원 범위 확인
2. (완료) L2 core manifest 스키마 · 검증 · A2UI v1.0 catalog 변환 (`packages/core`)
3. React 바인딩 + Next.js ssr:false 래퍼
4. 전송 어댑터: AG-UI · agent-loader WebSocket
5. Swift 바인딩
6. L4 skill (대상 프로젝트에 표시 추가 자동화)
```

## 참고

- A2UI: https://github.com/a2ui-project/a2ui
- AG-UI: https://github.com/ag-ui-protocol/ag-ui
- CopilotKit: https://github.com/CopilotKit/CopilotKit
- MCP ext-apps: https://github.com/modelcontextprotocol/ext-apps
- json-render: https://github.com/vercel-labs/json-render
- agent-loader (첫 백엔드): `~/Dev/agent-loader`
