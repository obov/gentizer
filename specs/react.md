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
useAgentAttributes(rootRef?)    마운트 동안 data-agent-* 속성 바인딩 (`specs/dom.md` bindAgentAttributes). rootRef 생략 = document.body
```

- 등록 시점: effect (커밋 후). 언마운트 시 해제
- `name` 또는 `def` 내용이 바뀌면 이전 등록 해제 후 재등록. `def` 는 내용 비교 (JSON 직렬화), 매 렌더 새 object 여도 재등록 없음
- `run` · `value` 만 바뀌면 재등록 없음
- StrictMode 이중 마운트에서 DuplicateNameError 없음
- `useAgentManifest` 는 변경이 없으면 같은 object 반환
- Next.js: 배포 entry 첫 줄 `"use client"`. 서버 렌더 중 등록 없음 (effect 미실행)

- A2UI `callRendererFunction` 실행은 `@gentizer/a2ui` (`specs/a2ui.md`). React 전용 연결 없음
- `useAgentAttributes` 의 rootRef 가 바뀌면 이전 바인딩 해제 후 다시 바인딩. 서버 렌더 중 바인딩 없음

## surface

에이전트가 만든 A2UI surface 를 React 로 그린다. 패키지 `@gentizer/react-a2ui` (`packages/react-a2ui`).
의존성 `@gentizer/react` · `@gentizer/a2ui` · `@a2ui/react` 0.15.0 고정 · `@a2ui/web_core` 0.15.0, peer `react` · `react-dom` >= 18.

```text
useA2uiSurfaceHost(options) → A2uiSurfaceHost | null
    options = createA2uiSurfaceHost 옵션 (catalogId · send · catalogs? · stateSync? · triggerSurfaceId?)
    Provider runtime 으로 마운트 후 생성 (서버 렌더 · 첫 렌더는 null), 언마운트 시 dispose
    send 는 최신 렌더의 함수. catalogId · stateSync · triggerSurfaceId 가 바뀌면 다시 생성
    커밋마다 host.syncState() (React 상태 값 변경을 /gentizer/state 에 반영)
useA2uiSurfaceIds(host) → string[]    활성 surface id. 생성 · 삭제 시 다시 렌더. host null 이면 []
<A2uiSurfaceView host surfaceId fallback? />   @a2ui/react A2uiSurface 로 그림. 없는 surface 면 fallback (기본 null)
```

Next.js `ssr:false` 대응 (README 'Next.js' SSR 버그):

- `A2uiSurfaceView` 는 마운트 후 `@a2ui/react` 를 동적 import 해서 그린다. 서버 · 첫 렌더는 fallback. `next/dynamic` 없이 같은 효과 (Next.js 의존 없음)
- 배포 entry 첫 줄 `"use client"`
- `@a2ui/web_core` 는 한 벌만 설치돼야 한다 (`@a2ui/react` 와 같은 버전). 두 벌이면 custom element 이름 충돌. 저장소는 루트 `overrides` 로 고정
