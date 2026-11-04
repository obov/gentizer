# examples/mock — 모든 예시가 공유하는 mock 에이전트

LLM 없이 키워드로 액션을 고르는 두 서버 (`intent.mjs` 의 `decide`).

| 파일 | 포트 | 프로토콜 |
|---|---|---|
| `agent-server.mjs` | 8782 (`AGENT_PORT`) | AG-UI. `POST /agent` → SSE |
| `a2ui-server.mjs` | 8781 (`A2UI_PORT`) | A2UI v1.0. catalog · SSE callRendererFunction · 응답 |

```sh
npm start -w @gentizer/example-mock
```
