# ag-ui — AG-UI 전송 어댑터

core 런타임 (`specs/core.md` '런타임') 의 액션을 AG-UI frontend tool 로, 상태를 AG-UI context 로 보내고, 에이전트의 tool call 을 앱에서 실행한다.
패키지 `@gentizer/ag-ui` (`packages/ag-ui`). 의존성 `@gentizer/core`, peer `@ag-ui/client` 1.x.

## API

```text
toAgUiTools(manifest)               → Tool[]   액션마다 { name, description, parameters = input (생략 시 빈 object) }
toAgUiContext(runtime)              → Context[] 상태마다 { description: "<name>: <description>", value: JSON.stringify(readState(name)) }
runFrontendTools(runtime, messages) → ToolMessage[]
runWithFrontendTools(agent, runtime, options?) → { rounds, toolMessages }
```

`runFrontendTools`:

- 대상: assistant 메시지의 `toolCalls` 중 같은 `toolCallId` 의 tool 메시지가 없고, 이름이 runtime 에 등록된 것. 미등록 이름은 무시 (다른 처리기 몫)
- `function.arguments` 를 JSON 파싱해 `runtime.invoke`. 파싱 실패 · object 아님은 실행 없이 `INVALID_ARGS`
- 결과 tool 메시지: `{ id: "gentizer-<toolCallId>", role: "tool", toolCallId, content }`
  - 성공 `content = JSON.stringify(value)`
  - 실패 `content = JSON.stringify({ error: { code, message } })`, `error = "<code>: <message>"`
- toolCalls 순서대로 하나씩 실행 (동시 실행 없음)

`runWithFrontendTools(agent, runtime, { maxRounds = 5, ...RunAgentParameters })`:

```text
반복  agent.runAgent({ ...params, tools: toAgUiTools(현재 manifest) + params.tools, context: toAgUiContext + params.context })
      → runFrontendTools(runtime, agent.messages)
      → 결과 없으면 종료. 있으면 agent.addMessages 후 다음 round
종료  결과 없음 · rounds = maxRounds
```

- 매 round 마다 tools · context 를 다시 계산 (실행으로 등록 · 상태가 바뀔 수 있음)

미구현: P2 이벤트형 `trigger`.

agent-loader 연동은 어댑터 패키지가 아니라 L4 skill 로 한다. gentizer 와 agent-loader 는 서로 의존하지 않는다.

## Swift

target · product `GentizerAGUI` (`swift/Sources/GentizerAGUI`), 의존성 `Gentizer` 만. AG-UI Swift SDK 에 의존하지 않고 AG-UI 메시지 형태의 Codable 타입을 둔다.

```text
AGUITool · AGUIContext · AGUIMessage · AGUIToolCall   AG-UI JSON 과 같은 키 (camelCase)
toAGUITools(manifest) · toAGUIContext(runtime)        TS 와 같은 규칙
runFrontendTools(runtime, messages) async             TS 와 같은 규칙 (대상 · 파싱 · tool 메시지 형식 · 순서 실행)
```

- 문자열 JSON (`content` · context `value`) 은 키 정렬 직렬화
- conformance `ag-ui` suite 를 Swift 실행기에서도 통과
- 미구현: `runWithFrontendTools` (에이전트 연결). AG-UI Swift 클라이언트 선택 (README Q3) 후
