# HTML · 바닐라 JS

## 속성 (코드 없이)

```html
<button data-agent-action="cart_clear" data-agent-desc="장바구니 비우기" data-agent-confirm>비우기</button>
<input data-agent-field="search" data-agent-desc="상품 검색어">
<select data-agent-field="category" data-agent-desc="분류 필터"><option value="all">전체</option></select>
<section data-agent-view="cart" data-agent-desc="장바구니">…</section>
```

- `data-agent-action` = 실제 click (form 이면 submit). `data-agent-field` = 상태 `<name>` + 액션 `<name>_set` (input · change 이벤트 발생)
- `data-agent-desc` 없으면 등록되지 않는다

```js
import { createAgentRuntime, validateManifest } from "@gentizer/core";
import { bindAgentAttributes } from "@gentizer/dom";

const runtime = createAgentRuntime({ confirm: ({ name, args }) => window.confirm(`${name} ${JSON.stringify(args)} 실행?`) });
bindAgentAttributes(runtime, document.body);
console.log(validateManifest(runtime.manifest()));
```

## 코드 API (인자 · 반환값이 필요할 때)

```js
runtime.action("cart_add", {
  description: "상품을 장바구니에 담기. 반환: 장바구니 개수",
  input: { type: "object", properties: { id: { type: "number" } }, required: ["id"] },
  returns: "number",
}, (a) => addToCart(a.id));
runtime.state("cart", { description: "장바구니 상품 목록" }, () => store.cart);
saveButton.addEventListener("click", () => runtime.trigger("form_saved", { id }));   // P2: 채팅 없이 에이전트에 알림
```

## 전송

```js
// AG-UI
import { HttpAgent } from "@ag-ui/client";
import { connectTriggers, runWithFrontendTools } from "@gentizer/ag-ui";
const agent = new HttpAgent({ url: "/agent" });
agent.addMessage({ id: crypto.randomUUID(), role: "user", content: text });
await runWithFrontendTools(agent, runtime);
connectTriggers(agent, runtime);

// A2UI (전송은 앱이 고른다: SSE · WebSocket · A2A)
import { createA2uiSurfaceHost } from "@gentizer/a2ui";
const host = createA2uiSurfaceHost(runtime, { catalogId, send: (m) => postToAgent(m) });
postToAgent(host.catalog());
onAgentMessage((m) => host.process(m));
```
