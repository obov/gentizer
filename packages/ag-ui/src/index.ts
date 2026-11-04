import type { AbstractAgent, Context, Message, RunAgentParameters, Tool, ToolMessage, UserMessage } from "@ag-ui/client";
import type { AgentRuntime, InvokeResult, Manifest, TriggerEvent } from "@gentizer/core";

const EMPTY_INPUT = { type: "object", properties: {} };

/** 액션마다 AG-UI frontend tool 하나 */
export function toAgUiTools(manifest: Manifest): Tool[] {
  return Object.entries(manifest.actions).map(([name, def]) => ({
    name,
    description: def.description,
    parameters: structuredClone(def.input ?? EMPTY_INPUT),
  }));
}

export const VIEWS_CONTEXT_DESCRIPTION = "gentizer views: 현재 화면에 표시된 영역";

/** 상태마다 context 하나 (value 는 현재 값의 JSON). 화면이 있으면 끝에 views context 하나 */
export function toAgUiContext(runtime: AgentRuntime): Context[] {
  const manifest = runtime.manifest();
  const out: Context[] = Object.entries(manifest.state).map(([name, def]) => ({
    description: `${name}: ${def.description}`,
    value: JSON.stringify(runtime.readState(name) ?? null),
  }));
  const views = Object.entries(manifest.views);
  if (views.length > 0) {
    out.push({
      description: VIEWS_CONTEXT_DESCRIPTION,
      value: JSON.stringify(Object.fromEntries(views.map(([name, def]) => [name, def.description]))),
    });
  }
  return out;
}

/** P2 trigger → user 메시지. content 의 gentizer_trigger 키로 일반 채팅과 구분 */
export function toAgUiTriggerMessage(event: TriggerEvent): UserMessage {
  return {
    id: `gentizer-trigger-${crypto.randomUUID()}`,
    role: "user",
    content: JSON.stringify({ gentizer_trigger: { name: event.name, payload: event.payload } }),
  };
}

export interface ConnectTriggersOptions extends RunWithFrontendToolsOptions {
  onError?: (error: unknown, event: TriggerEvent) => void;
}

/** trigger 마다 메시지 추가 → runWithFrontendTools. 한 번에 하나씩 순서대로. 반환 함수로 해제 (대기 중 trigger 버림) */
export function connectTriggers(agent: AbstractAgent, runtime: AgentRuntime, options: ConnectTriggersOptions = {}): () => void {
  const { onError, ...runOptions } = options;
  const queue: TriggerEvent[] = [];
  let running = false;
  let connected = true;

  async function drain() {
    if (running) return;
    running = true;
    try {
      while (connected && queue.length > 0) {
        const event = queue.shift()!;
        try {
          agent.addMessages([toAgUiTriggerMessage(event)]);
          await runWithFrontendTools(agent, runtime, runOptions);
        } catch (err) {
          onError?.(err, event);
        }
      }
    } finally {
      running = false;
    }
  }

  const off = runtime.onTrigger((event) => {
    queue.push(event);
    void drain();
  });
  return () => {
    connected = false;
    queue.length = 0;
    off();
  };
}

function parseArgs(raw: string): Record<string, unknown> | null {
  try {
    const v: unknown = raw.trim() === "" ? {} : JSON.parse(raw);
    return typeof v === "object" && v !== null && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

function toToolMessage(toolCallId: string, r: InvokeResult): ToolMessage {
  const base = { id: `gentizer-${toolCallId}`, role: "tool" as const, toolCallId };
  if (r.ok) return { ...base, content: JSON.stringify(r.value) };
  return { ...base, content: JSON.stringify({ error: r.error }), error: `${r.error.code}: ${r.error.message}` };
}

/** 응답 tool 메시지가 없고 runtime 에 등록된 tool call 만 순서대로 실행 */
export async function runFrontendTools(runtime: AgentRuntime, messages: readonly Message[]): Promise<ToolMessage[]> {
  const answered = new Set(messages.flatMap((m) => (m.role === "tool" ? [m.toolCallId] : [])));
  const out: ToolMessage[] = [];
  for (const m of messages) {
    if (m.role !== "assistant" || !m.toolCalls) continue;
    for (const call of m.toolCalls) {
      if (answered.has(call.id)) continue;
      const name = call.function.name;
      if (!Object.hasOwn(runtime.manifest().actions, name)) continue;
      answered.add(call.id);
      const args = parseArgs(call.function.arguments);
      const result: InvokeResult = args
        ? await runtime.invoke(name, args)
        : { ok: false, error: { code: "INVALID_ARGS", message: "arguments 는 JSON object" } };
      out.push(toToolMessage(call.id, result));
    }
  }
  return out;
}

export interface RunWithFrontendToolsOptions extends RunAgentParameters {
  /** 기본 5 */
  maxRounds?: number;
}

/** runAgent → frontend tool 실행 → 결과를 메시지로 추가 → 다시 runAgent. 실행할 tool call 이 없으면 종료 */
export async function runWithFrontendTools(
  agent: AbstractAgent,
  runtime: AgentRuntime,
  options: RunWithFrontendToolsOptions = {},
): Promise<{ rounds: number; toolMessages: ToolMessage[] }> {
  const { maxRounds = 5, ...params } = options;
  const toolMessages: ToolMessage[] = [];
  let rounds = 0;
  while (rounds < maxRounds) {
    rounds++;
    await agent.runAgent({
      ...params,
      tools: [...toAgUiTools(runtime.manifest()), ...(params.tools ?? [])],
      context: [...toAgUiContext(runtime), ...(params.context ?? [])],
    });
    const results = await runFrontendTools(runtime, agent.messages);
    if (results.length === 0) break;
    agent.addMessages(results);
    toolMessages.push(...results);
  }
  return { rounds, toolMessages };
}
