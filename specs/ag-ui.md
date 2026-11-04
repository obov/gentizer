# ag-ui — AG-UI 전송 어댑터

core 런타임 (`specs/core.md` '런타임') 의 액션을 AG-UI frontend tool 로, 상태를 AG-UI context 로 보내고, 에이전트의 tool call 을 앱에서 실행한다.
패키지 `@gentizer/ag-ui` (`packages/ag-ui`). 의존성 `@gentizer/core`, peer `@ag-ui/client` 1.x.

## API

```text
toAgUiTools(manifest)               → Tool[]   액션마다 { name, description, parameters = input (생략 시 빈 object) }
toAgUiContext(runtime)              → Context[] 상태마다 { description: "<name>: <description>", value: JSON.stringify(readState(name)) }
                                                화면 (views) 이 있으면 끝에 하나 { description: "gentizer views: 현재 화면에 표시된 영역", value: JSON.stringify({ <name>: <description> }) }
runFrontendTools(runtime, messages) → ToolMessage[]
runWithFrontendTools(agent, runtime, options?) → { rounds, toolMessages }
toAgUiTriggerMessage(event)         → UserMessage  P2 trigger 를 user 메시지로
connectTriggers(agent, runtime, options?) → () => void  trigger 마다 메시지 추가 후 runWithFrontendTools. 반환 함수로 해제
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

P2 trigger (`specs/core.md` '런타임' trigger):

```text
메시지      { id: "gentizer-trigger-<uuid>", role: "user", content: JSON.stringify({ gentizer_trigger: { name, payload } }) }
connect     runtime.onTrigger 등록. trigger 마다 agent.addMessages([메시지]) → runWithFrontendTools(agent, runtime, options)
순서        실행 중 들어온 trigger 는 큐에 쌓아 앞 실행이 끝난 뒤 순서대로 (동시 runAgent 없음)
오류        runWithFrontendTools 실패는 options.onError(error, event). 다음 trigger 처리는 계속
해제        반환 함수. 큐에 남은 trigger 는 버리고, 진행 중 실행은 끝까지 둔다
```

- role 이 user 인 이유: AG-UI 에 앱 이벤트 메시지 형식이 없고, developer · system 은 대화 중간 메시지를 무시하는 에이전트가 있다
- content 는 JSON 문자열이라 에이전트가 키 `gentizer_trigger` 로 일반 채팅과 구분한다

agent-loader 연동은 어댑터 패키지가 아니라 L4 skill 로 한다. gentizer 와 agent-loader 는 서로 의존하지 않는다.

## Swift

target · product `GentizerAGUI` (`swift/Sources/GentizerAGUI`), 의존성 `Gentizer` 만. AG-UI Swift SDK 에 의존하지 않고 AG-UI 메시지 형태의 Codable 타입을 둔다.

```text
AGUITool · AGUIContext · AGUIMessage · AGUIToolCall   AG-UI JSON 과 같은 키 (camelCase)
toAGUITools(manifest) · toAGUIContext(runtime)        TS 와 같은 규칙
runFrontendTools(runtime, messages) async             TS 와 같은 규칙 (대상 · 파싱 · tool 메시지 형식 · 순서 실행)
AGUIAgent (protocol, @MainActor)                      messages · runAgent(params) async throws · addMessages(_:)
AGUIHTTPAgent(url:headers:threadId:session:)          AGUIAgent 구현. AG-UI HTTP 전송 (자체 최소 SSE 클라이언트)
runWithFrontendTools(agent, runtime, params, maxRounds: 5) async throws → AGUIRunResult { rounds, toolMessages }
```

- 문자열 JSON (`content` · context `value`) 은 키 정렬 직렬화
- views context · trigger 메시지 (`toAGUITriggerMessage` · `connectTriggers(agent, runtime, params, maxRounds:, onError:)`) 는 TS 와 같은 규칙
- conformance `ag-ui` suite 를 Swift 실행기에서도 통과
- `runWithFrontendTools` 반복 · 종료 · round 마다 tools · context 재계산 규칙은 TS 와 같다. `params.tools` · `params.context` 는 gentizer 것 뒤에 붙인다
- 클라이언트: 외부 SDK 없이 Foundation `URLSession` 으로 구현. 공식 커뮤니티 SDK (`ag-ui` 저장소 `sdks/community/swift`) 는 저장소 루트가 아니라 SwiftPM URL 설치 불가

`AGUIHTTPAgent` 전송:

```text
요청      POST url. Content-Type application/json · Accept text/event-stream · headers
본문      RunAgentInput { threadId, runId (매 run 새 UUID, params.runId 우선), state, messages, tools, context, forwardedProps }
응답      2xx 아님 → AGUIError.http(status). 본문은 SSE
SSE       줄 끝 \n · \r\n. data: 줄 (콜론 뒤 공백 하나 제거) 을 \n 으로 이어 빈 줄에서 이벤트 하나. 그 외 필드 · 주석 무시
이벤트    JSON 의 type 으로 분기. 모르는 type · 디코딩 실패 이벤트는 무시
```

이벤트 반영 (`@ag-ui/client` 1.0.3 기본 규칙과 같은 결과):

```text
TEXT_MESSAGE_START      id 가 없으면 { id: messageId, role (기본 assistant), content: "" } 추가
TEXT_MESSAGE_CONTENT    해당 메시지 content 에 delta 이어 붙임. 메시지 없으면 무시
TEXT_MESSAGE_CHUNK      messageId 가 새 id 면 START, delta 있으면 CONTENT. messageId 생략 = 직전 CHUNK 메시지
TOOL_CALL_START         같은 toolCallId 가 있으면 이름만 갱신. 없으면 parentMessageId 의 assistant 메시지에 추가
                        (parent 없음 · 생략 → 새 assistant 메시지 id = parentMessageId ?? toolCallId,
                         parent 가 assistant 아님 → 새 assistant 메시지 id = toolCallId)
