# examples/web — HTML 미니 상점 + mock 에이전트 2개

기존 앱 (상품 목록 · 필터 · 장바구니) 에 gentizer 표시를 붙이고, 두 mock 에이전트로 조작한다. LLM 없음: 키워드로 액션을 고른다 (`mock/intent.mjs`).

```sh
npm install                      # 저장소 루트에서 한 번
npm run dev -w @gentizer/example-web
```

http://localhost:5173 → 오른쪽 채팅에서 에이전트 선택 후 입력: `신발만 보여줘` · `2번 담아줘` · `장바구니 비워줘` (승인 창)

| 구성 | 포트 | 역할 |
|---|---|---|
| `index.html` · `src/main.js` | 5173 (vite) | 앱 + `createAgentRuntime` 표시 + 두 에이전트 연결. `/agent` · `/a2ui` 는 vite 가 mock 으로 프록시 |
| `mock/agent-server.mjs` | 8782 | AG-UI agent. `POST /agent` → SSE 이벤트 (tool call · text) |
| `mock/a2ui-server.mjs` | 8781 | A2UI v1.0 agent. catalog 수신, SSE 로 `callRendererFunction` 전송, `rendererFunctionResponse` 수신 |

흐름:

```text
AG-UI  입력 → HttpAgent.runAgent (tools = 등록 액션, context = 상태) → TOOL_CALL → runtime.invoke → tool 메시지 → 다시 run → 결과 text
A2UI   로드 시 catalog POST → 입력 POST /a2ui/chat → SSE callRendererFunction → bridge.handle → 응답 POST /a2ui/response
```

- `npm run dev` 는 먼저 `packages/*` 를 빌드 (`predev`)
- mock 만 따로: `npm run agent -w @gentizer/example-web` · `npm run a2ui -w @gentizer/example-web`
- 포트 변경: `AGENT_PORT` · `A2UI_PORT` 환경 변수
