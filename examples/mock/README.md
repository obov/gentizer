# examples/mock — 모든 예시가 공유하는 mock 에이전트

LLM 없이 키워드로 액션을 고르는 두 서버 (`intent.mjs` 의 `decide`).

| 파일 | 포트 | 프로토콜 |
|---|---|---|
| `agent-server.mjs` | 8782 (`AGENT_PORT`) | AG-UI. `POST /agent` → SSE. trigger 메시지 (`gentizer_trigger`) 에는 "앱 이벤트 수신" 텍스트 |
| `a2ui-server.mjs` | 8781 (`A2UI_PORT`) | A2UI v1.0. catalog · 앱 컴포넌트 catalog (`POST /a2ui/components`) · SSE callRendererFunction · "추천" → ProductCard surface · 렌더러 메시지 수신 |

```sh
npm start -w @gentizer/example-mock
```
