import { describe, expect, test } from "vitest";
import { Observable } from "rxjs";
import { AbstractAgent, EventType, type BaseEvent, type RunAgentInput } from "@ag-ui/client";
import { createAgentRuntime } from "@gentizer/core";
import { runWithFrontendTools } from "../src/index.js";

/** round 마다 script(input) 이 낸 이벤트를 그대로 흘리는 가짜 agent */
class ScriptedAgent extends AbstractAgent {
  inputs: RunAgentInput[] = [];
  constructor(private script: (input: RunAgentInput, round: number) => BaseEvent[]) {
    super({ threadId: "th1" });
  }
  run(input: RunAgentInput): Observable<BaseEvent> {
    this.inputs.push(structuredClone(input));
    const events = [
      { type: EventType.RUN_STARTED, threadId: input.threadId, runId: input.runId },
      ...this.script(input, this.inputs.length),
      { type: EventType.RUN_FINISHED, threadId: input.threadId, runId: input.runId },
    ] as BaseEvent[];
    return new Observable((sub) => {
      for (const e of events) sub.next(e);
      sub.complete();
    });
  }
}

const toolCall = (id: string, name: string, args: string): BaseEvent[] =>
  [
    { type: EventType.TOOL_CALL_START, toolCallId: id, toolCallName: name, parentMessageId: `m-${id}` },
    { type: EventType.TOOL_CALL_ARGS, toolCallId: id, delta: args },
    { type: EventType.TOOL_CALL_END, toolCallId: id },
  ] as BaseEvent[];

const text = (id: string, s: string): BaseEvent[] =>
  [
    { type: EventType.TEXT_MESSAGE_START, messageId: id, role: "assistant" },
    { type: EventType.TEXT_MESSAGE_CONTENT, messageId: id, delta: s },
    { type: EventType.TEXT_MESSAGE_END, messageId: id },
  ] as BaseEvent[];

describe("runWithFrontendTools", () => {
  test("tool call round → 결과 메시지 추가 → text round 에서 종료", async () => {
    const rt = createAgentRuntime();
    rt.action("filter_set", { description: "필터" }, (a) => `set ${a.category}`);
    const agent = new ScriptedAgent((_, round) =>
      round === 1 ? toolCall("t1", "filter_set", '{"category":"shoes"}') : text("m2", "완료"),
    );
    const r = await runWithFrontendTools(agent, rt);
    expect(r.rounds).toBe(2);
    expect(r.toolMessages).toEqual([{ id: "gentizer-t1", role: "tool", toolCallId: "t1", content: '"set shoes"' }]);
    expect(agent.messages.some((m) => m.role === "tool" && m.toolCallId === "t1")).toBe(true);
    expect(agent.inputs[1]!.messages.find((m) => m.role === "tool")).toMatchObject({ toolCallId: "t1" });
    expect(agent.inputs[0]!.tools.map((t) => t.name)).toEqual(["filter_set"]);
  });

  test("maxRounds 도달 시 종료", async () => {
    const rt = createAgentRuntime();
    rt.action("ping", { description: "핑" }, () => "pong");
    let n = 0;
    const agent = new ScriptedAgent(() => toolCall(`t${++n}`, "ping", "{}"));
    const r = await runWithFrontendTools(agent, rt, { maxRounds: 3 });
    expect(r.rounds).toBe(3);
    expect(r.toolMessages).toHaveLength(3);
    expect(agent.inputs).toHaveLength(3);
  });

  test("round 마다 tools · context 재계산, 호출자 tools · context 유지", async () => {
    const rt = createAgentRuntime();
    let count = 0;
    rt.state("count", { description: "개수" }, () => count);
    rt.action("open", { description: "열기" }, () => {
      count++;
      rt.action("close", { description: "닫기" }, () => {});
    });
    const agent = new ScriptedAgent((_, round) => (round === 1 ? toolCall("t1", "open", "{}") : []));
    await runWithFrontendTools(agent, rt, {
      tools: [{ name: "backend", description: "b", parameters: {} }],
      context: [{ description: "extra", value: "1" }],
    });
    expect(agent.inputs.map((i) => i.tools.map((t) => t.name))).toEqual([
      ["open", "backend"],
      ["open", "close", "backend"],
    ]);
    expect(agent.inputs.map((i) => i.context.map((c) => c.value))).toEqual([
      ["0", "1"],
      ["1", "1"],
    ]);
  });
});