TOOL_CALL_ARGS          해당 tool call arguments 에 delta 이어 붙임
TOOL_CALL_CHUNK         toolCallId 가 새 id 면 START, delta 있으면 ARGS. toolCallId 생략 = 직전 CHUNK tool call
TOOL_CALL_RESULT        같은 id · toolCallId 의 tool 메시지 교체. 없으면 그 tool call 을 가진 assistant 메시지 뒤
                        (이어진 tool 메시지들 다음) 에 삽입, assistant 도 없으면 끝에 추가
MESSAGES_SNAPSHOT       기존 메시지 중 snapshot 에 있는 id 만 snapshot 값으로 남기고, 새 id 를 snapshot 순서로 추가.
                        단 snapshot 에 activity 메시지가 없으면 기존 activity 를, reasoning 메시지가 없으면 기존 reasoning 을 유지
STATE_SNAPSHOT          state = snapshot
STATE_DELTA             state 에 delta (RFC 6902 JSON Patch) 적용. 실패하면 state 변화 없음 (op 일부만 적용하지 않음)
REASONING_MESSAGE_START id 가 없으면 { id: messageId, role: "reasoning", content: "" } 추가. 같은 id 가 activity 면 무시
REASONING_MESSAGE_CONTENT  해당 메시지 (activity 아님) content 에 delta 이어 붙임. 없으면 무시
REASONING_MESSAGE_CHUNK messageId 가 새 id 면 START, delta 있으면 CONTENT. messageId 생략 = 직전 CHUNK 메시지
REASONING_ENCRYPTED_VALUE  subtype tool-call → 그 tool call 의 encryptedValue, 그 외 → entityId 메시지 (activity 아님) 의 encryptedValue
ACTIVITY_SNAPSHOT       messageId 가 없으면 { id, role: "activity", activityType, content } 추가.
                        있으면 replace (기본 true) 일 때 activityType · content 교체 (activity 아닌 메시지는 activity 메시지로 교체)
ACTIVITY_DELTA          해당 activity 메시지 content 에 patch (JSON Patch) 적용. 실패 · 없음 · activity 아님 = 무시
RUN_ERROR               runAgent 가 AGUIError.run(message, code) 로 실패. 이전까지 반영한 메시지는 유지
TEXT_MESSAGE_END · TOOL_CALL_END · REASONING_START · REASONING_MESSAGE_END · REASONING_END
RUN_STARTED · RUN_FINISHED · STEP_* · RAW · CUSTOM   메시지 변화 없음
```

- `AGUIMessage` 의 JSON `content` 가 문자열이면 `content`, 그 외 (activity object · multimodal 배열) 면 `structuredContent`. 인코딩은 같은 `content` 키로 되돌린다. `activityType` · `encryptedValue` 필드 포함

실행 취소:

```text
abortRun()       진행 중 runAgent 의 요청을 취소. runAgent 는 CancellationError 로 끝난다
Task 취소        runAgent 를 실행 중인 Task 가 취소돼도 같다
반영             취소 전까지 반영한 메시지 · state 는 유지
```
