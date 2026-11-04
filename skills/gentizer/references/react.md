# React · Next.js

## Provider

```tsx
import { createAgentRuntime } from "@gentizer/core";
import { GentizerProvider } from "@gentizer/react";

const runtime = createAgentRuntime({ confirm: ({ name }) => window.confirm(`${name} 실행?`) });

export function App() {
  return <GentizerProvider runtime={runtime}><Shop /></GentizerProvider>;
}
```

- Next.js: runtime · Provider 는 `"use client"` 파일에. 서버 컴포넌트에서 hook 을 쓰지 않는다

## 컴포넌트 안 표시

```tsx
import { useAgentAction, useAgentAttributes, useAgentState, useAgentView } from "@gentizer/react";

function Cart({ items, add, clear }: Props) {
  useAgentAction("cart_add", {
    description: "상품을 장바구니에 담기. 반환: 장바구니 개수",
    input: { type: "object", properties: { id: { type: "number" } }, required: ["id"] },
    returns: "number",
  }, (a) => add(a.id as number));
  useAgentAction("cart_clear", { description: "장바구니 비우기", confirm: true }, () => clear());
  useAgentState("cart", { description: "장바구니 상품 목록" }, items);
  useAgentView("cart", { description: "장바구니" });
  return <ul>…</ul>;
}
```

- 마운트 동안만 등록. `def` 는 내용 비교라 매 렌더 새 object 여도 된다
- 간단한 버튼은 JSX 에 `data-agent-action` · `data-agent-desc` 를 쓰고 앱 루트에서 `useAgentAttributes()` 한 번

```tsx
function Root() {
  useAgentAttributes();
  return <button data-agent-action="checkout_open" data-agent-desc="결제 화면 열기" onClick={open}>결제</button>;
}
```

## 에이전트가 만든 화면 (A2UI surface)

```tsx
import { A2uiSurfaceView, useA2uiSurfaceHost, useA2uiSurfaceIds } from "@gentizer/react-a2ui";

function AgentPanel() {
  const host = useA2uiSurfaceHost({ catalogId, send: (m) => socket.send(JSON.stringify(m)) });
  const ids = useA2uiSurfaceIds(host);
  useEffect(() => {
    if (!host) return;
    socket.onmessage = (e) => host.process(JSON.parse(e.data));
  }, [host]);
  return <>{ids.map((id) => <A2uiSurfaceView key={id} host={host} surfaceId={id} />)}</>;
}
```

- `@a2ui/web_core` 는 한 벌만 설치 (`npm ls @a2ui/web_core`). 두 벌이면 package.json `overrides` 로 고정
- Next.js: `A2uiSurfaceView` 는 마운트 후에만 `@a2ui/react` 를 불러와 SSR 오류가 없다 (`next/dynamic` 불필요)

## AG-UI

```tsx
import { HttpAgent } from "@ag-ui/client";
import { runWithFrontendTools } from "@gentizer/ag-ui";
import { useAgentRuntime } from "@gentizer/react";

const runtime = useAgentRuntime();
await runWithFrontendTools(agent, runtime);
```
