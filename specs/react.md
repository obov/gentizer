# react — React · Next.js 바인딩

React 컴포넌트가 마운트 동안 액션 · 상태 · 화면을 `@gentizer/core` 런타임 (`specs/core.md` '런타임') 에 등록한다.
패키지 `@gentizer/react` (`packages/react`). peer `react` >= 18, 의존성 `@gentizer/core`.

## API

```text
<GentizerProvider runtime>      하위 트리가 쓸 AgentRuntime 제공
useAgentRuntime()               Provider 의 runtime. Provider 밖이면 Error
useAgentAction(name, def, run)  마운트 동안 액션 등록. run 은 최신 렌더의 함수로 실행
useAgentState(name, def, value) 마운트 동안 상태 등록. readState 는 최신 렌더의 value
useAgentView(name, def)         마운트 동안 화면 등록
useAgentManifest()              현재 manifest. 등록 · 해제 시 다시 렌더
```

- 등록 시점: effect (커밋 후). 언마운트 시 해제
- `name` 또는 `def` 내용이 바뀌면 이전 등록 해제 후 재등록. `def` 는 내용 비교 (JSON 직렬화), 매 렌더 새 object 여도 재등록 없음
- `run` · `value` 만 바뀌면 재등록 없음
- StrictMode 이중 마운트에서 DuplicateNameError 없음
- `useAgentManifest` 는 변경이 없으면 같은 object 반환
- Next.js: 배포 entry 첫 줄 `"use client"`. 서버 렌더 중 등록 없음 (effect 미실행)

미구현: A2UI `callRendererFunction` 메시지 → `runtime.invoke` 연결 (`@a2ui/web_core` `RpcHandler`) · `data-agent-*` HTML 속성 · surface 렌더링과 Next.js `ssr:false` 래퍼.
