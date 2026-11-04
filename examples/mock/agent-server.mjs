// mock AG-UI agent. POST /agent (RunAgentInput) → SSE 로 AG-UI 이벤트
// 마지막 메시지가 user  → frontend tool 호출 (TOOL_CALL_*) 또는 안내 텍스트
// 마지막 메시지가 tool  → 실행 결과를 요약한 텍스트
// 마지막 메시지가 trigger (content 의 gentizer_trigger) → "앱 이벤트 수신" 텍스트
import { createServer } from "node:http";
import { decide, HELP } from "./intent.mjs";

const PORT = Number(process.env.AGENT_PORT ?? 8782);
let seq = 0;
const id = (p) => `${p}-${Date.now().toString(36)}-${++seq}`;

function textEvents(text) {
  const messageId = id("msg");
  return [
    { type: "TEXT_MESSAGE_START", messageId, role: "assistant" },
    { type: "TEXT_MESSAGE_CONTENT", messageId, delta: text },
    { type: "TEXT_MESSAGE_END", messageId },
  ];
}

function parseTrigger(text) {
  try {
    return JSON.parse(text)?.gentizer_trigger ?? null;
  } catch {
    return null;
  }
}

function respond(input) {
  const last = input.messages.at(-1);
  const tools = (input.tools ?? []).map((t) => t.name);

  if (last?.role === "tool") {
    const r = JSON.parse(last.content);
    return textEvents(r?.error ? `실행 실패 (${r.error.code}): ${r.error.message}` : `실행 완료: ${JSON.stringify(r)}`);
  }

  const text = typeof last?.content === "string" ? last.content : "";
  const trigger = parseTrigger(text);
  if (trigger) return textEvents(`앱 이벤트 수신: ${trigger.name} ${JSON.stringify(trigger.payload)}`);
  const call = decide(text, tools);
  if (!call) return textEvents(`이해하지 못함. 사용 가능 도구: ${tools.join(", ") || "없음"}. ${HELP}`);

  const toolCallId = id("call");
  const parentMessageId = id("msg");
  return [
    ...textEvents(`${call.name} 호출`),
    { type: "TOOL_CALL_START", toolCallId, toolCallName: call.name, parentMessageId },
    { type: "TOOL_CALL_ARGS", toolCallId, delta: JSON.stringify(call.args) },
    { type: "TOOL_CALL_END", toolCallId },
  ];
}

createServer(async (req, res) => {
  if (req.method !== "POST" || req.url !== "/agent") {
    res.writeHead(404).end();
    return;
  }
  let body = "";
  for await (const chunk of req) body += chunk;
  const input = JSON.parse(body);
  console.log(`[agent] run ${input.runId} · messages ${input.messages.length} · tools ${input.tools.map((t) => t.name).join(",")}`);

  res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive" });
  const events = [
    { type: "RUN_STARTED", threadId: input.threadId, runId: input.runId },
    ...respond(input),
    { type: "RUN_FINISHED", threadId: input.threadId, runId: input.runId },
  ];
  for (const e of events) res.write(`data: ${JSON.stringify(e)}\n\n`);
  res.end();
}).listen(PORT, () => console.log(`[agent] mock AG-UI agent http://localhost:${PORT}/agent`));
